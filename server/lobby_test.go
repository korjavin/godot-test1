package main

// lobby_test.go — the acceptance criteria, run against real websockets over a
// real HTTP server. Two peers create/join a room by code and exchange arbitrary
// signalling payloads; both see membership events and a master announcement; and
// killing the master produces a new-master broadcast.

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"
)

type frame map[string]any

// peer is one test client.
type peer struct {
	t    *testing.T
	c    *websocket.Conn
	id   string
	room string
}

func newServer(t *testing.T) string {
	t.Helper()
	hub := NewHub()
	srv := httptest.NewServer(http.HandlerFunc(hub.ServeWS))
	t.Cleanup(srv.Close)
	return "ws" + strings.TrimPrefix(srv.URL, "http")
}

// dial connects and consumes the welcome frame.
func dial(t *testing.T, base, room, name string) *peer {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	c, _, err := websocket.Dial(ctx, base+"?room="+room+"&name="+name, nil)
	if err != nil {
		t.Fatalf("dial %s: %v", name, err)
	}
	t.Cleanup(func() { _ = c.CloseNow() })
	p := &peer{t: t, c: c}
	w := p.want("welcome")
	p.id = w["you"].(string)
	p.room = w["room"].(string)
	return p
}

// next reads one frame with a deadline.
func (p *peer) next() frame {
	p.t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_, data, err := p.c.Read(ctx)
	if err != nil {
		p.t.Fatalf("read: %v", err)
	}
	var f frame
	if err := json.Unmarshal(data, &f); err != nil {
		p.t.Fatalf("unmarshal %q: %v", data, err)
	}
	return f
}

// want reads until a frame of the given type arrives, so a test asserting on the
// master broadcast is not tripped by the peer_leave that precedes it.
func (p *peer) want(typ string) frame {
	p.t.Helper()
	for i := 0; i < 10; i++ {
		f := p.next()
		if f["type"] == typ {
			return f
		}
	}
	p.t.Fatalf("no %q frame after 10 frames", typ)
	return nil
}

func (p *peer) send(v any) {
	p.t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	b, _ := json.Marshal(v)
	if err := p.c.Write(ctx, websocket.MessageText, b); err != nil {
		p.t.Fatalf("write: %v", err)
	}
}

// TestSignalAndMembership is acceptance criterion 1: two clients create/join a
// room by code and exchange arbitrary signalling payloads, seeing membership
// events and a master announcement.
func TestSignalAndMembership(t *testing.T) {
	base := newServer(t)

	a := dial(t, base, "", "alice")
	if a.room == "" || len(a.room) != codeLength {
		t.Fatalf("expected a generated room code, got %q", a.room)
	}
	b := dial(t, base, a.room, "bob")
	if b.room != a.room {
		t.Fatalf("bob joined %q, wanted %q", b.room, a.room)
	}

	join := a.want("peer_join")
	if got := join["peer"].(map[string]any)["id"]; got != b.id {
		t.Fatalf("peer_join carried %v, wanted %v", got, b.id)
	}

	// The lobby never inspects the payload — a nested object with odd keys must
	// arrive byte-identical at the other end.
	payload := map[string]any{"sdp": "v=0\r\no=- 1 2 IN IP4 0.0.0.0", "n": float64(42)}
	a.send(map[string]any{"type": "signal", "to": b.id, "payload": payload})
	sig := b.want("signal")
	if sig["from"] != a.id {
		t.Fatalf("signal from %v, wanted %v", sig["from"], a.id)
	}
	got, _ := json.Marshal(sig["payload"])
	want, _ := json.Marshal(payload)
	if string(got) != string(want) {
		t.Fatalf("payload round-trip: got %s, wanted %s", got, want)
	}

	// An empty `to` broadcasts to the rest of the room.
	b.send(map[string]any{"type": "signal", "payload": "hello everyone"})
	if bc := a.want("signal"); bc["payload"] != "hello everyone" {
		t.Fatalf("broadcast payload: %v", bc["payload"])
	}
}

