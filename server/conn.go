package main

// conn.go — the websocket layer. It owns exactly two jobs: turn a socket into a
// *Member, and translate inbound JSON into Room method calls. All lobby state
// lives in room.go.

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"log"
	"math"
	"net/http"
	"strings"
	"time"

	"github.com/coder/websocket"
)

const (
	// readLimit bounds a single client frame. SDP offers are a few KB; 64 KB is
	// generous and stops a peer from making the lobby allocate on demand.
	readLimit = 64 << 10
	// pingInterval reaps peers whose TCP connection died without a close frame —
	// without it a crashed master would hold its title forever.
	pingInterval = 20 * time.Second
	pingTimeout  = 10 * time.Second
	writeTimeout = 10 * time.Second
	// msgRateBurst / msgRatePerSec bound how fast one peer may send, IN BYTES.
	// Signalling is tiny and bursty — an offer, an answer and a handful of ICE
	// candidates per peer, then a heartbeat a second — so this is orders of
	// magnitude above honest traffic.
	//
	// It exists because `signal` is a 1:N amplifier and the read loop is otherwise
	// unmetered: a member (and every room code is public over /rooms, so that
	// means anyone) can fan frames out to the rest of the room as fast as the
	// socket accepts them, and when their queues fill it is THEY who get dropped
	// with "peer too slow" while the flooder keeps its connection. So the budget
	// disconnects the SENDER, before Room ever sees the message.
	//
	// BYTES, NOT MESSAGES, and that is the whole point: a per-message bucket let
	// through 130 x 64 KB frames before firing, which is ~8 MB fanned at every
	// other peer — whose queues are only sendBuffer (64) frames deep. Measured on
	// a 4-peer room, every victim was evicted inside 100 ms while the flooder was
	// still inside its budget, i.e. exactly the outcome this exists to prevent.
	// BUT BYTES ALONE ARE NOT ENOUGH, and that was a second, live hole: with no
	// minimum frame size a byte budget is a huge MESSAGE budget. 256 KB of burst
	// buys ~6900 ~38-byte broadcast `signal` frames and ~860/s sustained, each
	// fanned to every other member — far more than the sendBuffer (64) frames a
	// victim's queue holds, so `Member.send` killed the VICTIMS with "peer too
	// slow" while the flooder stayed inside its budget. Reproduced against a host
	// actively reading 500 frames/s (~1000x the honest relay rate): evicted in
	// 1.7 s, leaving the attacker alone in the room and elected master — i.e. a
	// room takeover that never casts a vote, so stallMasterSilence never sees it.
	//
	// So meter frames as well. Honest traffic is an offer, an answer and a handful
	// of ICE candidates per peer pair at join, then a 1 Hz heartbeat and the
	// occasional hero claim or stall report, so this is still orders of magnitude
	// clear of a real client.
	msgRateBurst    = 256 << 10
	msgRatePerSec   = 32 << 10
	frameRateBurst  = 120
	frameRatePerSec = 30
	// maxPayload bounds the opaque `signal` payload the lobby relays. The lobby
	// never inspects it, but it does re-frame it, and readLimit bounds the INBOUND
	// message rather than the outbound one: a 65509-byte payload is accepted at
	// exactly 65536 and relayed as 65562 bytes, past the 65535-byte default
	// inbound buffer of the Godot WebSocketPeer on the other end — so one message
	// drops every other peer in the room. SDP offers are a few KB.
	maxPayload = 32 << 10
)

// clientMsg is every message a client may send. Unknown types are answered with
// an error frame rather than a disconnect.
type clientMsg struct {
	Type    string          `json:"type"`
	To      string          `json:"to"`
	Payload json.RawMessage `json:"payload"`
	Hero    string          `json:"hero"`
	ID      string          `json:"id"`
}

