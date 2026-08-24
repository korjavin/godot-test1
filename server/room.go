package main

// room.go — the whole lobby state machine: rooms, membership, master election,
// hero assignments and signal fan-out. Deliberately free of any network types so
// it can be exercised directly by tests; the websocket layer lives in conn.go and
// only ever hands a *Member its outbound byte channel.
//
// There is no persistence and none is wanted: a lobby restart drops every room and
// clients simply re-create them from their invite code.

import (
	"crypto/rand"
	"encoding/json"
	"errors"
	"math"
	"strings"
	"sync"
)

// MaxMembers caps a room at the game's 4 players.
const MaxMembers = 4

// Heroes are the four playable characters (mirrors CHARACTERS in
// scripts/player_controller.gd). The lobby is the single source of truth for who
// holds which one so join-time hero picking has somewhere to ask.
var Heroes = []string{"windman", "primm", "teibi", "phoboman"}

// codeAlphabet omits 0/O/1/I/L so an invite code can be read aloud.
const codeAlphabet = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"

const codeLength = 6

// sendBuffer is how far behind a peer may fall before we consider it broken.
// Signalling traffic is tiny and bursty; a peer that cannot drain 64 messages is
// not coming back, so we kill it rather than silently drop an ICE candidate.
const sendBuffer = 64

var (
	errRoomFull    = errors.New("room is full")
	errUnknownHero = errors.New("unknown hero")
	errHeroTaken   = errors.New("hero already taken")
	errBadCode     = errors.New("malformed room code")
)

// validCode reports whether s is a well-formed invite code. Anything else is
// refused rather than silently becoming a room: the room map is keyed by these
// strings, so without the check a client picks both the key and its length.
func validCode(s string) bool {
	if len(s) != codeLength {
		return false
	}
	for _, c := range s {
		if !strings.ContainsRune(codeAlphabet, c) {
			return false
		}
	}
	return true
}

// Member is one connected peer.
type Member struct {
	ID   string
	Name string

	seq     uint64 // global join order; the lowest surviving seq is the master
	stalled bool   // quorum-reported stalled — never eligible for master again

	out      chan []byte
	quit     chan struct{}
	quitOnce sync.Once
}

// send queues a frame for the peer. A full buffer means the peer is not draining,
// so we tear it down instead of blocking the whole room behind it.
func (m *Member) send(b []byte) {
	select {
	case m.out <- b:
	case <-m.quit:
	default:
		m.kill()
	}
}

// kill signals the peer's writer to stop; the connection layer then closes the
// socket, which runs the normal Leave path.
func (m *Member) kill() {
	m.quitOnce.Do(func() { close(m.quit) })
}

// Out is the peer's outbound frame queue, drained by the connection layer.
func (m *Member) Out() <-chan []byte { return m.out }

// Quit closes when the member must disconnect.
func (m *Member) Quit() <-chan struct{} { return m.quit }

// peerInfo is the wire shape of a member.
type peerInfo struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

// Room is one invite code's worth of peers.
type Room struct {
	h    *Hub
	Code string

	members map[string]*Member
	heroes  map[string]string // hero name -> member id
	master  string

	// reports[subject] is the set of member ids that reported subject stalled.
	reports map[string]map[string]bool
}

// Hub owns every room.
//
// ponytail: one mutex guards every room in the process. Rooms hold at most 4
// members and signalling is a handful of messages per join, so contention is not
// a real quantity here; shard per-room if the lobby ever holds thousands of rooms.
type Hub struct {
	mu    sync.Mutex
	rooms map[string]*Room
	seq   uint64
}

// NewHub returns an empty hub.
func NewHub() *Hub {
	return &Hub{rooms: make(map[string]*Room)}
}

// Rooms reports the number of live rooms (used by /healthz and tests).
func (h *Hub) Rooms() int {
	h.mu.Lock()
	defer h.mu.Unlock()
	return len(h.rooms)
}

