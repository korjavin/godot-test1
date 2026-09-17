package main

// best_test.go — the /best acceptance criteria. The store's whole job is
// "records only ever go up, memory stays bounded, and the browser is allowed to
// talk to it", so those are the three things pinned here.

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

func decodeBest(t *testing.T, rec *httptest.ResponseRecorder) (int, int) {
	t.Helper()
	var body struct {
		Distance int `json:"distance"`
		Coins    int `json:"coins"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode %q: %v", rec.Body.String(), err)
	}
	return body.Distance, body.Coins
}

// TestBestRecordsOnlyGoUp is the reason the client can POST a stale value and
// retry a failed one without thinking: both fields are independent maxima, so no
// request can ever lower a record.
func TestBestRecordsOnlyGoUp(t *testing.T) {
	s := newBestStore("")

	if rec := s.get("player-unknown"); rec.Distance != 0 || rec.Coins != 0 {
		t.Fatalf("unknown id read as %+v, wanted zeroes", rec)
	}

	if rec := s.merge("player-aaaa", 500, 12, 0, 0, nil); rec.Distance != 500 || rec.Coins != 12 {
		t.Fatalf("first merge = %+v", rec)
	}
	// A shorter but richer run raises coins ONLY — the two records are independent.
	if rec := s.merge("player-aaaa", 100, 40, 0, 0, nil); rec.Distance != 500 || rec.Coins != 40 {
		t.Fatalf("independent maxima broken: %+v", rec)
	}
	// A stale replay changes nothing.
	if rec := s.merge("player-aaaa", 100, 40, 0, 0, nil); rec.Distance != 500 || rec.Coins != 40 {
		t.Fatalf("replay moved the record: %+v", rec)
	}
	// Another player is a separate record.
	if rec := s.merge("player-bbbb", 7, 0, 0, 0, nil); rec.Distance != 7 {
		t.Fatalf("ids leaked into each other: %+v", rec)
	}
	if rec := s.get("player-aaaa"); rec.Distance != 500 || rec.Coins != 40 {
		t.Fatalf("read back %+v", rec)
	}
}

// TestBestProgressionOnlyGoesUp pins the meta-progression half of the record.
// It is a separate test because the failure it guards is different in kind: a
// lifetime coin total that can go DOWN takes a player's LEVEL down with it, and
// the client posts its whole record on every game over, so one stale POST from a
// second device (or a retried one) would do it.
func TestBestProgressionOnlyGoesUp(t *testing.T) {
	s := newBestStore("")

	if rec := s.merge("player-prog", 0, 0, 500, 3, nil); rec.Lifetime != 500 || rec.Spent != 3 {
		t.Fatalf("first progression merge = %+v", rec)
	}
	// A stale device posts an older, smaller lifetime — it must not be believed.
	if rec := s.merge("player-prog", 0, 0, 120, 1, nil); rec.Lifetime != 500 || rec.Spent != 3 {
		t.Fatalf("a stale progression POST lowered the record: %+v", rec)
	}
	// Lifetime and spent move independently, exactly like distance and coins.
	if rec := s.merge("player-prog", 0, 0, 900, 3, nil); rec.Lifetime != 900 || rec.Spent != 3 {
		t.Fatalf("lifetime did not rise alone: %+v", rec)
	}
	if rec := s.merge("player-prog", 0, 0, 900, 5, nil); rec.Lifetime != 900 || rec.Spent != 5 {
		t.Fatalf("spent did not rise alone: %+v", rec)
	}
	// The best-run half is untouched by progression traffic, and vice versa —
	// this is the "an older client posts no lifetime/spent" case, which decodes
	// as 0 and must raise nothing.
	if rec := s.merge("player-prog", 42, 7, 0, 0, nil); rec.Lifetime != 900 || rec.Spent != 5 ||
		rec.Distance != 42 || rec.Coins != 7 {
		t.Fatalf("an old-client POST clobbered progression: %+v", rec)
	}
	if rec := s.get("player-prog"); rec.Lifetime != 900 || rec.Spent != 5 {
		t.Fatalf("read back %+v", rec)
	}
}

// TestBestEvictsLeastRecentlySeen is the memory bound on an unauthenticated write
// endpoint: at the cap a new id costs the oldest one, and an id that was READ
// recently counts as active — otherwise a returning player who has not beaten
// their record in a while is exactly who gets thrown away.
func TestBestEvictsLeastRecentlySeen(t *testing.T) {
	s := newBestStore("")
	// Fill to the cap with a hand-stamped `Seen` so the ordering is deterministic
	// rather than depending on wall-clock ties within one test run.
	for i := 0; i < maxBestRecords; i++ {
		id := padID(i)
		s.recs[id] = bestRecord{Distance: i, Seen: int64(i)}
	}
	oldest := padID(0)
	stale := padID(1)

	// Reading the oldest promotes it past the runner-up.
	s.get(oldest)
	s.merge(padID(maxBestRecords), 1, 1, 0, 0, nil)

	if len(s.recs) != maxBestRecords {
		t.Fatalf("map grew to %d, cap is %d", len(s.recs), maxBestRecords)
	}
	if _, ok := s.recs[stale]; ok {
		t.Errorf("least-recently-seen record survived eviction")
	}
	if _, ok := s.recs[oldest]; !ok {
		t.Errorf("a record read moments ago was evicted")
	}
	if _, ok := s.recs[padID(maxBestRecords)]; !ok {
		t.Errorf("the new record was not stored")
	}
}

// TestBestClampsHostileValues — nothing here can tell a real run from a made-up
// one, so the only job is keeping absurd numbers out of the dump file.
func TestBestClampsHostileValues(t *testing.T) {
	s := newBestStore("")
	rec := s.merge("player-cccc", clampBestValue(-5), clampBestValue(1<<40), 0, 0, nil)
	if rec.Distance != 0 {
		t.Errorf("negative distance stored as %d", rec.Distance)
	}
	if rec.Coins != maxBestValue {
		t.Errorf("huge coins stored as %d, wanted the clamp %d", rec.Coins, maxBestValue)
	}
}

// TestBestFileSurvivesRestart is the whole point of the file: a redeploy must not
// reset everybody's personal best.
func TestBestFileSurvivesRestart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "nested", "best.json")

	s := newBestStore(path)
	s.merge("player-dddd", 1234, 56, 0, 0, nil)
	if err := s.dump(); err != nil {
		t.Fatalf("dump: %v", err)
	}
	// A clean store is a no-op dump, not a rewrite.
	if err := s.dump(); err != nil {
		t.Fatalf("second dump: %v", err)
	}

	reborn := newBestStore(path)
	if rec := reborn.get("player-dddd"); rec.Distance != 1234 || rec.Coins != 56 {
		t.Fatalf("after restart the record read %+v", rec)
	}
	// A file naming an id the request path would refuse must not smuggle it in.
	reborn.recs["not a valid id"] = bestRecord{Distance: 9}
	if err := reborn.dump(); err != nil {
		t.Fatalf("dump with junk: %v", err)
	}
	third := newBestStore(path)
	if _, ok := third.recs["not a valid id"]; ok {
		t.Errorf("a malformed id survived a load")
	}
}

// TestBestFailedDumpStaysDirty — `dirty` is cleared BEFORE the write (so a merge
// landing mid-write is not swallowed), which means a failed write has to put it
// back. Without that the ticker's next pass sees a clean store and does nothing,
// and one transient failure — ENOSPC, or a volume not mounted yet — silently
// costs every record until somebody happens to write again.
func TestBestFailedDumpStaysDirty(t *testing.T) {
	// A path whose parent is a FILE, so MkdirAll fails every time.
	blocker := filepath.Join(t.TempDir(), "blocker")
	if err := os.WriteFile(blocker, []byte("x"), 0o644); err != nil {
		t.Fatalf("setup: %v", err)
	}
	s := newBestStore(filepath.Join(blocker, "sub", "best.json"))
	s.merge("player-eeee", 10, 1, 0, 0, nil)

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

// TestBestEndpointRoundTrip drives the route the client actually uses.
func TestBestEndpointRoundTrip(t *testing.T) {
	restore := allowedOrigins
	t.Cleanup(func() { allowedOrigins = restore })
	allowedOrigins = []string{"korjavin.github.io"}

	s := newBestStore("")
	const id = "0123456789abcdef0123456789abcdef"

	// A player who has never posted reads zeroes, not a 404: "no best yet" is a
	// normal answer and the client renders it as 0.
	rec := httptest.NewRecorder()
	s.handler(rec, httptest.NewRequest(http.MethodGet, "/best?id="+id, nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("GET status %d", rec.Code)
	}
	if d, c := decodeBest(t, rec); d != 0 || c != 0 {
		t.Fatalf("fresh id read %d/%d", d, c)
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-store" {
		t.Errorf("Cache-Control = %q", got)
	}

	post := func(body string, origin string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(http.MethodPost, "/best?id="+id, strings.NewReader(body))
		r.Header.Set("Content-Type", "application/json")
		if origin != "" {
			r.Header.Set("Origin", origin)
		}
		w := httptest.NewRecorder()
		s.handler(w, r)
		return w
	}

	rec = post(`{"distance":800,"coins":31}`, "https://korjavin.github.io")
	if rec.Code != http.StatusOK {
		t.Fatalf("POST status %d (%s)", rec.Code, rec.Body.String())
	}
	if d, c := decodeBest(t, rec); d != 800 || c != 31 {
		t.Fatalf("POST answered %d/%d", d, c)
	}
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "https://korjavin.github.io" {
		t.Errorf("CORS header = %q", got)
	}

	// The reply is the MERGED record, which is what lets the client trust it
	// blindly rather than having to max it against what it just sent.
	rec = post(`{"distance":10,"coins":99}`, "")
	if d, c := decodeBest(t, rec); d != 800 || c != 99 {
		t.Fatalf("merge answered %d/%d", d, c)
	}

	rec = httptest.NewRecorder()
	s.handler(rec, httptest.NewRequest(http.MethodGet, "/best?id="+id, nil))
	if d, c := decodeBest(t, rec); d != 800 || c != 99 {
		t.Fatalf("GET after merge read %d/%d", d, c)
	}
}

// TestBestEndpointGuards — every way in that is not a well-formed request.
func TestBestEndpointGuards(t *testing.T) {
	restore := allowedOrigins
	t.Cleanup(func() { allowedOrigins = restore })
	allowedOrigins = []string{"*"}

	s := newBestStore("")
	const id = "0123456789abcdef0123456789abcdef"

	// Escaped the way a browser would send them — the guard runs on the DECODED
	// value, which is what a path-traversal or injection attempt would arrive as.
	badIDs := []string{"", "short", "has spaces here", strings.Repeat("a", 65), "semi;colon", "../../etc/passwd"}
	for _, bad := range badIDs {
		rec := httptest.NewRecorder()
		s.handler(rec, httptest.NewRequest(http.MethodGet, "/best?id="+url.QueryEscape(bad), nil))
		if rec.Code != http.StatusBadRequest {
			t.Errorf("id %q: status %d, wanted 400", bad, rec.Code)
		}
	}

	// A body that is not a record, and one that is simply too big to be one.
	for _, body := range []string{"not json", strings.Repeat("x", maxBestBody+64)} {
		r := httptest.NewRequest(http.MethodPost, "/best?id="+id, strings.NewReader(body))
		rec := httptest.NewRecorder()
		s.handler(rec, r)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("body %.20q: status %d, wanted 400", body, rec.Code)
		}
	}

	rec := httptest.NewRecorder()
	s.handler(rec, httptest.NewRequest(http.MethodDelete, "/best?id="+id, nil))
	if rec.Code != http.StatusMethodNotAllowed {
		t.Errorf("DELETE status %d, wanted 405", rec.Code)
	}
}

// TestBestPreflight — the POST carries `Content-Type: application/json`, which is
// NOT a CORS "simple request", so the browser sends an OPTIONS first and drops
// the real request unless it is answered. Without this the whole feature would
// work in `curl` and silently do nothing in the game.
func TestBestPreflight(t *testing.T) {
	restore := allowedOrigins
	t.Cleanup(func() { allowedOrigins = restore })
	allowedOrigins = []string{"korjavin.github.io"}

	s := newBestStore("")
	req := httptest.NewRequest(http.MethodOptions, "/best?id=whatever", nil)
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
	if got := rec.Header().Get("Access-Control-Allow-Headers"); !strings.Contains(strings.ToLower(got), "content-type") {
		t.Errorf("allow-headers = %q", got)
	}

	// A foreign origin gets the preflight answered without the allow header, so
	// the browser refuses on its own — the same shape /ice uses.
	req = httptest.NewRequest(http.MethodOptions, "/best?id=whatever", nil)
	req.Header.Set("Origin", "https://evil.example")
	rec = httptest.NewRecorder()
	s.handler(rec, req)
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "" {
		t.Errorf("foreign origin got allow-origin %q", got)
	}
}

// padID makes a deterministic id long enough to satisfy playerIDRe.
func padID(i int) string { return fmt.Sprintf("player-%08d", i) }

// TestBestFoundIsUnion — the passport set merges across a player's devices:
// shaped ids join, repeats and misshapen ids change nothing, a smaller second
// POST never shrinks what the first one stored, and an old client that posts
// no `found` at all raises nothing.
func TestBestFoundIsUnion(t *testing.T) {
	s := newBestStore("")

	rec := s.merge("player-ff", 0, 0, 0, 0, []string{"stonehenge", "moai"})
	if !slices.Equal(rec.Found, []string{"moai", "stonehenge"}) {
		t.Fatalf("first found merge = %q", rec.Found)
	}
	// A repeat, a duplicate inside one body and three hostile ids: only the
	// one shaped stranger joins.
	rec = s.merge("player-ff", 0, 0, 0, 0, []string{"moai", "moai", "../x", "", "GIZA", "giza"})
	if !slices.Equal(rec.Found, []string{"giza", "moai", "stonehenge"}) {
		t.Fatalf("second found merge = %q", rec.Found)
	}
	// A smaller POST — a device that has found less — removes nothing.
	rec = s.merge("player-ff", 0, 0, 0, 0, []string{"moai"})
	if !slices.Equal(rec.Found, []string{"giza", "moai", "stonehenge"}) {
		t.Fatalf("a smaller POST shrank the set: %q", rec.Found)
	}
	// An old client posts no found at all: nil unions nothing, raises nothing.
	rec = s.merge("player-ff", 9, 9, 0, 0, nil)
	if !slices.Equal(rec.Found, []string{"giza", "moai", "stonehenge"}) || rec.Distance != 9 {
		t.Fatalf("a foundless POST moved the set: %+v", rec)
	}
}

// TestBestFoundBounded — at the cap the STORED set wins over the excess: what
// is already held is never dropped for a newcomer.
func TestBestFoundBounded(t *testing.T) {
	s := newBestStore("")
	if rec := s.merge("player-cap", 0, 0, 0, 0, []string{"kept_a", "kept_b"}); len(rec.Found) != 2 {
		t.Fatalf("seed = %q", rec.Found)
	}
	bulk := make([]string, 0, 200)
	for i := 0; i < 200; i++ {
		bulk = append(bulk, fmt.Sprintf("site_%03d", i))
	}
	rec := s.merge("player-cap", 0, 0, 0, 0, bulk)
	if len(rec.Found) != maxFoundIDs {
		t.Fatalf("set grew to %d, cap is %d", len(rec.Found), maxFoundIDs)
	}
	if !slices.Contains(rec.Found, "kept_a") || !slices.Contains(rec.Found, "kept_b") {
		t.Fatalf("the stored set lost to the excess: %q", rec.Found[:4])
	}
}

// TestBestFoundRoundTrip — POST a set through the real handler, GET it back,
// POST a smaller one and keep the union.
func TestBestFoundRoundTrip(t *testing.T) {
	s := newBestStore("")
	const id = "fedcba9876543210fedcba9876543210"

	decodeFound := func(rec *httptest.ResponseRecorder) []string {
		t.Helper()
		var decoded map[string]any
		if err := json.Unmarshal(rec.Body.Bytes(), &decoded); err != nil {
			t.Fatalf("decode %q: %v", rec.Body.String(), err)
		}
		// A fresh record stores nil, which arrives as JSON null — an empty
		// set, not an error.
		list, _ := decoded["found"].([]any)
		out := []string{}
		for _, v := range list {
			str, ok := v.(string)
			if !ok {
				t.Fatalf("found entry %v is not a string", v)
			}
			out = append(out, str)
		}
		return out
	}
	post := func(body string) *httptest.ResponseRecorder {
		t.Helper()
		r := httptest.NewRequest(http.MethodPost, "/best?id="+id, strings.NewReader(body))
		w := httptest.NewRecorder()
		s.handler(w, r)
		if w.Code != http.StatusOK {
			t.Fatalf("POST status %d (%s)", w.Code, w.Body.String())
		}
		return w
	}
	get := func() *httptest.ResponseRecorder {
		w := httptest.NewRecorder()
		s.handler(w, httptest.NewRequest(http.MethodGet, "/best?id="+id, nil))
		if w.Code != http.StatusOK {
			t.Fatalf("GET status %d", w.Code)
		}
		return w
	}

	if got := decodeFound(get()); len(got) != 0 {
		t.Fatalf("fresh id found %q", got)
	}
	post(`{"distance":5,"found":["giza","moai"]}`)
	if got := decodeFound(get()); !slices.Equal(got, []string{"giza", "moai"}) {
		t.Fatalf("after POST found %q", got)
	}
	// A smaller POST unions rather than replaces, and the POST reply carries
	// the merged set the client can trust.
	if got := decodeFound(post(`{"distance":6,"found":["moai","petra"]}`)); !slices.Equal(got, []string{"giza", "moai", "petra"}) {
		t.Fatalf("POST reply found %q", got)
	}
	if got := decodeFound(get()); !slices.Equal(got, []string{"giza", "moai", "petra"}) {
		t.Fatalf("after smaller POST found %q", got)
	}
}

// TestBestFoundSurvivesRestart — the set persists across a dump/load cycle,
// and a hand-edited dump cannot smuggle past the request path's bounds.
func TestBestFoundSurvivesRestart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "found", "best.json")

	s := newBestStore(path)
	s.merge("player-ffff", 3, 1, 0, 0, []string{"giza", "moai", "petra"})
	if err := s.dump(); err != nil {
		t.Fatalf("dump: %v", err)
	}
	reborn := newBestStore(path)
	if rec := reborn.get("player-ffff"); !slices.Equal(rec.Found, []string{"giza", "moai", "petra"}) {
		t.Fatalf("after restart found %q", rec.Found)
	}

	// A dump carrying hostile ids and an over-long list loads bounded: shaped
	// only, deduplicated, sorted, capped — the request path's rule, not a
	// second one.
	many := []string{"../x", "MOAI"}
	for i := 0; i < 200; i++ {
		many = append(many, fmt.Sprintf("bulk_%03d", i))
	}
	reborn.recs["player-junk"] = bestRecord{Found: many}
	if err := reborn.dump(); err != nil {
		t.Fatalf("dump with junk: %v", err)
	}
	third := newBestStore(path)
	rec := third.get("player-junk")
	if len(rec.Found) != maxFoundIDs {
		t.Fatalf("junk dump loaded %d ids, cap is %d", len(rec.Found), maxFoundIDs)
	}
	if slices.Contains(rec.Found, "../x") || slices.Contains(rec.Found, "MOAI") {
		t.Fatalf("a hostile id survived a load: %q", rec.Found[:4])
	}
}

// TestBestFoundRejectsOversizeBody — a well-formed body over maxBestBody is a
// 400, not a truncation: the size guard runs before the decode, so validity
// cannot smuggle size past it.
func TestBestFoundRejectsOversizeBody(t *testing.T) {
	s := newBestStore("")
	const id = "0123456789abcdef0123456789abcdef"

	long := strings.Repeat("a", 32)
	ids := make([]string, 0, 150)
	for i := 0; i < 150; i++ {
		ids = append(ids, long)
	}
	body, err := json.Marshal(map[string]any{"distance": 1, "found": ids})
	if err != nil {
		t.Fatalf("fixture: %v", err)
	}
	// The fixture guards itself: if the cap ever moves past it, this fails
	// instead of passing vacuously.
	if len(body) <= maxBestBody {
		t.Fatalf("fixture body is %d bytes, wanted over the %d cap", len(body), maxBestBody)
	}
	r := httptest.NewRequest(http.MethodPost, "/best?id="+id, bytes.NewReader(body))
	w := httptest.NewRecorder()
	s.handler(w, r)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("oversize body status %d, wanted 400", w.Code)
	}
}
