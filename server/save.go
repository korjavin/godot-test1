package main

// save.go — one cloud save slot per player. A sibling of best.go in its EXACT
// shape (a map, a 30 s dump file, an LRU cap, a body cap), but a SECOND FILE
// with its own map, because the merge semantics differ: /best is monotone
// (every field max/union, every POST idempotent) and a save is NOT — it goes
// backwards by design. Putting a blob on bestRecord would force merge() to
// grow a non-monotone branch and break the one sentence best.go is built on.
// A sibling microservice would cost an image, a CI job, a router and a volume
// for a ~10 MB JSON file.
//
// SHAPE CHOICE (bead godot-test1-i8yu.4 asks): two copies, not a shared
// helper. The store, load, dump, runDumper and evict bodies below are ~40-line
// copies of best.go's, adapted to saveRecord. A generic store interface would
// have to abstract over a monotone merge AND a last-write-wins put AND a
// found-set union — three call shapes — to save one small file's worth of
// obvious code. The copy is the smaller diff and each file stays readable
// alone.
//
// Trust model, stated because it looks like an omission otherwise: the
// endpoint is unauthenticated, exactly like /best, /ice and /rooms, so anyone
// who knows a player id can read, overwrite or clear that player's save. The
// id is a client-generated 128-bit random token that appears in no listing,
// so guessing one is the bound — the id IS the secret (auth proper is bead
// .7's problem). The stake is one toy save slot. What IS defended is the
// server: bounded id, bounded body, bounded blob, bounded map, no
// enumeration, no listing route.
//
// THE LOBBY STAYS "DOES NOT INSPECT PAYLOADS" FOR THE BLOB'S CONTENT: the
// server checks only that the blob is a JSON string within the cap. It never
// decodes the blob's FIELDS — that format belongs to the client
// (scripts/save_state.gd; SaveState.decode validates on read). A blob that is
// well-formed JSON-string here may still be rejected by the game on load, and
// that is fine: the server is a shelf, not a validator.

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const (
	// maxSaveRecords bounds the map (and therefore the dump file) on an
	// unauthenticated write endpoint. At the cap a new id evicts the
	// least-recently-seen one — see saveStore.put.
	maxSaveRecords = 10000

	// maxSaveBody is the accepted request body, SIZED FROM THE CONSTANTS, not
	// guessed — the same derivation best.go:60-75 does for /best. The client
	// holds MAX_SAVE_BYTES = 2048 (scripts/save_state.gd): the largest blob
	// the game will ever store. On the wire that blob rides INSIDE a JSON
	// string, so every quote and backslash in it costs an extra escape byte,
	// plus the envelope itself ({"blob":"…","saved_at":<10 digits>} ≈ 35
	// bytes). A real v1 blob carries a few dozen quotes, so the worst honest
	// body is ~2048 + ~100 + ~35 ≈ 2.2 KB. 4096 is that worst case with room
	// to spare (~1.8x), still far too small for a hostile client to park
	// anything large behind. Over the cap is a 400, never a truncation.
	maxSaveBody = 4096

	// maxSaveClockSkew bounds saved_at into the future: a device clock a day
	// fast is tolerated, anything beyond it is a hostile or broken client
	// parking an un-overwritable far-future stamp (LWW would then refuse every
	// honest write until that date). The past needs no bound: an old stamp
	// simply loses to the stored one, which is the whole point.
	maxSaveClockSkew = 24 * time.Hour

	// saveDumpInterval is how often a dirty store is written to disk. Same
	// reasoning as best.go: the lobby has no graceful shutdown (see main), so
	// a SIGTERM can lose up to this much — acceptable for a save slot whose
	// client keeps its own browser copy, and the alternative (writing on every
	// POST) puts a file write on an unauthenticated request path.
	saveDumpInterval = 30 * time.Second
)

