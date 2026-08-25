package main

// best.go — personal best-run records. THE ONLY PERSISTENT STATE THIS SERVICE
// HAS, and a deliberate exception to the "no persistence on the lobby" rule the
// rest of the code states (owner order, 2026-08-25).
//
// Why it is here at all: the game kept its records in `user://best_run.cfg`, an
// IndexedDB mount on the web export, and the owner saw every single run flash
// "NEW BEST!" — i.e. the records were not coming back. Driving the deployed build
// headless showed that path working end to end in both Chromium and WebKit, so
// the failure is not the code: it is SITE STORAGE not surviving in a particular
// browser (Safari/iOS purges IndexedDB for sites without recent interaction, a
// private window keeps nothing, and two origins have two stores). No amount of
// client-side cleverness fixes that. A record kept on the server does, and it
// follows a player between devices as well.
//
// PERSONAL BESTS ONLY. There is no leaderboard, no listing route, and nothing
// here is ever enumerated to a client — a caller can read and raise exactly the
// one id it names.
//
// Trust model, stated because it looks like an omission otherwise: the endpoint
// is unauthenticated, exactly like /ice and /rooms, so anyone who knows a player
// id can read and raise that player's record. The id is a client-generated
// 128-bit random token that appears in no listing, so guessing one is the bound.
// The stake is a distance number in a toy game; a login is not worth building
// for it. What IS defended is the server: bounded id, bounded body, bounded
// value, bounded map, bounded file.

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"
)

const (
	// maxBestRecords bounds the map (and therefore the dump file) on an
	// unauthenticated write endpoint. At the cap a new id evicts the
	// least-recently-seen one — see bestStore.merge.
	//
	// ponytail: an O(n) scan to find that victim, paid only on an insert that is
	// already at the cap. 10k entries is microseconds; if this ever becomes a
	// real player base, the upgrade is a heap or an LRU list, not a database.
	maxBestRecords = 10000

	// maxBestValue clamps a submitted record. It is not anti-cheat (nothing here
	// can distinguish a good run from a fabricated one) — it keeps a hostile or
	// broken client from parking absurd numbers in the JSON file.
	maxBestValue = 1 << 30

	// maxBestBody is the accepted request body. A record is two small integers.
	maxBestBody = 256

	// bestDumpInterval is how often a dirty store is written to disk. The lobby
	// has no graceful shutdown (see main), so a SIGTERM can lose up to this much
	// — acceptable for a best-score, and the alternative (writing on every POST)
	// puts a file write on an unauthenticated request path.
	bestDumpInterval = 30 * time.Second
)

// playerIDRe is the whole id validation: URL-safe, bounded, non-empty. The
// client generates 32 hex characters; the range is wider so an older or newer
// client's format still works.
var playerIDRe = regexp.MustCompile(`^[A-Za-z0-9_-]{8,64}$`)

// bestRecord is one player's records. Distance and coins are INDEPENDENT maxima,
// matching the client: a long-but-poor run can set one without the other.
type bestRecord struct {
	Distance int   `json:"distance"`
	Coins    int   `json:"coins"`
	Seen     int64 `json:"seen"` // unix seconds; refreshed by read AND write
}

type bestStore struct {
	mu    sync.Mutex
	recs  map[string]bestRecord
	path  string // "" = memory only (tests, and a deployment with no volume)
	dirty bool
}

func newBestStore(path string) *bestStore {
	s := &bestStore{recs: map[string]bestRecord{}, path: path}
	if path != "" {
		if err := s.load(); err != nil {
			// A missing file is the first-run path, not an error.
			if !errors.Is(err, os.ErrNotExist) {
				log.Printf("lobby: best: could not load %s: %v (starting empty)", path, err)
			}
		}
	}
	return s
}

// get returns the record for id, and stamps it as seen so an active player is
// not the one evicted at the cap. A missing id reads as the zero record — "you
// have no best yet" is not an error.
func (s *bestStore) get(id string) bestRecord {
	s.mu.Lock()
	defer s.mu.Unlock()
	rec, ok := s.recs[id]
	if !ok {
		return bestRecord{}
	}
	rec.Seen = time.Now().Unix()
	s.recs[id] = rec
	s.dirty = true
	return rec
}

