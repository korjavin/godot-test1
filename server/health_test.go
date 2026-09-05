package main

// health_test.go — the post-incident rule that /healthz reports on SIGNALLING and
// nothing else (bead godot-test1-xuz).
//
// THE INCIDENT, 2026-09-05: the prod host filled its disk with ~500 SHA-pinned
// images. Every 30 s the lobby logged `best: dump failed: write
// /data/best.json.tmp: no space left on device`, the container went UNHEALTHY, and
// Traefik dropped the unhealthy router — so /ws, /ice, /rooms and /best fell
// through to the web client's catch-all and nobody could create a room. The disk
// was the fault; the BLAST RADIUS was that a service whose whole job needs no disk
// went off the air with its optional scoreboard.
//
// What this file pins is the recovery property, and it is deliberately about
// BEHAVIOUR rather than about the current shape of the code: with the store's
// writes failing every single time, /healthz still answers 200 with ok:true, and
// /best still serves correct records out of memory. Both halves matter — a health
// endpoint that stayed up while the service it fronts had stopped working would be
// the opposite bug.

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// unwritableStore returns a bestStore whose every dump() fails, the way ENOSPC
// made the real one fail. The mechanism is best_test.go's
// TestBestFailedDumpStaysDirty verbatim — a path whose parent is a FILE, so
// MkdirAll can never succeed — because "the disk refuses this write" is the same
// class of failure however it is produced, and a full filesystem is not something
// a unit test gets to arrange.
func unwritableStore(t *testing.T) *bestStore {
	t.Helper()
	blocker := filepath.Join(t.TempDir(), "blocker")
	if err := os.WriteFile(blocker, []byte("x"), 0o644); err != nil {
		t.Fatalf("setup: %v", err)
	}
	return newBestStore(filepath.Join(blocker, "sub", "best.json"))
}

// TestHealthzSurvivesFailedDump — the acceptance criterion of the bead, and an
// HONEST account of what it can and cannot measure.
//
// It measures: /healthz answers 200 with ok:true and a live room count. It does
// NOT measure "an unwritable store cannot affect it" — `healthzHandler` takes the
// hub and nothing else, so the store is not reachable from the code under test and
// no assertion here could see it. Deleting the failing-store setup below leaves
// this test passing, which was verified. The store is here as SCENARIO
// DOCUMENTATION — this is the shape of the world during the incident — and the
// real guard against somebody plumbing dump health into /healthz is the
// signature: widening it is a compile-level change that lands the author in this
// file and in healthzHandler's comment.
func TestHealthzSurvivesFailedDump(t *testing.T) {
	hub := NewHub()
	store := unwritableStore(t)
	store.merge("player-aaaa", 1234, 56, 78, 0)

	// Prove the premise before asserting anything about it: a dump that quietly
	// SUCCEEDED would make every assertion below pass while measuring nothing.
	// Twice, because the incident's disk was full for hours, not for one tick.
	for i := 0; i < 2; i++ {
		if err := store.dump(); err == nil {
			t.Fatalf("dump %d into %s unexpectedly succeeded — the premise of this test is gone", i, store.path)
		}
	}

	rec := httptest.NewRecorder()
	healthzHandler(hub)(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("/healthz answered %d while the best-scores dump was failing — "+
			"Traefik drops an unhealthy router and takes /ws down with it", rec.Code)
	}
	var body struct {
		OK    bool `json:"ok"`
		Rooms int  `json:"rooms"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("/healthz body is not JSON: %v (%q)", err, rec.Body.String())
	}
	if !body.OK {
		t.Fatalf("/healthz reported ok=false with only the scoreboard broken; body %q", rec.Body.String())
	}

	// And the signalling it reports on really is still there: a room can be
	// created and counted while the disk refuses every write. This is the thing
	// the owner could not do during the incident.
	if _, _, err := hub.Join("", "host", "id-1"); err != nil {
		t.Fatalf("hub.Join with an unwritable best store: %v", err)
	}
	rec = httptest.NewRecorder()
	healthzHandler(hub)(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if body.Rooms != 1 {
		t.Fatalf("/healthz reported rooms=%d after one room was created", body.Rooms)
	}
}

// TestBestServesWhileDumpFails — the other half of "the lobby needs no disk": the
// records themselves keep working out of memory, so a full disk costs DURABILITY
// (the records do not survive a redeploy) and nothing else. Without this, "healthz
// stays up" could be true of a service that had silently stopped answering.
// It writes no `Origin` header and `bestStore.handler` only uses `corsOrigin` to
// SET a response header — it never rejects — so this needs no `allowedOrigins`
// mutation, and deliberately does not make one: that global is shared with
// best_test.go and lobby_test.go, and a package-global write for nothing is churn
// (verified: adding it changes no outcome).
func TestBestServesWhileDumpFails(t *testing.T) {
	store := unwritableStore(t)

	const id = "player-bbbb"
	post := httptest.NewRequest(http.MethodPost, "/best?id="+id,
		strings.NewReader(`{"distance":500,"coins":40,"lifetime":40,"spent":0}`))
	post.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	store.handler(rec, post)
	if rec.Code != http.StatusOK {
		t.Fatalf("POST /best answered %d with an unwritable store", rec.Code)
	}

	// The premise, asserted AFTER the POST rather than before it: a CLEAN store's
	// dump is a deliberate no-op returning nil (best.go), so dumping an untouched
	// store proves nothing. Now that a record is in memory the write is really
	// attempted, and really refused.
	if err := store.dump(); err == nil {
		t.Fatalf("dump into %s unexpectedly succeeded — the premise of this test is gone", store.path)
	}

	rec = httptest.NewRecorder()
	store.handler(rec, httptest.NewRequest(http.MethodGet, "/best?id="+id, nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /best answered %d with an unwritable store", rec.Code)
	}
	var got struct {
		Distance int `json:"distance"`
		Coins    int `json:"coins"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("GET /best body is not JSON: %v (%q)", err, rec.Body.String())
	}
	if got.Distance != 500 || got.Coins != 40 {
		t.Fatalf("GET /best returned distance=%d coins=%d, want 500/40 — records must "+
			"still be correct in memory when only the dump is broken", got.Distance, got.Coins)
	}
}
