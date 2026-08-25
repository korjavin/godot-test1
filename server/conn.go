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
	// msgRateBurst / msgRatePerSec bound how fast one peer may send. Signalling is
	// tiny and bursty — an offer, an answer and a handful of ICE candidates per
	// peer, then a heartbeat a second — so this is orders of magnitude above
	// honest traffic.
	//
	// It exists because `signal` is a 1:N amplifier and the read loop is otherwise
	// unmetered: a member (and every room code is public over /rooms, so that
	// means anyone) can fan 64 KB frames out to the rest of the room as fast as
	// the socket accepts them, and when their queues fill it is THEY who get
	// dropped with "peer too slow" while the flooder keeps its connection. So the
	// budget disconnects the SENDER, before Room ever sees the message.
	msgRateBurst  = 120
	msgRatePerSec = 40
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
	last := time.Now()

	for {
		typ, data, err := c.Read(ctx)
		if err != nil {
			return
		}

		now := time.Now()
		tokens = math.Min(float64(msgRateBurst), tokens+now.Sub(last).Seconds()*msgRatePerSec)
		last = now
		if tokens < 1 {
			c.Close(websocket.StatusPolicyViolation, "sending too fast") //nolint:errcheck
			return
		}
		tokens--

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
			me.send(mustJSON(map[string]any{"type": "error", "error": "unknown message type: " + msg.Type}))
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