// newCode returns an unused invite code. Caller holds h.mu.
func (h *Hub) newCodeLocked() (string, error) {
	buf := make([]byte, codeLength)
	for try := 0; try < 20; try++ {
		if _, err := rand.Read(buf); err != nil {
			return "", err
		}
		out := make([]byte, codeLength)
		for i, b := range buf {
			out[i] = codeAlphabet[int(b)%len(codeAlphabet)]
		}
		code := string(out)
		if _, exists := h.rooms[code]; !exists {
			return code, nil
		}
	}
	return "", errors.New("could not allocate a room code")
}

// Join places a new member in the room with the given code, creating the room if
// the code is empty or unknown. It sends the welcome frame to the joiner and a
// peer_join to everyone else, and announces a master if the room just got one.
func (h *Hub) Join(code, name, id string) (*Room, *Member, error) {
	h.mu.Lock()
	defer h.mu.Unlock()

	var room *Room
	if code != "" && !validCode(code) {
		return nil, nil, errBadCode
	}
	if code == "" {
		fresh, err := h.newCodeLocked()
		if err != nil {
			return nil, nil, err
		}
		code = fresh
	}
	room = h.rooms[code]
	if room == nil {
		room = &Room{
			h:       h,
			Code:    code,
			members: make(map[string]*Member),
			heroes:  make(map[string]string),
			reports: make(map[string]map[string]bool),
		}
		h.rooms[code] = room
	}
	if len(room.members) >= MaxMembers {
		return nil, nil, errRoomFull
	}

	h.seq++
	m := &Member{
		ID:   id,
		Name: name,
		seq:  h.seq,
		out:  make(chan []byte, sendBuffer),
		quit: make(chan struct{}),
	}
	room.members[m.ID] = m

	// Welcome goes out before any broadcast so the joiner's first frame always
	// describes the room it is entering, master included.
	changed := room.electLocked()
	m.send(mustJSON(map[string]any{
		"type":    "welcome",
		"you":     m.ID,
		"room":    room.Code,
		"master":  room.master,
		"members": room.peersLocked(),
		"heroes":  room.heroesLocked(),
		"pool":    Heroes,
	}))
	room.broadcastLocked(mustJSON(map[string]any{
		"type": "peer_join",
		"peer": peerInfo{ID: m.ID, Name: m.Name},
	}), m.ID)
	if changed {
		// The joiner already learned the master from its welcome frame.
		room.announceMasterLocked(m.ID)
	}
	return room, m, nil
}

// Leave removes a member, releases its hero, discards its stall reports and
// re-elects if it was the master.
func (r *Room) Leave(m *Member) {
	r.h.mu.Lock()
	defer r.h.mu.Unlock()

	if _, ok := r.members[m.ID]; !ok {
		return
	}
	delete(r.members, m.ID)
	m.kill()

	heroChanged := false
	for hero, holder := range r.heroes {
		if holder == m.ID {
			delete(r.heroes, hero)
			heroChanged = true
		}
	}
	// A departed peer's stall vote no longer counts toward quorum.
	delete(r.reports, m.ID)
	for _, set := range r.reports {
		delete(set, m.ID)
	}

	if len(r.members) == 0 {
		delete(r.h.rooms, r.Code)
		return
	}

	r.broadcastLocked(mustJSON(map[string]any{"type": "peer_leave", "id": m.ID}), "")
	if heroChanged {
		r.broadcastLocked(mustJSON(map[string]any{"type": "heroes", "heroes": r.heroesLocked()}), "")
	}
	if r.electLocked() {
		r.announceMasterLocked("")
	}
}

// Signal relays an opaque payload. An empty `to` broadcasts to the rest of the
// room; the lobby never inspects the payload — that is the whole point.
func (r *Room) Signal(from *Member, to string, payload json.RawMessage) {
	r.h.mu.Lock()
	defer r.h.mu.Unlock()

	frame := mustJSON(map[string]any{
		"type":    "signal",
		"from":    from.ID,
		"payload": payload,
	})
	if to == "" {
		r.broadcastLocked(frame, from.ID)
		return
	}
	if target, ok := r.members[to]; ok {
		target.send(frame)
	}
}