// merge raises the stored record toward (distance, coins) and returns the result.
// Both fields move independently and only ever upward, so a client that posts a
// stale value cannot lower anything — which is what makes the POST idempotent
// and safe to retry.
func (s *bestStore) merge(id string, distance, coins int) bestRecord {
	s.mu.Lock()
	defer s.mu.Unlock()
	rec, existed := s.recs[id]
	if !existed && len(s.recs) >= maxBestRecords {
		s.evictOldestLocked()
	}
	if distance > rec.Distance {
		rec.Distance = distance
	}
	if coins > rec.Coins {
		rec.Coins = coins
	}
	rec.Seen = time.Now().Unix()
	s.recs[id] = rec
	s.dirty = true
	return rec
}

// evictOldestLocked drops the least-recently-seen record. Caller holds the mutex.
func (s *bestStore) evictOldestLocked() {
	var victim string
	var oldest int64
	for id, rec := range s.recs {
		if victim == "" || rec.Seen < oldest {
			victim, oldest = id, rec.Seen
		}
	}
	if victim != "" {
		delete(s.recs, victim)
	}
}

// load reads the dump file over the (empty) map.
func (s *bestStore) load() error {
	b, err := os.ReadFile(s.path)
	if err != nil {
		return err
	}
	var recs map[string]bestRecord
	if err := json.Unmarshal(b, &recs); err != nil {
		return err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	for id, rec := range recs {
		// The file is ours, but it is still a file on disk: re-apply the same
		// bounds the request path applies, so a hand-edited or truncated dump
		// cannot smuggle past them.
		if !playerIDRe.MatchString(id) {
			continue
		}
		rec.Distance = clampBestValue(rec.Distance)
		rec.Coins = clampBestValue(rec.Coins)
		s.recs[id] = rec
		if len(s.recs) >= maxBestRecords {
			break
		}
	}
	return nil
}

// dump writes the map to disk, atomically (temp file + rename) so a crash
// mid-write cannot leave a half-written file that the next boot refuses to parse.
// It is a no-op when nothing changed, and when no path was configured.
func (s *bestStore) dump() error {
	s.mu.Lock()
	if s.path == "" || !s.dirty {
		s.mu.Unlock()
		return nil
	}
	b, err := json.Marshal(s.recs)
	s.dirty = false
	path := s.path
	s.mu.Unlock()
	if err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(tmp, b, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// runDumper flushes the store on a ticker for the process's lifetime.
func (s *bestStore) runDumper() {
	if s.path == "" {
		return
	}
	for range time.Tick(bestDumpInterval) {
		if err := s.dump(); err != nil {
			log.Printf("lobby: best: dump failed: %v", err)
		}
	}
}

func clampBestValue(v int) int {
	if v < 0 {
		return 0
	}
	if v > maxBestValue {
		return maxBestValue
	}
	return v
}

// bestHandler serves GET/POST /best?id=<player id>.
//
//	GET  → {"distance":N,"coins":N}          the stored record (zeroes if unknown)
//	POST → {"distance":N,"coins":N}          the record AFTER merging the body
//
// Same CORS rule as /ice and /rooms — the game is served from a different origin
// than the lobby, so without the header the browser discards the response. Unlike
// those two this route is also POSTed to with a JSON content type, which is not a
// "simple request": the browser sends an OPTIONS preflight first and drops the
// real request if it is not answered. That is what the OPTIONS branch is for.
func (s *bestStore) handler(w http.ResponseWriter, r *http.Request) {
	origin := corsOrigin(r.Header.Get("Origin"))
	if origin != "" {
		w.Header().Set("Access-Control-Allow-Origin", origin)
		w.Header().Set("Vary", "Origin")
	}
	if r.Method == http.MethodOptions {
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		w.Header().Set("Access-Control-Max-Age", "86400")
		w.WriteHeader(http.StatusNoContent)
		return
	}

	id := strings.TrimSpace(r.URL.Query().Get("id"))
	if !playerIDRe.MatchString(id) {
		http.Error(w, "bad player id", http.StatusBadRequest)
		return
	}

	var rec bestRecord
	switch r.Method {
	case http.MethodGet:
		rec = s.get(id)
	case http.MethodPost:
		var body struct {
			Distance int `json:"distance"`
			Coins    int `json:"coins"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxBestBody)).Decode(&body); err != nil {
			http.Error(w, "bad body", http.StatusBadRequest)
			return
		}
		rec = s.merge(id, clampBestValue(body.Distance), clampBestValue(body.Coins))
	default:
		w.Header().Set("Allow", "GET, POST, OPTIONS")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	// `seen` is bookkeeping, not the client's business — it is deliberately not
	// in the response shape.
	_, _ = w.Write(mustJSON(map[string]any{"distance": rec.Distance, "coins": rec.Coins}))
}
