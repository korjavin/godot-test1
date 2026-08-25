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
	base, _ := newServerHub(t)
	return base
}

// newServerHub is newServer for the one test that has to reach past the wire and
// touch lobby state directly (ageing a stall vote — there is no clock to inject).
func newServerHub(t *testing.T) (string, *Hub) {
	t.Helper()
	hub := NewHub()
	srv := httptest.NewServer(http.HandlerFunc(hub.ServeWS))
	t.Cleanup(srv.Close)
	return "ws" + strings.TrimPrefix(srv.URL, "http"), hub
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

// silence backdates one member's lastSeen so the lobby believes it has gone
// quiet, without sleeping for stallMasterSilence. Same "age it in place" trick
// TestStallVotesExpire uses on the votes themselves.
func silence(hub *Hub, code, id string) {
	hub.mu.Lock()
	defer hub.mu.Unlock()
	if m := hub.rooms[code].members[id]; m != nil {
		m.lastSeen.Store(time.Now().Add(-2 * stallMasterSilence).UnixNano())
	}
}

// TestStallQuorumReElects covers the phase-5 hook: the lobby re-elects once
// strictly more than half of the non-master members report the master stalled
// AND the lobby has itself heard nothing from that master.
func TestStallQuorumReElects(t *testing.T) {
	base, hub := newServerHub(t)

	a := dial(t, base, "", "alice")
	b := dial(t, base, a.room, "bob")
	c := dial(t, base, a.room, "carol")
	silence(hub, a.room, a.id)

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

// TestStallVotesExpire pins the TTL: a vote is evidence about right now, so a
// stale one must not add up with a fresh one from a different peer. Without the
// prune in ReportStalled, two peers that each hiccuped once — an hour apart, with
// a perfectly healthy master in between — reach quorum and depose it.
func TestStallVotesExpire(t *testing.T) {
	base, hub := newServerHub(t)

	a := dial(t, base, "", "alice")
	b := dial(t, base, a.room, "bob")
	c := dial(t, base, a.room, "carol")
	_ = b.want("peer_join")
	silence(hub, a.room, a.id)

	b.send(map[string]any{"type": "stalled", "id": a.id})
	// Round-trip a frame so bob's vote is definitely recorded before we age it.
	b.send(map[string]any{"type": "ping"})
	_ = b.want("pong")

	// Age bob's vote past the TTL, in place — there is no clock to inject and
	// sleeping for stallVoteTTL would make this the slowest test in the file.
	hub.mu.Lock()
	for _, set := range hub.rooms[a.room].reports {
		for id := range set {
			set[id] = time.Now().Add(-2 * stallVoteTTL)
		}
	}
	hub.mu.Unlock()

	// Carol's fresh vote is now the ONLY live one, and one of two is not a quorum.
	c.send(map[string]any{"type": "stalled", "id": a.id})
	c.send(map[string]any{"type": "signal", "to": c.id, "payload": "ping"})
	if f := c.next(); f["type"] == "master" {
		t.Fatalf("an expired vote still counted toward quorum: %v", f)
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

// codes is the invite codes ListRooms currently advertises, for assertions that
// only care about which rooms are on the list.
func codes(rooms []RoomInfo) []string {
	out := make([]string, 0, len(rooms))
	for _, r := range rooms {
		out = append(out, r.Code)
	}
	return out
}

// TestListRoomsTracksMembership is the public room list's acceptance criterion:
// EVERY open room is listed (rooms are public by default — there is no opt-in),
// the member count follows joins and leaves, a room that fills up drops off the
// list, and the last member leaving takes the room with it.
func TestListRoomsTracksMembership(t *testing.T) {
	hub := NewHub()
	if got := hub.ListRooms(); len(got) != 0 {
		t.Fatalf("fresh hub listed %v", codes(got))
	}

	// Create — one member, immediately listed with no opt-in of any kind.
	room, host, err := hub.Join("", "host", "id-1")
	if err != nil {
		t.Fatalf("join: %v", err)
	}
	got := hub.ListRooms()
	if len(got) != 1 || got[0].Code != room.Code || got[0].Members != 1 {
		t.Fatalf("after create: %+v", got)
	}
	if len(got[0].Heroes) != 0 {
		t.Fatalf("nobody has claimed a hero yet: %v", got[0].Heroes)
	}

	// Join — the count follows, and embodied heroes show up so the list can say
	// who is already in the room.
	_, second, err := hub.Join(room.Code, "second", "id-2")
	if err != nil {
		t.Fatalf("join 2: %v", err)
	}
	if err := room.SetHero(second, "primm"); err != nil {
		t.Fatalf("set hero: %v", err)
	}
	if err := room.SetHero(host, "windman"); err != nil {
		t.Fatalf("set hero: %v", err)
	}
	got = hub.ListRooms()
	if len(got) != 1 || got[0].Members != 2 {
		t.Fatalf("after second join: %+v", got)
	}
	// Sorted, so an unchanged room does not reshuffle between refreshes.
	if len(got[0].Heroes) != 2 || got[0].Heroes[0] != "primm" || got[0].Heroes[1] != "windman" {
		t.Fatalf("heroes = %v, wanted [primm windman]", got[0].Heroes)
	}

	// Fill it — a full room is not joinable, so it must not be offered.
	if _, _, err := hub.Join(room.Code, "third", "id-3"); err != nil {
		t.Fatalf("join 3: %v", err)
	}
	_, fourth, err := hub.Join(room.Code, "fourth", "id-4")
	if err != nil {
		t.Fatalf("join 4: %v", err)
	}
	if got := hub.ListRooms(); len(got) != 0 {
		t.Fatalf("a full room was listed: %+v", got)
	}

	// One leaves — a seat opened, so the room is joinable and listed again.
	room.Leave(fourth)
	got = hub.ListRooms()
	if len(got) != 1 || got[0].Members != 3 {
		t.Fatalf("after a leave: %+v", got)
	}

	// Everybody leaves — the room is collected, so nothing is left to list.
	for _, m := range []*Member{host, second} {
		room.Leave(m)
	}
	if got := hub.ListRooms(); len(got) != 1 || got[0].Members != 1 {
		t.Fatalf("expected the last member's room still listed: %+v", got)
	}
	for _, m := range room.members {
		room.Leave(m)
	}
	if got := hub.ListRooms(); len(got) != 0 {
		t.Fatalf("an emptied room was still listed: %v", codes(got))
	}
}

// TestListRoomsSkipsMemberlessRoom guards the invariant the listing depends on:
// a room with no members is a room mid-teardown and must never be advertised.
// `Leave` deletes such a room under the same mutex, so this state is unreachable
// through the public API today — it is built by hand precisely because the check
// exists to survive a future path that does not hold that property.
func TestListRoomsSkipsMemberlessRoom(t *testing.T) {
	hub := NewHub()
	hub.rooms["ZZZZZZ"] = &Room{
		h:       hub,
		Code:    "ZZZZZZ",
		members: make(map[string]*Member),
		heroes:  make(map[string]string),
		reports: make(map[string]map[string]time.Time),
	}
	if got := hub.ListRooms(); len(got) != 0 {
		t.Fatalf("a member-less room was listed: %+v", got)
	}
}

// TestRoomsEndpoint checks the wire shape the game parses, plus the CORS header
// it needs to be readable at all from the GitHub Pages origin.
func TestRoomsEndpoint(t *testing.T) {
	restore := allowedOrigins
	t.Cleanup(func() { allowedOrigins = restore })
	allowedOrigins = []string{"korjavin.github.io"}

	hub := NewHub()
	room, m, err := hub.Join("", "host", "id-1")
	if err != nil {
		t.Fatalf("join: %v", err)
	}
	if err := room.SetHero(m, "teibi"); err != nil {
		t.Fatalf("set hero: %v", err)
	}

	req := httptest.NewRequest(http.MethodGet, "/rooms", nil)
	req.Header.Set("Origin", "https://korjavin.github.io")
	rec := httptest.NewRecorder()
	hub.roomsHandler(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status %d", rec.Code)
	}
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "https://korjavin.github.io" {
		t.Errorf("CORS header = %q", got)
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-store" {
		t.Errorf("Cache-Control = %q, wanted no-store", got)
	}

	var body struct {
		Rooms []RoomInfo `json:"rooms"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("unmarshal %q: %v", rec.Body.String(), err)
	}
	if len(body.Rooms) != 1 {
		t.Fatalf("rooms = %+v", body.Rooms)
	}
	if body.Rooms[0].Code != room.Code || body.Rooms[0].Members != 1 {
		t.Errorf("room = %+v, wanted %s with 1 member", body.Rooms[0], room.Code)
	}
	if len(body.Rooms[0].Heroes) != 1 || body.Rooms[0].Heroes[0] != "teibi" {
		t.Errorf("heroes = %v, wanted [teibi]", body.Rooms[0].Heroes)
	}

	// An unlisted origin gets no header, exactly like /ice.
	req = httptest.NewRequest(http.MethodGet, "/rooms", nil)
	req.Header.Set("Origin", "https://evil.example")
	rec = httptest.NewRecorder()
	hub.roomsHandler(rec, req)
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "" {
		t.Errorf("evil origin got %q", got)
	}
}

// TestStallQuorumNeedsSilentMaster is the negative control for
// stallMasterSilence, and it covers a live griefing route rather than a
// hypothetical: room codes are public over GET /rooms, "strictly more than half
// the non-master members" is ONE vote in a two-member room, and the client trusts
// whoever is master with pickup arbitration, crocodile sync and the world seed.
// So a stranger joining a solo host must not be able to take the room with a
// single frame while the host is heartbeating normally.
func TestStallQuorumNeedsSilentMaster(t *testing.T) {
	base, hub := newServerHub(t)

	host := dial(t, base, "", "host")
	intruder := dial(t, base, host.room, "intruder")
	_ = host.want("peer_join")

	// The host is talking (its 1 Hz heartbeat is a signal frame), so the lobby
	// can see for itself that the report is false.
	host.send(map[string]any{"type": "signal", "payload": "hb"})
	_ = intruder.want("signal")

	intruder.send(map[string]any{"type": "stalled", "id": host.id})
	intruder.send(map[string]any{"type": "ping"})
	if f := intruder.want("pong"); f["type"] != "pong" {
		t.Fatalf("wanted pong, got %v", f)
	}
	hub.mu.Lock()
	master := hub.rooms[host.room].master
	hub.mu.Unlock()
	if master != host.id {
		t.Fatalf("a single vote against a live master took the room: master = %v, host = %v", master, host.id)
	}

	// ...and once the host really does go quiet, the same vote works. A
	// re-send is needed because the refused one is still in the set but the
	// count only runs when a report arrives.
	silence(hub, host.room, host.id)
	intruder.send(map[string]any{"type": "stalled", "id": host.id})
	if m := intruder.want("master"); m["id"] != intruder.id {
		t.Fatalf("after the master went silent, master = %v, wanted %v", m["id"], intruder.id)
	}
}

// TestTinyFrameFloodEvictsTheFlooderNotTheRoom is the negative control for the
// frame-rate bucket. The byte bucket alone did not bound MESSAGE count, so a
// stream of tiny broadcast `signal` frames stayed inside its 256 KB budget while
// fanning out enough frames to overflow every other member's 64-deep send queue —
// `Member.send` then killed the VICTIMS with "peer too slow", leaving the flooder
// alone in the room and elected master without a single stall vote being cast.
//
// The flood is deliberately sized to stay WELL under msgRateBurst bytes (asserted
// below), so the only thing that can refuse it is the frame bucket: remove that
// and this test fails with the flooder still happily connected.
func TestTinyFrameFloodEvictsTheFlooderNotTheRoom(t *testing.T) {
	base, hub := newServerHub(t)
	host := dial(t, base, "", "host")
	flooder := dial(t, base, host.room, "flooder")
	host.want("peer_join")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	body, _ := json.Marshal(map[string]any{"type": "signal", "payload": json.RawMessage(`1`)})
	// A LITERAL count, not one derived from frameRateBurst: deriving it makes the
	// flood grow with the constant, so raising the constant to disable the bucket
	// would also make the flood pass the byte budget and the test would fail for
	// the wrong reason instead of catching the removal.
	const frames = 3000
	if frames <= frameRateBurst {
		t.Fatalf("flood of %d frames no longer exceeds frameRateBurst (%d)", frames, frameRateBurst)
	}
	if total := len(body) * frames; total >= msgRateBurst {
		t.Fatalf("flood of %d bytes is inside the BYTE budget (%d) — the test would "+
			"pass on the byte bucket alone and prove nothing", total, msgRateBurst)
	}
	for i := 0; i < frames; i++ {
		// The write fails once the lobby closes the socket, which is the intended
		// outcome — stop there rather than failing.
		if err := flooder.c.Write(ctx, websocket.MessageText, body); err != nil {
			break
		}
	}

	// Read until the socket errors: that is the lobby's close frame arriving.
	rctx, rcancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer rcancel()
	for {
		if _, _, err := flooder.c.Read(rctx); err != nil {
			if rctx.Err() != nil {
				t.Fatal("the lobby never refused the flood — the frame bucket is not firing")
			}
			break
		}
	}

	// `Leave` runs in the flooder's own goroutine after the close, so settle first.
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		hub.mu.Lock()
		r := hub.rooms[host.room]
		var names []string
		if r != nil {
			for _, m := range r.members {
				names = append(names, m.Name)
			}
		}
		hub.mu.Unlock()
		if len(names) == 1 && names[0] == "host" {
			return // Flooder gone, host still in its own room.
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatal("the flooder was not evicted, or it took the host down with it")
}