// SetHero claims a hero for the member, or releases theirs when hero is empty.
func (r *Room) SetHero(m *Member, hero string) error {
	r.h.mu.Lock()
	defer r.h.mu.Unlock()

	if hero != "" {
		known := false
		for _, h := range Heroes {
			if h == hero {
				known = true
				break
			}
		}
		if !known {
			return errUnknownHero
		}
		if holder, taken := r.heroes[hero]; taken && holder != m.ID {
			return errHeroTaken
		}
	}
	for h, holder := range r.heroes {
		if holder == m.ID {
			delete(r.heroes, h)
		}
	}
	if hero != "" {
		r.heroes[hero] = m.ID
	}
	r.broadcastLocked(mustJSON(map[string]any{"type": "heroes", "heroes": r.heroesLocked()}), "")
	return nil
}

// ReportStalled records one peer's vote that the current master has stalled. The
// detection is client-side (phase 5); the lobby only counts votes and re-elects
// once strictly more than half of the non-master members agree.
func (r *Room) ReportStalled(reporter *Member, subject string) {
	r.h.mu.Lock()
	defer r.h.mu.Unlock()

	if subject == "" || subject != r.master || reporter.ID == subject {
		return
	}
	if _, ok := r.members[reporter.ID]; !ok {
		return
	}
	set := r.reports[subject]
	if set == nil {
		set = make(map[string]bool)
		r.reports[subject] = set
	}
	set[reporter.ID] = true

	others := len(r.members) - 1
	if others < 1 || len(set)*2 <= others {
		return
	}
	if target, ok := r.members[subject]; ok {
		target.stalled = true
	}
	delete(r.reports, subject)
	if r.electLocked() {
		r.announceMasterLocked("")
	}
}

// electLocked names the oldest surviving non-stalled member as master and reports
// whether that changed anything.
func (r *Room) electLocked() bool {
	best, bestSeq := "", uint64(math.MaxUint64)
	for id, m := range r.members {
		if m.stalled {
			continue
		}
		if m.seq < bestSeq {
			best, bestSeq = id, m.seq
		}
	}
	// Every remaining member has been reported stalled: rather than leave the room
	// permanently master-less, forgive everyone and elect from scratch.
	if best == "" && len(r.members) > 0 {
		for _, m := range r.members {
			m.stalled = false
		}
		r.reports = make(map[string]map[string]bool)
		for id, m := range r.members {
			if m.seq < bestSeq {
				best, bestSeq = id, m.seq
			}
		}
	}
	if best == r.master {
		return false
	}
	r.master = best
	return true
}

func (r *Room) announceMasterLocked(except string) {
	r.broadcastLocked(mustJSON(map[string]any{"type": "master", "id": r.master}), except)
}

// broadcastLocked sends to every member except `except` (pass "" for everyone).
func (r *Room) broadcastLocked(frame []byte, except string) {
	for id, m := range r.members {
		if id == except {
			continue
		}
		m.send(frame)
	}
}

func (r *Room) peersLocked() []peerInfo {
	out := make([]peerInfo, 0, len(r.members))
	for _, m := range r.members {
		out = append(out, peerInfo{ID: m.ID, Name: m.Name})
	}
	return out
}

func (r *Room) heroesLocked() map[string]string {
	out := make(map[string]string, len(r.heroes))
	for h, id := range r.heroes {
		out[h] = id
	}
	return out
}

// Master reports the current master id (tests and diagnostics).
func (r *Room) Master() string {
	r.h.mu.Lock()
	defer r.h.mu.Unlock()
	return r.master
}

// mustJSON marshals frames we build ourselves out of plain maps and known types,
// so a failure here is a programming error, not a runtime condition.
func mustJSON(v any) []byte {
	b, err := json.Marshal(v)
	if err != nil {
		panic(err)
	}
	return b
}