// ServeWS upgrades the request and runs the peer until it disconnects.
//
//	GET /ws?room=<code>&name=<label>
//
// An empty or missing room creates a fresh one; the generated code comes back in
// the welcome frame.
func (h *Hub) ServeWS(w http.ResponseWriter, r *http.Request) {
	opts := &websocket.AcceptOptions{OriginPatterns: allowedOrigins}
	if len(allowedOrigins) == 1 && allowedOrigins[0] == "*" {
		// The lobby is deliberately public and unauthenticated — there is no cookie
		// or credential for a cross-origin page to abuse — so any page may connect
		// unless the operator narrows LOBBY_ALLOWED_ORIGINS.
		opts.InsecureSkipVerify = true
		opts.OriginPatterns = nil
	}
	c, err := websocket.Accept(w, r, opts)
	if err != nil {
		return // Accept already wrote a response.
	}
	c.SetReadLimit(readLimit)
	defer c.CloseNow() //nolint:errcheck // best-effort teardown

	// TRIM FIRST, then cap: trimming exists precisely to tolerate surrounding
	// whitespace, and slicing ahead of it eats real code characters instead —
	// "  ABC234" would come out as "ABC23" and be refused as malformed. The cap
	// is still one over codeLength so validCode refuses anything genuinely long
	// without it being carried any further.
	raw := strings.TrimSpace(r.URL.Query().Get("room"))
	if len(raw) > codeLength {
		raw = raw[:codeLength+1]
	}
	code := strings.ToUpper(raw)
	name := trimName(r.URL.Query().Get("name"))

	room, me, err := h.Join(code, name, newID())
	if err != nil {
		_ = writeJSON(r.Context(), c, map[string]any{"type": "error", "error": err.Error()})
		c.Close(websocket.StatusPolicyViolation, err.Error())
		return
	}
	defer room.Leave(me)

	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()
	go writePump(ctx, cancel, c, me)

	// Token bucket, refilled from the clock rather than a ticker so an idle peer
	// costs nothing.
	tokens := float64(msgRateBurst)
	frames := float64(frameRateBurst)
	last := time.Now()

	for {
		typ, data, err := c.Read(ctx)
		if err != nil {
			return
		}

		now := time.Now()
		elapsed := now.Sub(last).Seconds()
		tokens = math.Min(float64(msgRateBurst), tokens+elapsed*msgRatePerSec)
		frames = math.Min(float64(frameRateBurst), frames+elapsed*frameRatePerSec)
		last = now
		if tokens < float64(len(data)) || frames < 1 {
			c.Close(websocket.StatusPolicyViolation, "sending too fast") //nolint:errcheck
			return
		}
		tokens -= float64(len(data))
		frames--

		me.Touch()

		if typ != websocket.MessageText {
			continue
		}
		var msg clientMsg
		if err := json.Unmarshal(data, &msg); err != nil {
			me.send(mustJSON(map[string]any{"type": "error", "error": "malformed json"}))
			continue
		}
		switch msg.Type {
		case "signal":
			if len(msg.Payload) > maxPayload {
				me.send(mustJSON(map[string]any{"type": "error", "error": "payload too large"}))
				continue
			}
			room.Signal(me, msg.To, msg.Payload)
		case "hero":
			if err := room.SetHero(me, msg.Hero); err != nil {
				me.send(mustJSON(map[string]any{"type": "error", "error": err.Error()}))
			}
		case "stalled":
			room.ReportStalled(me, msg.ID)
		case "ping":
			me.send(mustJSON(map[string]any{"type": "pong"}))
		default:
			// The client's own string is NOT echoed: it is unvalidated input up
			// to readLimit, and this is a server-built frame.
			me.send(mustJSON(map[string]any{"type": "error", "error": "unknown message type"}))
		}
	}
}

// writePump drains the member's queue and keeps the connection alive. It exits —
// cancelling the read loop with it — on quit, a write error, or a dead ping.
func writePump(ctx context.Context, cancel context.CancelFunc, c *websocket.Conn, m *Member) {
	defer cancel()
	ticker := time.NewTicker(pingInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-m.Quit():
			c.Close(websocket.StatusPolicyViolation, "peer too slow") //nolint:errcheck
			return
		case frame := <-m.Out():
			wctx, wcancel := context.WithTimeout(ctx, writeTimeout)
			err := c.Write(wctx, websocket.MessageText, frame)
			wcancel()
			if err != nil {
				return
			}
		case <-ticker.C:
			pctx, pcancel := context.WithTimeout(ctx, pingTimeout)
			err := c.Ping(pctx)
			pcancel()
			if err != nil {
				return
			}
		}
	}
}

func writeJSON(ctx context.Context, c *websocket.Conn, v any) error {
	wctx, cancel := context.WithTimeout(ctx, writeTimeout)
	defer cancel()
	return c.Write(wctx, websocket.MessageText, mustJSON(v))
}

// newID returns an opaque per-connection peer id.
func newID() string {
	buf := make([]byte, 8)
	if _, err := rand.Read(buf); err != nil {
		log.Printf("lobby: rand failed: %v", err)
		panic(errors.New("no entropy"))
	}
	return hex.EncodeToString(buf)
}

// trimName bounds an attacker-supplied display name; it is echoed to every other
// peer, so it does not get to be unbounded.
func trimName(s string) string {
	// ToValidUTF8 AFTER the byte cap but BEFORE the empty check. After, because
	// the cap is a byte slice and can land mid-rune; before, because a name made
	// entirely of invalid UTF-8 is dropped to "" by it, and validating last would
	// hand that empty string to every peer instead of the "player" default.
	s = strings.TrimSpace(s)
	if len(s) > 32 {
		s = s[:32]
	}
	s = strings.ToValidUTF8(s, "")
	if s == "" {
		s = "player"
	}
	return s
}