// TestMasterIsOldestAndReElects is acceptance criterion 2: the master is the
// oldest surviving member, and killing it broadcasts a new one.
func TestMasterIsOldestAndReElects(t *testing.T) {
	base := newServer(t)

	a := dial(t, base, "", "alice")
	b := dial(t, base, a.room, "bob")
	c := dial(t, base, a.room, "carol")

	// b and c learned the master from their welcome frames; assert on c's, which
	// saw the room with two members already in it.
	if m := b.want("peer_join"); m["peer"].(map[string]any)["id"] != c.id {
		t.Fatalf("bob missed carol's join")
	}

	_ = a.c.Close(websocket.StatusNormalClosure, "bye")
	for _, p := range []*peer{b, c} {
		if m := p.want("master"); m["id"] != b.id {
			t.Fatalf("after alice left, master = %v, wanted bob (%v)", m["id"], b.id)
		}
	}
}

// TestStallQuorumReElects covers the phase-5 hook: the lobby re-elects once
// strictly more than half of the non-master members report the master stalled.
func TestStallQuorumReElects(t *testing.T) {
	base := newServer(t)

	a := dial(t, base, "", "alice")
	b := dial(t, base, a.room, "bob")
	c := dial(t, base, a.room, "carol")

	// One of two non-master members is not a quorum.
	b.send(map[string]any{"type": "stalled", "id": a.id})
	b.send(map[string]any{"type": "signal", "to": b.id, "payload": "ping"})
	// Nothing but our own frames should be waiting; the next thing bob sees after
	// carol's join is that echo, not a master change.
	_ = b.want("peer_join")
	if f := b.next(); f["type"] == "master" {
		t.Fatalf("re-elected on a single report: %v", f)
	}

	// The second report crosses the quorum.
	c.send(map[string]any{"type": "stalled", "id": a.id})
	if m := c.want("master"); m["id"] != b.id {
		t.Fatalf("after quorum, master = %v, wanted bob (%v)", m["id"], b.id)
	}
	// The stalled peer is told too, and is not re-elected on the next change.
	if m := a.want("master"); m["id"] != b.id {
		t.Fatalf("alice saw master = %v", m["id"])
	}
}

// TestHeroAssignments covers the single source of truth for hero picking.
func TestHeroAssignments(t *testing.T) {
	base := newServer(t)

	a := dial(t, base, "", "alice")
	b := dial(t, base, a.room, "bob")
	_ = a.want("peer_join")

	a.send(map[string]any{"type": "hero", "hero": "windman"})
	if h := b.want("heroes")["heroes"].(map[string]any); h["windman"] != a.id {
		t.Fatalf("windman held by %v, wanted alice (%v)", h["windman"], a.id)
	}

	b.send(map[string]any{"type": "hero", "hero": "windman"})
	if e := b.want("error"); e["error"] != errHeroTaken.Error() {
		t.Fatalf("double claim error: %v", e["error"])
	}
	b.send(map[string]any{"type": "hero", "hero": "nobody"})
	if e := b.want("error"); e["error"] != errUnknownHero.Error() {
		t.Fatalf("unknown hero error: %v", e["error"])
	}

	// A claim replaces the claimant's previous hero rather than stacking.
	a.send(map[string]any{"type": "hero", "hero": "primm"})
	h := b.want("heroes")["heroes"].(map[string]any)
	if len(h) != 1 || h["primm"] != a.id {
		t.Fatalf("expected only primm held by alice, got %v", h)
	}

	// Leaving releases the hero.
	_ = a.c.Close(websocket.StatusNormalClosure, "bye")
	if h := b.want("heroes")["heroes"].(map[string]any); len(h) != 0 {
		t.Fatalf("hero not released on leave: %v", h)
	}
}

