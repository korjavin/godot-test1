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
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"
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

// stallVoteTTL is how long one peer's "the master has stalled" vote counts
// toward a quorum. Roughly 5x the client's STALL_REPORT_INTERVAL (2 s), so a peer
// that still believes the master is gone keeps its vote alive by re-sending,
// while a peer whose connection merely hiccuped once stops contributing.
const stallVoteTTL = 10 * time.Second

// stallMasterSilence is how long the LOBBY ITSELF must have heard nothing from
// the master before any quorum of stall votes is acted on.
//
// Without it a vote is taken purely on the reporters' word, and "strictly more
// than half of the non-master members" is ONE vote in a two-member room — so a
// stranger (every room code is public over /rooms) joins a room somebody is
// hosting alone, sends a single `stalled` frame, and is master. The client trusts
// the master for pickup arbitration, crocodile sync, `dead`/`flee` broadcasts and
// as the only accepted `seed` source, so that is the whole room.
//
// The master heartbeats over the relay once a second (mp_manager.HEARTBEAT_INTERVAL),
// which is a socket read here, so a healthy master is never 3 s silent and a
// genuinely throttled tab is silent immediately. Corroboration, not a second
// detector: the clients still decide, the lobby just refuses to act on a claim it
// can see is false.
const stallMasterSilence = 3 * time.Second

// maxListedRooms bounds the work one unauthenticated GET /rooms can provoke under
// the hub mutex — the same lock every signal, join and election serialises on.
// ponytail: which rooms are dropped is map-iteration order, i.e. arbitrary. The
// upgrade path is a cached listing if a lobby ever really holds this many.
const maxListedRooms = 200

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

	// lastSeen is when the read loop last got a frame from this peer, in Unix
	// nanoseconds. Atomic because it is written from the peer's own read
	// goroutine and read under the hub mutex during an election — see
	// stallMasterSilence for why it exists.
	lastSeen atomic.Int64

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

// Touch records that a frame just arrived from this peer.
func (m *Member) Touch() { m.lastSeen.Store(time.Now().UnixNano()) }

// silentFor reports how long the lobby has heard nothing from this peer.
func (m *Member) silentFor(now time.Time) time.Duration {
	return now.Sub(time.Unix(0, m.lastSeen.Load()))
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

	// reports[subject][reporterID] is when that reporter last voted subject
	// stalled. Timestamped rather than a plain set because a vote must EXPIRE:
	// a stall report is evidence about right now, and a monotone set means two
	// peers whose connections hiccuped at completely unrelated moments an hour
	// apart still add up to a quorum against a perfectly healthy master. See
	// stallVoteTTL.
	reports map[string]map[string]time.Time
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

// RoomInfo is one open room as the public listing reports it.
//
// Deliberately NOT peerInfo-shaped: this is browsed *before* joining, by someone
// who is not in the room, so it carries no peer ids and no display names — only
// what a stranger needs in order to pick a room. The heroes are the bodies
// already embodied, so the list reads "two players, one of them Windman".
type RoomInfo struct {
	Code    string   `json:"code"`
	Members int      `json:"members"`
	Heroes  []string `json:"heroes"`
}

// ListRooms returns every open, joinable room, sorted by code so a client's list
// does not reshuffle between refreshes.
//
// EVERY open room is listed: the owner's decision is that rooms are public by
// default and an invite code is the way to reach one *specific* friend, not the
// only way in. There is no per-room "listed" flag and none is wanted.
//
// Two kinds of room are withheld, both for the same reason — a row you cannot
// join is worse than no row:
//
//   - a FULL room, which would only produce a refused join; and
//   - an EMPTY room, i.e. one mid-teardown. `Leave` deletes a room the instant
//     its last member goes, and it does so under this same mutex, so today the
//     empty case is unreachable rather than merely rare. The check is kept
//     because it is the invariant this listing depends on: any future path that
//     builds a room before its first member (or drains one before deleting it)
//     would otherwise start advertising rooms nobody is in.
func (h *Hub) ListRooms() []RoomInfo {
	h.mu.Lock()
	defer h.mu.Unlock()

	out := make([]RoomInfo, 0, min(len(h.rooms), maxListedRooms))
	// Bounded on rooms EXAMINED, not rooms emitted. Breaking on len(out) bounded
	// only the response: full and mid-teardown rooms never increment it, so a hub
	// full of them was scanned end to end under h.mu — the same lock every Signal,
	// Join and election serialises on — for one unauthenticated, unrated GET.
	// Join creates a room for any well-formed unknown code, so the room count is
	// caller-controlled at one room per socket.
	examined := 0
	for code, r := range h.rooms {
		if examined >= maxListedRooms {
			break
		}
		examined++
		n := len(r.members)
		if n == 0 || n >= MaxMembers {
			continue
		}
		heroes := make([]string, 0, len(r.heroes))
		for hero := range r.heroes {
			heroes = append(heroes, hero)
		}
		// Map iteration is random, so both levels are sorted: without this the
		// same unchanged room renders its heroes in a different order on every
		// refresh.
		sort.Strings(heroes)
		out = append(out, RoomInfo{Code: code, Members: n, Heroes: heroes})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Code < out[j].Code })
	return out
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
			reports: make(map[string]map[string]time.Time),
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
	// A member that has not spoken yet is not a silent one: without this its
	// lastSeen is the zero time and the very first vote against it succeeds.
	m.Touch()
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
	// A member the room has already voted out keeps its socket but loses its
	// vote. Otherwise one peer that hiccuped once (or one that is malicious)
	// forms a quorum against every master the room ever elects, churning the
	// title indefinitely — each migration costing a visible croc-sim handover.
	if reporter.stalled {
		return
	}
	// CORROBORATE. The claim is "the master has gone quiet"; the lobby is a peer
	// of the master too and can simply check. See stallMasterSilence.
	master, ok := r.members[subject]
	if !ok {
		return
	}
	set := r.reports[subject]
	if set == nil {
		set = make(map[string]time.Time)
		r.reports[subject] = set
	}
	now := time.Now()
	set[reporter.ID] = now
	// Prune before counting, so only peers that still believe the master is gone
	// right now contribute to the quorum.
	for id, at := range set {
		if now.Sub(at) > stallVoteTTL {
			delete(set, id)
		}
	}

	if master.silentFor(now) < stallMasterSilence {
		return
	}

	// Count only members that can still vote — a stalled member is neither an
	// eligible reporter (above) nor part of the electorate, so counting it in the
	// denominator would mean neither "half the live peers" nor "half the eligible
	// ones".
	others, votes := 0, 0
	for id, m := range r.members {
		if id == subject || m.stalled {
			continue
		}
		others++
		if _, voted := set[id]; voted {
			votes++
		}
	}
	if others < 1 || votes*2 <= others {
		return
	}
	master.stalled = true
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
		r.reports = make(map[string]map[string]time.Time)
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
