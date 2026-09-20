// save_test.go — the /save acceptance criteria. The store's whole job is
// "one opaque slot per player, last write wins, memory stays bounded, and the
// browser is allowed to talk to it", so those are the four things pinned here.
//
// The v1 blob below is bead .1's literal verbatim
// (scripts/save_selfcheck.gd LITERAL): both sides pin the same string, so a
// drift in the format breaks here as well as there.

package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// saveV1Fixture is the client's canonical v1 save blob, byte-identical to
// scripts/save_selfcheck.gd's LITERAL. Its saved_at (2026-09-19) is in the
// past, so it stays inside the [0, now+1 day] window forever.
const saveV1Fixture = `{"captives":["primm","teibi"],"coins":1250,"distance":3340,"explored":7,"hero":2,"in_hq":true,"landing":"lift_stop_s3","lift":["lift_stop_s3"],"pos":[1234.5,0.0,-9876.25],"saved_at":1758326400,"seed":20260904,"v":1,"waypoints":3}`

// saveFixtureAt is the same shape with a caller-chosen stamp, for LWW tests.
func saveFixtureAt(savedAt int64) string {
	return fmt.Sprintf(`{"blob":%q,"saved_at":%d}`, saveV1Fixture, savedAt)
}

func decodeSave(t *testing.T, rec *httptest.ResponseRecorder) (string, int64) {
	t.Helper()
	var body struct {
		Blob    string `json:"blob"`
		SavedAt int64  `json:"saved_at"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode %q: %v", rec.Body.String(), err)
	}
	return body.Blob, body.SavedAt
}

func postSave(s *saveStore, id, body string) *httptest.ResponseRecorder {
	r := httptest.NewRequest(http.MethodPost, "/save?id="+id, strings.NewReader(body))
	r.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	s.handler(w, r)
	return w
}

func getSave(s *saveStore, id string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	s.handler(w, httptest.NewRequest(http.MethodGet, "/save?id="+id, nil))
	return w
}

// TestSaveRoundTrip drives the route the client actually uses: POST the pinned
// v1 blob, GET it back byte-identical with its stamp.
func TestSaveRoundTrip(t *testing.T) {
	s := newSaveStore("")
	const id = "0123456789abcdef0123456789abcdef"

	// A player who has never saved reads the zero record, not a 404: "no
	// cloud save yet" is a normal answer and the client renders it as such.
	rec := getSave(s, id)
	if rec.Code != http.StatusOK {
		t.Fatalf("GET status %d", rec.Code)
	}
	if blob, at := decodeSave(t, rec); blob != "" || at != 0 {
		t.Fatalf("fresh id read %q/%d, wanted zeroes", blob, at)
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-store" {
		t.Errorf("Cache-Control = %q", got)
	}

	rec = postSave(s, id, saveFixtureAt(1758326400))
	if rec.Code != http.StatusOK {
		t.Fatalf("POST status %d (%s)", rec.Code, rec.Body.String())
	}
	if blob, at := decodeSave(t, rec); blob != saveV1Fixture || at != 1758326400 {
		t.Fatalf("POST answered %d bytes/%d", len(blob), at)
	}

	rec = getSave(s, id)
	if blob, at := decodeSave(t, rec); blob != saveV1Fixture || at != 1758326400 {
		t.Fatalf("GET after POST read %d bytes/%d", len(blob), at)
	}
}

// TestSaveLastWriteWins is the reason the endpoint is NOT monotone: an offline
// device that comes back with a stale slot must learn the newer one, not
// clobber it — and the reply carries the stored record so the caller trusts
// it blindly, exactly like /best answers the merged record.
func TestSaveLastWriteWins(t *testing.T) {
	s := newSaveStore("")
	const id = "fedcba9876543210fedcba9876543210"
	now := time.Now().Unix()

	if rec := postSave(s, id, saveFixtureAt(now)); rec.Code != http.StatusOK {
		t.Fatalf("first POST status %d", rec.Code)
	}
	// An older stamp is a 200 no-op, and the reply is the STORED (newer) one.
	rec := postSave(s, id, fmt.Sprintf(`{"blob":"stale-blob","saved_at":%d}`, now-3600))
	if rec.Code != http.StatusOK {
		t.Fatalf("stale POST status %d", rec.Code)
	}
	if blob, at := decodeSave(t, rec); blob != saveV1Fixture || at != now {
		t.Fatalf("stale POST answered %q/%d, wanted the stored record", blob, at)
	}
	if blob, _ := decodeSave(t, getSave(s, id)); blob != saveV1Fixture {
		t.Fatalf("a stale POST overwrote the slot")
	}
	// An equal stamp overwrites: the same device retrying a write whose reply
	// it never saw.
	rec = postSave(s, id, fmt.Sprintf(`{"blob":"retry-blob","saved_at":%d}`, now))
	if blob, at := decodeSave(t, rec); blob != "retry-blob" || at != now {
		t.Fatalf("equal-stamp POST answered %q/%d", blob, at)
	}
	// And a newer stamp wins normally.
	rec = postSave(s, id, fmt.Sprintf(`{"blob":"newer-blob","saved_at":%d}`, now+10))
	if blob, at := decodeSave(t, rec); blob != "newer-blob" || at != now+10 {
		t.Fatalf("newer POST answered %q/%d", blob, at)
	}
}

// TestSaveClear — DELETE drops the slot, and so does a POST with an explicitly
// empty blob (bead .2's clear_save_slot rides one of these in .5).
func TestSaveClear(t *testing.T) {
	s := newSaveStore("")
	const id = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	now := time.Now().Unix()

	if rec := postSave(s, id, saveFixtureAt(now)); rec.Code != http.StatusOK {
		t.Fatalf("seed POST status %d", rec.Code)
	}
	w := httptest.NewRecorder()
	s.handler(w, httptest.NewRequest(http.MethodDelete, "/save?id="+id, nil))
	if w.Code != http.StatusOK {
		t.Fatalf("DELETE status %d", w.Code)
	}
	if blob, at := decodeSave(t, getSave(s, id)); blob != "" || at != 0 {
		t.Fatalf("after DELETE the slot read %q/%d", blob, at)
	}

	// The POST-with-empty-blob half.
	if rec := postSave(s, id, saveFixtureAt(now)); rec.Code != http.StatusOK {
		t.Fatalf("re-seed POST status %d", rec.Code)
	}
	rec := postSave(s, id, fmt.Sprintf(`{"blob":"","saved_at":%d}`, now))
	if rec.Code != http.StatusOK {
		t.Fatalf("clear POST status %d", rec.Code)
	}
	if blob, at := decodeSave(t, getSave(s, id)); blob != "" || at != 0 {
		t.Fatalf("after clear POST the slot read %q/%d", blob, at)
	}

	// Clearing a missing id is a silent success, not a 404.
	w = httptest.NewRecorder()
	s.handler(w, httptest.NewRequest(http.MethodDelete, "/save?id="+id, nil))
	if w.Code != http.StatusOK {
		t.Fatalf("second DELETE status %d", w.Code)
	}
}

// TestSaveEvictsLeastRecentlySeen is the memory bound on an unauthenticated
// write endpoint: at the cap a new id costs the oldest one, and an id that
// was READ recently counts as active.
func TestSaveEvictsLeastRecentlySeen(t *testing.T) {
	s := newSaveStore("")
	// Fill to the cap with a hand-stamped `Seen` so the ordering is
	// deterministic rather than depending on wall-clock ties.
	for i := 0; i < maxSaveRecords; i++ {
		id := padID(i)
		s.recs[id] = saveRecord{Blob: "b", SavedAt: 1, Seen: int64(i)}
	}
	oldest := padID(0)
	stale := padID(1)

	// Reading the oldest promotes it past the runner-up.
	s.get(oldest)
	s.put(padID(maxSaveRecords), "new", 2)

	if len(s.recs) != maxSaveRecords {
		t.Fatalf("map grew to %d, cap is %d", len(s.recs), maxSaveRecords)
	}
	if _, ok := s.recs[stale]; ok {
		t.Errorf("least-recently-seen record survived eviction")
	}
	if _, ok := s.recs[oldest]; !ok {
		t.Errorf("a record read moments ago was evicted")
	}
	if _, ok := s.recs[padID(maxSaveRecords)]; !ok {
		t.Errorf("the new record was not stored")
	}
}

// TestSaveBodyCap — over the cap is a 400, never a truncation. Both layers:
// an oversize BLOB, and an oversize BODY around a valid blob (the positive
// half: a client-max 2048-byte blob is a 200).
func TestSaveBodyCap(t *testing.T) {
	s := newSaveStore("")
	const id = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
	now := time.Now().Unix()

	// The positive half: the largest blob the client may ever send (its
	// MAX_SAVE_BYTES = 2048) is accepted.
	big, err := json.Marshal(map[string]any{"blob": strings.Repeat("a", 2048), "saved_at": now})
	if err != nil {
		t.Fatalf("fixture: %v", err)
	}
	if rec := postSave(s, id, string(big)); rec.Code != http.StatusOK {
		t.Fatalf("client-max blob POST status %d (%s)", rec.Code, rec.Body.String())
	}

	// A blob one past the cap is a 400.
	huge, err := json.Marshal(map[string]any{"blob": strings.Repeat("a", maxSaveBody+1), "saved_at": now})
	if err != nil {
		t.Fatalf("fixture: %v", err)
	}
	if rec := postSave(s, id, string(huge)); rec.Code != http.StatusBadRequest {
		t.Errorf("cap+1 blob POST status %d, wanted 400", rec.Code)
	}

	// An oversize body AROUND a valid blob is a 400 too: the size guard runs
	// before the decode, so padding cannot smuggle size past it.
	padded, err := json.Marshal(map[string]any{
		"blob": saveV1Fixture, "saved_at": now, "pad": strings.Repeat("p", maxSaveBody),
	})
	if err != nil {
		t.Fatalf("fixture: %v", err)
	}
	if rec := postSave(s, id, string(padded)); rec.Code != http.StatusBadRequest {
		t.Errorf("padded body POST status %d, wanted 400", rec.Code)
	}
}

// TestSaveRejectsBadID — every way in that is not a well-formed id.
func TestSaveRejectsBadID(t *testing.T) {
	s := newSaveStore("")
	// Escaped the way a browser would send them — the guard runs on the
	// DECODED value, which is what a path-traversal attempt arrives as.
	badIDs := []string{"", "short", "has spaces here", strings.Repeat("a", 65), "semi;colon", "../../etc/passwd"}
	for _, bad := range badIDs {
		rec := httptest.NewRecorder()
		s.handler(rec, httptest.NewRequest(http.MethodGet, "/save?id="+url.QueryEscape(bad), nil))
		if rec.Code != http.StatusBadRequest {
			t.Errorf("id %q: status %d, wanted 400", bad, rec.Code)
		}
	}
	rec := postSave(s, "../../etc/passwd", saveFixtureAt(time.Now().Unix()))
	if rec.Code != http.StatusBadRequest {
		t.Errorf("POST with bad id: status %d, wanted 400", rec.Code)
	}
}

// TestSaveRejectsBadSavedAt — the stamp is a finite int in [0, now+1 day].
func TestSaveRejectsBadSavedAt(t *testing.T) {
	s := newSaveStore("")
	const id = "cccccccccccccccccccccccccccccccc"
	now := time.Now().Unix()

	bodies := []string{
		fmt.Sprintf(`{"blob":"x","saved_at":%d}`, -1),          // negative
		fmt.Sprintf(`{"blob":"x","saved_at":%d}`, now+2*86400), // beyond the +1 day skew
		`{"blob":"x","saved_at":1.5}`,                          // fractional
		`{"blob":"x","saved_at":"tomorrow"}`,                   // wrong type
		`{"blob":"x","saved_at":null}`,                         // null
		`{"blob":"x"}`,                                         // missing
		`{"blob":"x","saved_at":1e999}`,                        // not finite
	}
	for _, body := range bodies {
		if rec := postSave(s, id, body); rec.Code != http.StatusBadRequest {
			t.Errorf("body %.40q: status %d, wanted 400", body, rec.Code)
		}
	}
	// The positive half: the edges of the window are accepted.
	for _, at := range []int64{0, now, now + 86400} {
		if rec := postSave(s, id, saveFixtureAt(at)); rec.Code != http.StatusOK {
			t.Errorf("saved_at=%d: status %d, wanted 200", at, rec.Code)
		}
	}
}

// TestSaveRejectsNonStringBlob — the server never decodes the blob's fields,
// but the blob itself must be a JSON string: a number, object, array, null or
// missing blob is a 400, not a stored surprise.
func TestSaveRejectsNonStringBlob(t *testing.T) {
	s := newSaveStore("")
	const id = "dddddddddddddddddddddddddddddddd"
	now := time.Now().Unix()

	bodies := []string{
		fmt.Sprintf(`{"blob":123,"saved_at":%d}`, now),
		fmt.Sprintf(`{"blob":{},"saved_at":%d}`, now),
		fmt.Sprintf(`{"blob":[],"saved_at":%d}`, now),
		fmt.Sprintf(`{"blob":null,"saved_at":%d}`, now),
		fmt.Sprintf(`{"saved_at":%d}`, now),
		`not json`,
		``,
	}
	for _, body := range bodies {
		if rec := postSave(s, id, body); rec.Code != http.StatusBadRequest {
			t.Errorf("body %.40q: status %d, wanted 400", body, rec.Code)
		}
	}
}

// TestSaveFileSurvivesRestart is the whole point of the file: a redeploy must
// not reset everybody's cloud slot.
func TestSaveFileSurvivesRestart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "nested", "save.json")

	s := newSaveStore(path)
	s.put("player-dddd", saveV1Fixture, 1758326400)
	if err := s.dump(); err != nil {
		t.Fatalf("dump: %v", err)
	}
	// A clean store is a no-op dump, not a rewrite.
	if err := s.dump(); err != nil {
		t.Fatalf("second dump: %v", err)
	}

	reborn := newSaveStore(path)
	if rec := reborn.get("player-dddd"); rec.Blob != saveV1Fixture || rec.SavedAt != 1758326400 {
		t.Fatalf("after restart the slot read %d bytes/%d", len(rec.Blob), rec.SavedAt)
	}
	// A file naming an id the request path would refuse must not smuggle it in.
	reborn.recs["not a valid id"] = saveRecord{Blob: "x", SavedAt: 1}
	reborn.recs["player-junk"] = saveRecord{Blob: strings.Repeat("z", maxSaveBody+1), SavedAt: 1}
	reborn.recs["player-neg"] = saveRecord{Blob: "x", SavedAt: -5}
	if err := reborn.dump(); err != nil {
		t.Fatalf("dump with junk: %v", err)
	}
	third := newSaveStore(path)
	if _, ok := third.recs["not a valid id"]; ok {
		t.Errorf("a malformed id survived a load")
	}
	if _, ok := third.recs["player-junk"]; ok {
		t.Errorf("an oversize blob survived a load")
	}
	if _, ok := third.recs["player-neg"]; ok {
		t.Errorf("a negative stamp survived a load")
	}
}

// TestSaveFailedDumpStaysDirty — `dirty` is cleared BEFORE the write (so a put
// landing mid-write is not swallowed), which means a failed write has to put
// it back. Without that the ticker's next pass sees a clean store and does
// nothing, and one transient failure silently costs every save until somebody
// happens to write again.
func TestSaveFailedDumpStaysDirty(t *testing.T) {
	// A path whose parent is a FILE, so MkdirAll fails every time.
	blocker := filepath.Join(t.TempDir(), "blocker")
	if err := os.WriteFile(blocker, []byte("x"), 0o644); err != nil {
		t.Fatalf("setup: %v", err)
	}
	s := newSaveStore(filepath.Join(blocker, "sub", "save.json"))
	s.put("player-eeee", saveV1Fixture, 1758326400)

	if err := s.dump(); err == nil {
		t.Fatalf("dump into %s unexpectedly succeeded", s.path)
	}
	s.mu.Lock()
	dirty := s.dirty
	s.mu.Unlock()
	if !dirty {
		t.Fatalf("a failed dump left the store clean — every later tick is a no-op")
	}
}

// TestSavePreflight — the POST carries `Content-Type: application/json`, which
// is NOT a CORS "simple request", so the browser sends an OPTIONS first and
// drops the real request unless it is answered.
func TestSavePreflight(t *testing.T) {
	restore := allowedOrigins
	t.Cleanup(func() { allowedOrigins = restore })
	allowedOrigins = []string{"korjavin.github.io"}

	s := newSaveStore("")
	req := httptest.NewRequest(http.MethodOptions, "/save?id=whatever", nil)
	req.Header.Set("Origin", "https://korjavin.github.io")
	req.Header.Set("Access-Control-Request-Method", "POST")
	req.Header.Set("Access-Control-Request-Headers", "content-type")
	rec := httptest.NewRecorder()
	s.handler(rec, req)

	if rec.Code != http.StatusNoContent {
		t.Fatalf("preflight status %d", rec.Code)
	}
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "https://korjavin.github.io" {
		t.Errorf("allow-origin = %q", got)
	}
	if got := rec.Header().Get("Access-Control-Allow-Methods"); !strings.Contains(got, "POST") {
		t.Errorf("allow-methods = %q", got)
	}
	if got := rec.Header().Get("Access-Control-Allow-Methods"); !strings.Contains(got, "DELETE") {
		t.Errorf("allow-methods = %q, wanted DELETE too", got)
	}

	// A foreign origin gets the preflight answered without the allow header.
	req = httptest.NewRequest(http.MethodOptions, "/save?id=whatever", nil)
	req.Header.Set("Origin", "https://evil.example")
	rec = httptest.NewRecorder()
	s.handler(rec, req)
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "" {
		t.Errorf("foreign origin got allow-origin %q", got)
	}
}

// TestSaveIsNotOnHealthz — compile-level guard for the rule in main.go:89-119.
// healthzHandler takes the hub and NOTHING else, so this call stops compiling
// the moment somebody threads a store into it — which drags the author through
// server/health_test.go and the comment. The body then proves the behaviour:
// with the save dump failing every time, /healthz still answers 200 ok:true.
func TestSaveIsNotOnHealthz(t *testing.T) {
	hub := NewHub()
	blocker := filepath.Join(t.TempDir(), "blocker")
	if err := os.WriteFile(blocker, []byte("x"), 0o644); err != nil {
		t.Fatalf("setup: %v", err)
	}
	store := newSaveStore(filepath.Join(blocker, "sub", "save.json"))
	store.put("player-ffff", saveV1Fixture, 1758326400)
	for i := 0; i < 2; i++ {
		if err := store.dump(); err == nil {
			t.Fatalf("dump %d unexpectedly succeeded — the premise is gone", i)
		}
	}

	rec := httptest.NewRecorder()
	healthzHandler(hub)(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("/healthz answered %d while the save dump was failing", rec.Code)
	}
	var body struct {
		OK bool `json:"ok"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil || !body.OK {
		t.Fatalf("/healthz body %q", rec.Body.String())
	}
}