// TestRoomIsCappedAtFour keeps the lobby honest about the game's 4-player limit.
func TestRoomIsCappedAtFour(t *testing.T) {
	base := newServer(t)

	a := dial(t, base, "", "p1")
	for i := 0; i < MaxMembers-1; i++ {
		dial(t, base, a.room, "pn")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	c, _, err := websocket.Dial(ctx, base+"?room="+a.room+"&name=spare", nil)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer c.CloseNow() //nolint:errcheck
	_, data, err := c.Read(ctx)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	var f frame
	_ = json.Unmarshal(data, &f)
	if f["type"] != "error" || f["error"] != errRoomFull.Error() {
		t.Fatalf("fifth peer got %v, wanted a room-full error", f)
	}
}

// TestEmptyRoomIsCollected proves the lobby holds no state after everyone leaves —
// there is no database and no room ever needs cleaning up by hand.
func TestEmptyRoomIsCollected(t *testing.T) {
	hub := NewHub()
	room, m, err := hub.Join("", "solo", "id-1")
	if err != nil {
		t.Fatalf("join: %v", err)
	}
	if hub.Rooms() != 1 {
		t.Fatalf("expected 1 room, got %d", hub.Rooms())
	}
	room.Leave(m)
	if hub.Rooms() != 0 {
		t.Fatalf("expected the empty room to be collected, got %d", hub.Rooms())
	}
}

// TestJoiningAnUnknownCodeCreatesIt keeps invite codes usable without a
// create-then-share round trip: whoever arrives first makes the room.
func TestJoiningAnUnknownCodeCreatesIt(t *testing.T) {
	base := newServer(t)
	p := dial(t, base, "ABC234", "first")
	if p.room != "ABC234" {
		t.Fatalf("room = %q, wanted ABC234", p.room)
	}
}

// TestMalformedRoomCodeRejected: the room map is keyed by invite codes, so a
// client does not get to choose the key or its length.
func TestMalformedRoomCodeRejected(t *testing.T) {
	base := newServer(t)
	for _, code := range []string{"abc", "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "AAAAA0", "AAAAAAA"} {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		c, _, err := websocket.Dial(ctx, base+"?room="+code+"&name=x", nil)
		if err != nil {
			cancel()
			t.Fatalf("dial %q: %v", code, err)
		}
		_, data, err := c.Read(ctx)
		if err != nil {
			cancel()
			t.Fatalf("read %q: %v", code, err)
		}
		var f frame
		_ = json.Unmarshal(data, &f)
		if f["type"] != "error" || f["error"] != errBadCode.Error() {
			t.Errorf("code %q was accepted: %v", code, f)
		}
		_ = c.CloseNow()
		cancel()
	}
}

// TestICECORS: the game is served from a different origin than the lobby, so
// /ice must carry Access-Control-Allow-Origin — and, because the body is the TURN
// credentials, must honour the same allowlist as the websocket upgrade.
func TestICECORS(t *testing.T) {
	restore := allowedOrigins
	t.Cleanup(func() { allowedOrigins = restore })

	cases := []struct {
		allow  []string
		origin string
		want   string
	}{
		{[]string{"*"}, "https://korjavin.github.io", "*"},
		{[]string{"*"}, "", "*"},
		{[]string{"korjavin.github.io"}, "https://korjavin.github.io", "https://korjavin.github.io"},
		{[]string{"korjavin.github.io"}, "https://evil.example", ""},
		{[]string{"*.example.com"}, "https://game.example.com", "https://game.example.com"},
		{[]string{"korjavin.github.io"}, "", ""},
	}
	for _, tc := range cases {
		allowedOrigins = tc.allow
		req := httptest.NewRequest(http.MethodGet, "/ice", nil)
		if tc.origin != "" {
			req.Header.Set("Origin", tc.origin)
		}
		rec := httptest.NewRecorder()
		iceHandler(rec, req)
		if got := rec.Header().Get("Access-Control-Allow-Origin"); got != tc.want {
			t.Errorf("allow=%v origin=%q: header = %q, wanted %q", tc.allow, tc.origin, got, tc.want)
		}
		if rec.Code != http.StatusOK {
			t.Errorf("status %d", rec.Code)
		}
	}
}