// saveRecord is one player's cloud slot: an opaque blob plus the client-
// asserted unix time it was written. Seen is bookkeeping for the LRU cap,
// refreshed by read AND write, and never sent to the client.
type saveRecord struct {
	Blob    string `json:"blob"`
	SavedAt int64  `json:"saved_at"`
	Seen    int64  `json:"seen"` // unix seconds; refreshed by read AND write
}

type saveStore struct {
	mu    sync.Mutex
	recs  map[string]saveRecord
	path  string // "" = memory only (tests, and a deployment with no volume)
	dirty bool
}

func newSaveStore(path string) *saveStore {
	s := &saveStore{recs: map[string]saveRecord{}, path: path}
	if path != "" {
		if err := s.load(); err != nil {
			// A missing file is the first-run path, not an error.
			if !errors.Is(err, os.ErrNotExist) {
				log.Printf("lobby: save: could not load %s: %v (starting empty)", path, err)
			}
		}
	}
	return s
}

// get returns the record for id, and stamps it as seen so an active player is
// not the one evicted at the cap. A missing id reads as the zero record —
// "you have no cloud save yet" is not an error.
func (s *saveStore) get(id string) saveRecord {
	s.mu.Lock()
	defer s.mu.Unlock()
	rec, ok := s.recs[id]
	if !ok {
		return saveRecord{}
	}
	rec.Seen = time.Now().Unix()
	s.recs[id] = rec
	s.dirty = true
	return rec
}

// put stores blob under id LAST-WRITE-WINS on savedAt: a write whose stamp is
// OLDER than the stored one is a no-op that returns the stored record, so an
// offline device that comes back with a stale slot learns the newer one
// instead of clobbering it. An EQUAL stamp overwrites — that is the same
// device retrying a write whose reply it never saw. Either way the returned
// record is what the caller should trust, exactly like /best answers the
// merged record.
func (s *saveStore) put(id, blob string, savedAt int64) saveRecord {
	s.mu.Lock()
	defer s.mu.Unlock()
	if rec, ok := s.recs[id]; ok && savedAt < rec.SavedAt {
		return rec
	}
	if _, existed := s.recs[id]; !existed && len(s.recs) >= maxSaveRecords {
		s.evictOldestLocked()
	}
	rec := saveRecord{Blob: blob, SavedAt: savedAt, Seen: time.Now().Unix()}
	s.recs[id] = rec
	s.dirty = true
	return rec
}

// clear drops the slot outright. A clear is the player's explicit intent
// (the in-game "erase save" action), so it is unconditional: no stamp
// comparison, no tombstone. Clearing a missing id is a silent success.
func (s *saveStore) clear(id string) saveRecord {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.recs, id)
	s.dirty = true
	return saveRecord{}
}

// evictOldestLocked drops the least-recently-seen record. Caller holds the mutex.
func (s *saveStore) evictOldestLocked() {
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
func (s *saveStore) load() error {
	b, err := os.ReadFile(s.path)
	if err != nil {
		return err
	}
	var recs map[string]saveRecord
	if err := json.Unmarshal(b, &recs); err != nil {
		return err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	for id, rec := range recs {
		// The file is ours, but it is still a file on disk: re-apply the
		// request path's bounds, so a hand-edited or truncated dump cannot
		// smuggle past them. One deliberate exception: the future bound on
		// saved_at is NOT re-applied — time passes, so a stamp that was
		// within a day when written would be dropped by a load a week later,
		// losing a save. saved_at >= 0 is the load-time rule.
		if !playerIDRe.MatchString(id) {
			continue
		}
		if len(rec.Blob) > maxSaveBody {
			continue
		}
		if rec.SavedAt < 0 {
			continue
		}
		s.recs[id] = rec
		if len(s.recs) >= maxSaveRecords {
			break
		}
	}
	return nil
}

// dump writes the map to disk, atomically (temp file + rename) so a crash
// mid-write cannot leave a half-written file that the next boot refuses to parse.
// It is a no-op when nothing changed, and when no path was configured.
func (s *saveStore) dump() error {
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
	err = os.MkdirAll(filepath.Dir(path), 0o755)
	if err == nil {
		err = os.WriteFile(tmp, b, 0o644)
	}
	if err == nil {
		err = os.Rename(tmp, path)
	}
	if err != nil {
		// `dirty` was cleared before the I/O so a put landing mid-write is not
		// swallowed. Put it back on failure, or the ticker's next pass sees a
		// clean store and does nothing — one transient ENOSPC or a volume not yet
		// mounted would then quietly cost every save until somebody happens to
		// write again.
		s.mu.Lock()
		s.dirty = true
		s.mu.Unlock()
	}
	return err
}

// runDumper flushes the store on a ticker for the process's lifetime.
func (s *saveStore) runDumper() {
	if s.path == "" {
		return
	}
	for range time.Tick(saveDumpInterval) {
		if err := s.dump(); err != nil {
			log.Printf("lobby: save: dump failed: %v", err)
		}
	}
}

// validSaveAt is the whole stamp rule: a finite int in [0, now+1 day].
// Finiteness and integer-ness arrive free — the body decodes saved_at into an
// int64, so 1.5, "tomorrow", 1e999 and null all fail the decode before this
// ever runs — and this checks the range.
func validSaveAt(ts, now int64) bool {
	return ts >= 0 && ts <= now+int64(maxSaveClockSkew/time.Second)
}

// saveHandler serves GET/POST/DELETE /save?id=<player id>.
//
//	GET    → {"blob":s,"saved_at":N}   stored (zeroes if unknown)
//	POST   → {"blob":s,"saved_at":N}   AFTER the LWW put (or the stored record
//	         on a stale write); a POST with an empty blob clears instead
//	DELETE → {"blob":"","saved_at":0}  the slot cleared
//
// Same CORS rule as /best, /ice and /rooms — the game is served from a
// different origin than the lobby, so without the header the browser discards
// the response. The POST carries a JSON content type, which is not a "simple
// request": the browser sends an OPTIONS preflight first and drops the real
// request if it is not answered. That is what the OPTIONS branch is for.
func (s *saveStore) handler(w http.ResponseWriter, r *http.Request) {
	origin := corsOrigin(r.Header.Get("Origin"))
	if origin != "" {
		w.Header().Set("Access-Control-Allow-Origin", origin)
		w.Header().Set("Vary", "Origin")
	}
	if r.Method == http.MethodOptions {
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
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

	var rec saveRecord
	switch r.Method {
	case http.MethodGet:
		rec = s.get(id)
	case http.MethodDelete:
		rec = s.clear(id)
	case http.MethodPost:
		var body struct {
			Blob    *string `json:"blob"`
			SavedAt *int64  `json:"saved_at"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxSaveBody)).Decode(&body); err != nil {
			http.Error(w, "bad body", http.StatusBadRequest)
			return
		}
		// Both fields are required and typed: a missing, null or non-string
		// blob and a missing, fractional or out-of-range stamp are all a 400.
		// An explicitly EMPTY blob is the clear verb riding POST.
		if body.Blob == nil || body.SavedAt == nil {
			http.Error(w, "bad body", http.StatusBadRequest)
			return
		}
		if len(*body.Blob) > maxSaveBody {
			http.Error(w, "bad body", http.StatusBadRequest)
			return
		}
		if !validSaveAt(*body.SavedAt, time.Now().Unix()) {
			http.Error(w, "bad saved_at", http.StatusBadRequest)
			return
		}
		if *body.Blob == "" {
			rec = s.clear(id)
		} else {
			rec = s.put(id, *body.Blob, *body.SavedAt)
		}
	default:
		w.Header().Set("Allow", "GET, POST, DELETE, OPTIONS")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	// `seen` is bookkeeping, not the client's business — it is deliberately not
	// in the response shape.
	_, _ = w.Write(mustJSON(map[string]any{
		"blob":     rec.Blob,
		"saved_at": rec.SavedAt,
	}))
}
