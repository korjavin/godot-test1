// auth_test.go — the /auth acceptance criteria: one-shot links, sessions in
// fragments, the one-time link, and the same boundedness the sibling stores
// promise. Table stakes first: the clock is injected (no sleeps anywhere — a
// test that sleeps is a test that flakes), the mailer is replaced (nothing
// here touches a network), and every map the store holds is asserted for what
// it must NOT contain as well as what it must.

package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

// authEnv is one lobby's three stores, wired the way main wires them.
type authEnv struct {
	best *bestStore
	save *saveStore
	auth *authStore
}

func newAuthEnv() *authEnv {
	b := newBestStore("")
	s := newSaveStore("")
	return &authEnv{best: b, save: s, auth: newAuthStore("", b, s)}
}

// postMagic is POST /auth/magic from one client ip.
func postMagic(e *authEnv, email, ip string) *httptest.ResponseRecorder {
	body, _ := json.Marshal(map[string]any{"email": email})
	r := httptest.NewRequest(http.MethodPost, "/auth/magic", bytes.NewReader(body))
	r.Header.Set("Content-Type", "application/json")
	r.Header.Set("X-Real-Ip", ip)
	w := httptest.NewRecorder()
	e.auth.magicHandler(w, r)
	return w
}

// decodeAuthError reads the {"error": ...} refusal every /auth error takes.
func decodeAuthError(t *testing.T, rec *httptest.ResponseRecorder) string {
	t.Helper()
	var body struct {
		Error string `json:"error"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("refusal %q does not decode: %v", rec.Body.String(), err)
	}
	return body.Error
}

// captureSend replaces the mailer with a channel: the test waits on the
// send, never sleeps for it.
func captureSend(e *authEnv) chan struct {
	to   string
	link string
} {
	got := make(chan struct {
		to   string
		link string
	}, 1)
	e.auth.send = func(to, link string) error {
		got <- struct {
			to   string
			link string
		}{to, link}
		return nil
	}
	return got
}

// waitLink waits for the mailed link, failing the test instead of hanging it.
func waitLink(t *testing.T, got chan struct {
	to   string
	link string
}) (string, string) {
	t.Helper()
	select {
	case m := <-got:
		return m.to, m.link
	case <-time.After(5 * time.Second):
		t.Fatalf("the mailer was never called")
		return "", ""
	}
}

// tokenFromLink splits the token off a .../auth/verify?t=<token> link.
func tokenFromLink(t *testing.T, link string) string {
	t.Helper()
	i := strings.LastIndex(link, "t=")
	if i < 0 {
		t.Fatalf("link %q has no token", link)
	}
	tok := link[i+2:]
	if !tokenRe.MatchString(tok) {
		t.Fatalf("link token %q is not 64 hex", tok)
	}
	return tok
}

// verifyToken runs the full mailed flow: magic, capture, open the link. It
// returns the session from the 302 fragment.
func verifyToken(t *testing.T, e *authEnv, email, ip string) string {
	t.Helper()
	got := captureSend(e)
	if rec := postMagic(e, email, ip); rec.Code != http.StatusOK {
		t.Fatalf("magic status %d (%s)", rec.Code, rec.Body.String())
	}
	_, link := waitLink(t, got)
	tok := tokenFromLink(t, link)
	rec := httptest.NewRecorder()
	e.auth.verifyHandler(rec, httptest.NewRequest(http.MethodGet, "/auth/verify?t="+tok, nil))
	if rec.Code != http.StatusFound {
		t.Fatalf("verify status %d, wanted 302", rec.Code)
	}
	loc := rec.Header().Get("Location")
	i := strings.LastIndex(loc, "#session=")
	if i < 0 {
		t.Fatalf("Location %q carries no session fragment", loc)
	}
	sess := loc[i+len("#session="):]
	if !tokenRe.MatchString(sess) {
		t.Fatalf("session %q is not 64 hex", sess)
	}
	return sess
}

// insertSession mints a session straight into the map for tests of the
// middleware rather than the minting.
func insertSession(e *authEnv, sub string, exp int64) string {
	sess, err := mintToken()
	if err != nil {
		panic(err)
	}
	e.auth.mu.Lock()
	e.auth.sessions[tokenKey(sess)] = authSession{Sub: sub, Exp: exp}
	e.auth.mu.Unlock()
	return sess
}

// authedBest drives /best through the middleware, the way main wires it.
func authedBest(e *authEnv, method, id, sess, body string) *httptest.ResponseRecorder {
	var r *http.Request
	if body == "" {
		r = httptest.NewRequest(method, "/best?id="+id, nil)
	} else {
		r = httptest.NewRequest(method, "/best?id="+id, strings.NewReader(body))
		r.Header.Set("Content-Type", "application/json")
	}
	if sess != "" {
		r.Header.Set("X-Session", sess)
	}
	w := httptest.NewRecorder()
	e.auth.withSession(e.best.handler)(w, r)
	return w
}

// authedSave drives /save through the middleware.
func authedSave(e *authEnv, method, id, sess, body string) *httptest.ResponseRecorder {
	var r *http.Request
	if body == "" {
		r = httptest.NewRequest(method, "/save?id="+id, nil)
	} else {
		r = httptest.NewRequest(method, "/save?id="+id, strings.NewReader(body))
		r.Header.Set("Content-Type", "application/json")
	}
	if sess != "" {
		r.Header.Set("X-Session", sess)
	}
	w := httptest.NewRecorder()
	e.auth.withSession(e.save.handler)(w, r)
	return w
}

// lockBuffer is a bytes.Buffer safe to String() while a logging goroutine
// Writes: the dev-link poll's race would otherwise fail -race.
type lockBuffer struct {
	mu sync.Mutex
	b  bytes.Buffer
}

func (l *lockBuffer) Write(p []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.b.Write(p)
}

func (l *lockBuffer) String() string {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.b.String()
}

func decodeAuthBest(t *testing.T, rec *httptest.ResponseRecorder) bestRecord {
	t.Helper()
	var br bestRecord
	if err := json.Unmarshal(rec.Body.Bytes(), &br); err != nil {
		t.Fatalf("best decode %q: %v", rec.Body.String(), err)
	}
	return br
}

// TestAuthMagicMailsALinkOnce: one token mailed, once, hashed at rest, and
// the address in no map anywhere.
func TestAuthMagicMailsALinkOnce(t *testing.T) {
	t.Setenv("SMTP_HOST", "mail.example")
	e := newAuthEnv()
	got := captureSend(e)
	const addr = "player@example.com"

	rec := postMagic(e, addr, "203.0.113.7")
	if rec.Code != http.StatusOK {
		t.Fatalf("magic status %d (%s)", rec.Code, rec.Body.String())
	}
	var ok struct {
		OK int `json:"ok"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &ok); err != nil || ok.OK != 1 {
		t.Fatalf("magic body %q, wanted {\"ok\":1}", rec.Body.String())
	}
	if cc := rec.Header().Get("Cache-Control"); cc != "no-store" {
		t.Errorf("Cache-Control = %q, wanted no-store", cc)
	}

	to, link := waitLink(t, got)
	if to != addr {
		t.Errorf("mailed to %q, wanted the posted address", to)
	}
	if !strings.HasPrefix(link, "http://") || !strings.Contains(link, "/auth/verify?t=") {
		t.Fatalf("link %q is not <scheme>://host/auth/verify?t=<token>", link)
	}
	tok := tokenFromLink(t, link)

	e.auth.mu.Lock()
	defer e.auth.mu.Unlock()
	if len(e.auth.pending) != 1 {
		t.Fatalf("pending holds %d tokens, wanted 1", len(e.auth.pending))
	}
	for k, p := range e.auth.pending {
		// Keyed by the digest, never the raw token: a leaked map must hold
		// nothing presentable.
		if !tokenRe.MatchString(k) {
			t.Errorf("pending key %q is not a digest", k)
		}
		if k == tok {
			t.Errorf("pending is keyed by the raw token")
		}
		if p.Sub != subForEmail(addr) {
			t.Errorf("pending sub %q, wanted the address hash", p.Sub)
		}
	}
	// The address in NO map: pending, sessions, aliases, limits.
	var dump strings.Builder
	for k, p := range e.auth.pending {
		fmt.Fprintf(&dump, "%s%v", k, p)
	}
	for k, v := range e.auth.sessions {
		fmt.Fprintf(&dump, "%s%v", k, v)
	}
	for k, v := range e.auth.aliases {
		fmt.Fprintf(&dump, "%s%s", k, v)
	}
	for k, v := range e.auth.limits {
		fmt.Fprintf(&dump, "%s%v", k, v)
	}
	if strings.Contains(dump.String(), addr) {
		t.Errorf("the address is stored in memory: %q", dump.String())
	}
}

// TestAuthMagicRefusesBadAddresses: every malformed address names itself, and
// an oversize body never decodes.
func TestAuthMagicRefusesBadAddresses(t *testing.T) {
	t.Setenv("SMTP_HOST", "mail.example")
	e := newAuthEnv()
	e.auth.send = func(to, link string) error { return nil }
	bad := []string{
		"",
		"not-an-address",
		"@nodomain",
		"nolocal@",
		"two@@signs.example",
		"two@signs@example",
		"sp ace@example.com",
		"tab\there@example.com",
		"new\nline@example.com",
		"carriage@example.com\rbcc:evil@example.com",
		strings.Repeat("a", 300) + "@example.com",
	}
	for _, addr := range bad {
		rec := postMagic(e, addr, "203.0.113.7")
		if rec.Code != http.StatusBadRequest {
			t.Errorf("address %q: status %d, wanted 400", addr, rec.Code)
			continue
		}
		if got := decodeAuthError(t, rec); got != "That does not look like an email address" {
			t.Errorf("address %q: error %q", addr, got)
		}
	}
	if n := len(e.auth.pending); n != 0 {
		t.Errorf("refused addresses minted %d pending tokens", n)
	}

	rec := postMagic(e, strings.Repeat("x", 2048), "203.0.113.7")
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("2 KB body: status %d, wanted 400", rec.Code)
	}
	if got := decodeAuthError(t, rec); got != "bad body" {
		t.Errorf("2 KB body: error %q, wanted bad body", got)
	}
}

// TestAuthMagicRateLimited: ten links per ip per ten minutes, three per email
// per fifteen — then the windows pass and both pass again. The clock is
// injected, so no part of this sleeps.
func TestAuthMagicRateLimited(t *testing.T) {
	t.Setenv("SMTP_HOST", "mail.example")
	e := newAuthEnv()
	e.auth.send = func(to, link string) error { return nil }
	base := time.Now()
	cur := base
	e.auth.now = func() time.Time { return cur }

	for i := 0; i < 10; i++ {
		if rec := postMagic(e, fmt.Sprintf("r%d@example.com", i), "10.0.0.1"); rec.Code != http.StatusOK {
			t.Fatalf("link %d status %d (%s)", i, rec.Code, rec.Body.String())
		}
	}
	rec := postMagic(e, "r10@example.com", "10.0.0.1")
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("11th link from one ip: status %d, wanted 429", rec.Code)
	}
	if got, want := decodeAuthError(t, rec), "Too many sign-in links — try again in 10 minutes"; got != want {
		t.Errorf("ip refusal %q, wanted %q", got, want)
	}

	for _, ip := range []string{"10.0.0.2", "10.0.0.3", "10.0.0.4"} {
		if rec := postMagic(e, "single@example.com", ip); rec.Code != http.StatusOK {
			t.Fatalf("email link from %s status %d", ip, rec.Code)
		}
	}
	rec = postMagic(e, "single@example.com", "10.0.0.5")
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("4th link to one address: status %d, wanted 429", rec.Code)
	}
	if got, want := decodeAuthError(t, rec), "Too many sign-in links — try again in 15 minutes"; got != want {
		t.Errorf("email refusal %q, wanted %q", got, want)
	}

	cur = base.Add(16 * time.Minute)
	if rec := postMagic(e, "single@example.com", "10.0.0.6"); rec.Code != http.StatusOK {
		t.Errorf("after the window: email status %d, wanted 200", rec.Code)
	}
	if rec := postMagic(e, "fresh@example.com", "10.0.0.1"); rec.Code != http.StatusOK {
		t.Errorf("after the window: ip status %d, wanted 200", rec.Code)
	}
}

// TestAuthMagicNotConfigured: no relay and no dev flag is a plain 503; the
// dev flag logs the link instead and skips the refusal.
func TestAuthMagicNotConfigured(t *testing.T) {
	t.Setenv("SMTP_HOST", "")
	e := newAuthEnv()
	rec := postMagic(e, "player@example.com", "203.0.113.7")
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("unconfigured magic status %d, wanted 503", rec.Code)
	}
	if got := decodeAuthError(t, rec); got != "Sign-in is not set up on this lobby" {
		t.Errorf("unconfigured magic error %q", got)
	}

	t.Setenv("AUTH_DEV_LOG_LINK", "1")
	// Guarded: the dev send logs from its goroutine while the poll below
	// reads, and bytes.Buffer is not goroutine-safe.
	buf := &lockBuffer{}
	log.SetOutput(buf)
	t.Cleanup(func() { log.SetOutput(os.Stderr) })
	dev := newAuthEnv()
	if rec := postMagic(dev, "player@example.com", "203.0.113.7"); rec.Code != http.StatusOK {
		t.Fatalf("dev magic status %d, wanted 200", rec.Code)
	}
	deadline := time.Now().Add(5 * time.Second)
	for {
		if strings.Contains(buf.String(), "/auth/verify?t=") {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("the dev link never landed in the log")
		}
		time.Sleep(10 * time.Millisecond)
	}
}

// TestAuthVerifyRedirectsWithSessionInFragment: the mailed token 302s to the
// game URL with the session after the #, and the session authenticates.
func TestAuthVerifyRedirectsWithSessionInFragment(t *testing.T) {
	t.Setenv("SMTP_HOST", "mail.example")
	t.Setenv("AUTH_GAME_URL", "https://game.example/play")
	e := newAuthEnv()
	sess := verifyToken(t, e, "player@example.com", "203.0.113.7")

	// The fragment form exactly: game URL, then #session=<64 hex>.
	got := captureSend(e)
	if rec := postMagic(e, "second@example.com", "203.0.113.8"); rec.Code != http.StatusOK {
		t.Fatalf("magic status %d", rec.Code)
	}
	_, link := waitLink(t, got)
	tok := tokenFromLink(t, link)
	rec := httptest.NewRecorder()
	e.auth.verifyHandler(rec, httptest.NewRequest(http.MethodGet, "/auth/verify?t="+tok, nil))
	if rec.Code != http.StatusFound {
		t.Fatalf("verify status %d, wanted 302", rec.Code)
	}
	loc := rec.Header().Get("Location")
	if !strings.HasPrefix(loc, "https://game.example/play#session=") {
		t.Fatalf("Location %q, wanted the game URL with #session=", loc)
	}
	if got := rec.Header().Get("Cache-Control"); got != "no-store" {
		t.Errorf("Cache-Control = %q, wanted no-store", got)
	}

	// And the session from the first flow authenticates a fresh sub.
	if rec := authedBest(e, http.MethodGet, "dddddddddddddddddddddddddddddddd", sess, ""); rec.Code != http.StatusOK {
		t.Fatalf("session GET /best status %d", rec.Code)
	} else if br := decodeAuthBest(t, rec); br.Distance != 0 {
		t.Fatalf("fresh sub reads distance %d, wanted 0", br.Distance)
	}
}

// TestAuthTokenSingleUse: the second opener, an unknown token and garbage all
// land on the same human page — 200, text/html, never a 4xx.
func TestAuthTokenSingleUse(t *testing.T) {
	t.Setenv("SMTP_HOST", "mail.example")
	e := newAuthEnv()
	got := captureSend(e)
	if rec := postMagic(e, "player@example.com", "203.0.113.7"); rec.Code != http.StatusOK {
		t.Fatalf("magic status %d", rec.Code)
	}
	_, link := waitLink(t, got)
	tok := tokenFromLink(t, link)

	open := func(tok string) *httptest.ResponseRecorder {
		rec := httptest.NewRecorder()
		e.auth.verifyHandler(rec, httptest.NewRequest(http.MethodGet, "/auth/verify?t="+tok, nil))
		return rec
	}
	if rec := open(tok); rec.Code != http.StatusFound {
		t.Fatalf("first open status %d, wanted 302", rec.Code)
	}
	for name, rec := range map[string]*httptest.ResponseRecorder{
		"second open":   open(tok),
		"unknown token": open(strings.Repeat("ab", 32)),
		"garbage":       open("zzz"),
		"empty":         open(""),
	} {
		if rec.Code != http.StatusOK {
			t.Errorf("%s: status %d, wanted the expired page (200)", name, rec.Code)
			continue
		}
		if ct := rec.Header().Get("Content-Type"); !strings.HasPrefix(ct, "text/html") {
			t.Errorf("%s: Content-Type %q, wanted text/html", name, ct)
		}
		if !strings.Contains(rec.Body.String(), "expired or was already used") {
			t.Errorf("%s: body %q names nothing", name, rec.Body.String())
		}
	}
}

// TestAuthTokenExpires: sixteen minutes later the mailed link is paper, and
// thirty-one days later the session is too — the client signs out on the
// 401's own words.
func TestAuthTokenExpires(t *testing.T) {
	t.Setenv("SMTP_HOST", "mail.example")
	e := newAuthEnv()
	e.auth.send = func(to, link string) error { return nil }
	base := time.Now()
	cur := base
	e.auth.now = func() time.Time { return cur }

	body, _ := json.Marshal(map[string]any{"email": "player@example.com"})
	r := httptest.NewRequest(http.MethodPost, "/auth/magic", bytes.NewReader(body))
	r.Header.Set("X-Real-Ip", "203.0.113.7")
	w := httptest.NewRecorder()
	e.auth.magicHandler(w, r)
	if w.Code != http.StatusOK {
		t.Fatalf("magic status %d", w.Code)
	}
	// The test digests nothing: any pending key back through the route would
	// be the raw-token bug, so the count — not the key — is the assertion.
	e.auth.mu.Lock()
	n := len(e.auth.pending)
	e.auth.mu.Unlock()
	if n != 1 {
		t.Fatalf("pending holds %d tokens, wanted 1", n)
	}

	cur = base.Add(16 * time.Minute)
	// Re-mint through the route to keep the raw token out of the test: the
	// first token expired unopened, so a FRESH link must verify...
	got := captureSend(e)
	if rec := postMagic(e, "player@example.com", "203.0.113.7"); rec.Code != http.StatusOK {
		t.Fatalf("second magic status %d", rec.Code)
	}
	_, link := waitLink(t, got)
	fresh := tokenFromLink(t, link)
	// ...while the sixteen-minute-old flow is gone: verify the FRESH token
	// with the clock wound further still, and it too is paper.
	cur = base.Add(32 * time.Minute)
	rec := httptest.NewRecorder()
	e.auth.verifyHandler(rec, httptest.NewRequest(http.MethodGet, "/auth/verify?t="+fresh, nil))
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "expired or was already used") {
		t.Fatalf("aged link: status %d, wanted the expired page", rec.Code)
	}

	// A session lives thirty days, not thirty-one.
	cur = base
	sess := verifyToken(t, e, "sitter@example.com", "203.0.113.9")
	cur = base.Add(31 * 24 * time.Hour)
	rec = authedBest(e, http.MethodGet, "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee", sess, "")
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("aged session: status %d, wanted 401", rec.Code)
	}
	if got := decodeAuthError(t, rec); got != "Your sign-in has expired — send a new link" {
		t.Errorf("aged session error %q", got)
	}
}

// TestAuthSessionRewritesIdToSub: one login, two ids — the session's sub
// answers both, and the anon id alone still reads its own nothing.
func TestAuthSessionRewritesIdToSub(t *testing.T) {
	t.Setenv("SMTP_HOST", "mail.example")
	e := newAuthEnv()
	sess := verifyToken(t, e, "player@example.com", "203.0.113.7")

	const anonA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	const anonB = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
	rec := authedBest(e, http.MethodPost, anonA, sess, `{"distance":50}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("session POST status %d (%s)", rec.Code, rec.Body.String())
	}
	if br := decodeAuthBest(t, rec); br.Distance != 50 {
		t.Fatalf("session POST answered distance %d", br.Distance)
	}

	// Another anon id under the same session reads the same record.
	if rec := authedBest(e, http.MethodGet, anonB, sess, ""); rec.Code != http.StatusOK {
		t.Fatalf("session GET other id status %d", rec.Code)
	} else if br := decodeAuthBest(t, rec); br.Distance != 50 {
		t.Fatalf("session GET other id reads distance %d, wanted 50", br.Distance)
	}

	// Without the header the anon id is still its own empty record: the
	// middleware never serves sub to strangers.
	if rec := authedBest(e, http.MethodGet, anonA, "", ""); rec.Code != http.StatusOK {
		t.Fatalf("anonymous GET status %d", rec.Code)
	} else if br := decodeAuthBest(t, rec); br.Distance != 0 {
		t.Fatalf("anonymous GET reads distance %d, wanted 0", br.Distance)
	}
}

// linkFixture seeds the merge test's three records: the anon id holds 100
// and one stamp with a t=50 save; sub holds 50, another stamp, a t=40 save.
func linkFixture(t *testing.T, e *authEnv, anon, sub string) {
	t.Helper()
	if rec := authedBest(e, http.MethodPost, anon, "", `{"distance":100,"found":["stamp_a"]}`); rec.Code != http.StatusOK {
		t.Fatalf("seed anon best status %d", rec.Code)
	}
	if rec := authedSave(e, http.MethodPost, anon, "", `{"blob":"B50","saved_at":50}`); rec.Code != http.StatusOK {
		t.Fatalf("seed anon save status %d", rec.Code)
	}
	if rec := authedBest(e, http.MethodPost, sub, "", `{"distance":50,"found":["stamp_b"]}`); rec.Code != http.StatusOK {
		t.Fatalf("seed sub best status %d", rec.Code)
	}
	if rec := authedSave(e, http.MethodPost, sub, "", `{"blob":"B40","saved_at":40}`); rec.Code != http.StatusOK {
		t.Fatalf("seed sub save status %d", rec.Code)
	}
}

func subBest(t *testing.T, e *authEnv, sub, sess string) bestRecord {
	t.Helper()
	rec := authedBest(e, http.MethodGet, sub, sess, "")
	if rec.Code != http.StatusOK {
		t.Fatalf("sub GET status %d", rec.Code)
	}
	return decodeAuthBest(t, rec)
}

func subSave(t *testing.T, e *authEnv, sub, sess string) (string, int64) {
	t.Helper()
	rec := authedSave(e, http.MethodGet, sub, sess, "")
	if rec.Code != http.StatusOK {
		t.Fatalf("sub save GET status %d", rec.Code)
	}
	var body struct {
		Blob    string `json:"blob"`
		SavedAt int64  `json:"saved_at"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("sub save decode: %v", err)
	}
	return body.Blob, body.SavedAt
}

// TestAuthLinkMergesOnce: the first authed anon request merges /best monotone
// and /save by stamp, then never again — an anon write after the link stays
// the anon's own.
func TestAuthLinkMergesOnce(t *testing.T) {
	t.Setenv("SMTP_HOST", "mail.example")
	e := newAuthEnv()
	const email = "link@example.com"
	sub := subForEmail(email)
	const anon = "cccccccccccccccccccccccccccccccc"
	linkFixture(t, e, anon, sub)
	sess := verifyToken(t, e, email, "203.0.113.7")

	// The first authed request naming anon fires the link.
	if rec := authedBest(e, http.MethodGet, anon, sess, ""); rec.Code != http.StatusOK {
		t.Fatalf("first authed anon GET status %d", rec.Code)
	}
	if br := subBest(t, e, sub, sess); br.Distance != 100 {
		t.Errorf("linked distance %d, wanted 100", br.Distance)
	} else if len(br.Found) != 2 || br.Found[0] != "stamp_a" || br.Found[1] != "stamp_b" {
		t.Errorf("linked found %q, wanted the union", br.Found)
	}
	if blob, at := subSave(t, e, sub, sess); blob != "B50" || at != 50 {
		t.Errorf("linked save %q/%d, wanted B50/50", blob, at)
	}

	// An anon write AFTER the link never arrives — but the anon keeps living.
	if rec := authedSave(e, http.MethodPost, anon, "", `{"blob":"B60","saved_at":60}`); rec.Code != http.StatusOK {
		t.Fatalf("late anon POST status %d", rec.Code)
	}
	if rec := authedBest(e, http.MethodGet, anon, sess, ""); rec.Code != http.StatusOK {
		t.Fatalf("second authed anon GET status %d", rec.Code)
	}
	if blob, at := subSave(t, e, sub, sess); blob != "B50" || at != 50 {
		t.Errorf("sub save after late anon write %q/%d, wanted B50/50", blob, at)
	}
	if br := subBest(t, e, sub, sess); br.Distance != 100 {
		t.Errorf("sub distance after late anon write %d, wanted 100", br.Distance)
	}
	if rec := authedBest(e, http.MethodGet, anon, "", ""); rec.Code != http.StatusOK {
		t.Fatalf("anon GET status %d", rec.Code)
	} else if br := decodeAuthBest(t, rec); br.Distance != 100 {
		t.Errorf("anon distance %d, wanted its own 100", br.Distance)
	}
}

// TestAuthLinkNeverRelinks: an alias belongs to its first sub forever — a
// second session naming the same anon id gets its own record, not the anon's.
func TestAuthLinkNeverRelinks(t *testing.T) {
	t.Setenv("SMTP_HOST", "mail.example")
	e := newAuthEnv()
	const anon = "dddddddddddddddddddddddddddddddd"
	sub1 := subForEmail("first@example.com")
	if rec := authedBest(e, http.MethodPost, anon, "", `{"distance":100}`); rec.Code != http.StatusOK {
		t.Fatalf("seed anon status %d", rec.Code)
	}
	sess1 := verifyToken(t, e, "first@example.com", "203.0.113.7")
	if rec := authedBest(e, http.MethodGet, anon, sess1, ""); rec.Code != http.StatusOK {
		t.Fatalf("link GET status %d", rec.Code)
	}

	sess2 := insertSession(e, subForEmail("second@example.com"), time.Now().Add(sessionTTL).Unix())
	if rec := authedBest(e, http.MethodGet, anon, sess2, ""); rec.Code != http.StatusOK {
		t.Fatalf("second session GET status %d", rec.Code)
	} else if br := decodeAuthBest(t, rec); br.Distance != 0 {
		t.Errorf("second session reads distance %d through the alias, wanted its own 0", br.Distance)
	}
	e.auth.mu.Lock()
	got := e.auth.aliases[anon]
	e.auth.mu.Unlock()
	if got != sub1 {
		t.Errorf("alias points at %q, wanted the first sub", got)
	}
	if br := subBest(t, e, subForEmail("second@example.com"), sess2); br.Distance != 0 {
		t.Errorf("second sub holds distance %d of the anon, wanted 0", br.Distance)
	}
}

// TestAuthLinkSaveLWWKeepsNewerSub: when sub's own save is newer than the
// anon's, the link keeps sub's — last write wins, not first link wins.
func TestAuthLinkSaveLWWKeepsNewerSub(t *testing.T) {
	t.Setenv("SMTP_HOST", "mail.example")
	e := newAuthEnv()
	const email = "lww@example.com"
	sub := subForEmail(email)
	const anon = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
	if rec := authedSave(e, http.MethodPost, anon, "", `{"blob":"OLD","saved_at":50}`); rec.Code != http.StatusOK {
		t.Fatalf("seed anon save status %d", rec.Code)
	}
	if rec := authedSave(e, http.MethodPost, sub, "", `{"blob":"NEW","saved_at":80}`); rec.Code != http.StatusOK {
		t.Fatalf("seed sub save status %d", rec.Code)
	}
	sess := verifyToken(t, e, email, "203.0.113.7")
	if rec := authedBest(e, http.MethodGet, anon, sess, ""); rec.Code != http.StatusOK {
		t.Fatalf("link GET status %d", rec.Code)
	}
	if blob, at := subSave(t, e, sub, sess); blob != "NEW" || at != 80 {
		t.Errorf("linked save %q/%d, wanted NEW/80", blob, at)
	}
}

// TestAuthUnknownSessionIs401: a well-formed stranger and garbage both 401
// with the refusal's own words — while no header at all stays anonymous.
func TestAuthUnknownSessionIs401(t *testing.T) {
	e := newAuthEnv()
	restore := allowedOrigins
	t.Cleanup(func() { allowedOrigins = restore })
	allowedOrigins = []string{"example.com"}

	bad := httptest.NewRequest(http.MethodGet, "/best?id=ffffffffffffffffffffffffffffffff", nil)
	bad.Header.Set("Origin", "https://example.com")
	bad.Header.Set("X-Session", strings.Repeat("ab", 32))
	rec := httptest.NewRecorder()
	e.auth.withSession(e.best.handler)(rec, bad)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("unknown session status %d, wanted 401", rec.Code)
	}
	if got := decodeAuthError(t, rec); got != "Your sign-in has expired — send a new link" {
		t.Errorf("unknown session error %q", got)
	}
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "https://example.com" {
		t.Errorf("401 without the CORS origin header — the browser would hide the body")
	}

	garbage := httptest.NewRequest(http.MethodGet, "/best?id=ffffffffffffffffffffffffffffffff", nil)
	garbage.Header.Set("X-Session", "zzz")
	rec = httptest.NewRecorder()
	e.auth.withSession(e.best.handler)(rec, garbage)
	if rec.Code != http.StatusUnauthorized {
		t.Errorf("malformed session status %d, wanted 401", rec.Code)
	}

	if rec := authedBest(e, http.MethodGet, "ffffffffffffffffffffffffffffffff", "", ""); rec.Code != http.StatusOK {
		t.Errorf("no header status %d, wanted anonymous 200", rec.Code)
	}
}

// TestAuthSignOut: DELETE drops the session (204), the token 401s after, and
// deleting twice is still 204.
func TestAuthSignOut(t *testing.T) {
	t.Setenv("SMTP_HOST", "mail.example")
	e := newAuthEnv()
	sess := verifyToken(t, e, "player@example.com", "203.0.113.7")

	bye := func() *httptest.ResponseRecorder {
		r := httptest.NewRequest(http.MethodDelete, "/auth/session", nil)
		r.Header.Set("X-Session", sess)
		rec := httptest.NewRecorder()
		e.auth.sessionHandler(rec, r)
		return rec
	}
	if rec := bye(); rec.Code != http.StatusNoContent {
		t.Fatalf("sign-out status %d, wanted 204", rec.Code)
	}
	if rec := authedBest(e, http.MethodGet, "ffffffffffffffffffffffffffffffff", sess, ""); rec.Code != http.StatusUnauthorized {
		t.Errorf("signed-out token status %d, wanted 401", rec.Code)
	}
	if rec := bye(); rec.Code != http.StatusNoContent {
		t.Errorf("second sign-out status %d, wanted 204", rec.Code)
	}
}

// TestAuthPreflightAllowsSessionHeader: the browser's preflight for an
// X-Session /best or /save is answered with both headers named, and the two
// auth routes answer their own preflights.
func TestAuthPreflightAllowsSessionHeader(t *testing.T) {
	e := newAuthEnv()
	restore := allowedOrigins
	t.Cleanup(func() { allowedOrigins = restore })
	allowedOrigins = []string{"korjavin.github.io"}

	preflight := func(path string, h http.HandlerFunc) *httptest.ResponseRecorder {
		req := httptest.NewRequest(http.MethodOptions, path, nil)
		req.Header.Set("Origin", "https://korjavin.github.io")
		req.Header.Set("Access-Control-Request-Method", "POST")
		req.Header.Set("Access-Control-Request-Headers", "content-type, x-session")
		rec := httptest.NewRecorder()
		h(rec, req)
		return rec
	}
	for _, path := range []string{"/best?id=whatever", "/save?id=whatever"} {
		h := e.auth.withSession(e.best.handler)
		if strings.HasPrefix(path, "/save") {
			h = e.auth.withSession(e.save.handler)
		}
		rec := preflight(path, h)
		if rec.Code != http.StatusNoContent {
			t.Errorf("OPTIONS %s status %d, wanted 204", path, rec.Code)
			continue
		}
		got := rec.Header().Get("Access-Control-Allow-Headers")
		if !strings.Contains(got, "X-Session") || !strings.Contains(got, "Content-Type") {
			t.Errorf("OPTIONS %s allow-headers %q, wanted X-Session and Content-Type", path, got)
		}
	}

	if rec := preflight("/auth/magic", e.auth.magicHandler); rec.Code != http.StatusNoContent {
		t.Errorf("OPTIONS /auth/magic status %d, wanted 204", rec.Code)
	} else if got := rec.Header().Get("Access-Control-Allow-Headers"); !strings.Contains(got, "Content-Type") {
		t.Errorf("OPTIONS /auth/magic allow-headers %q", got)
	}
	if rec := preflight("/auth/session", e.auth.sessionHandler); rec.Code != http.StatusNoContent {
		t.Errorf("OPTIONS /auth/session status %d, wanted 204", rec.Code)
	} else if got := rec.Header().Get("Access-Control-Allow-Methods"); !strings.Contains(got, "DELETE") {
		t.Errorf("OPTIONS /auth/session allow-methods %q", got)
	}
}

// TestAuthFileSurvivesRestart: sessions and aliases ride the dump; junk keys
// (bad hash, bad sub, zero exp, bad alias sides) are dropped on load — and
// the file refuses nothing it wrote.
func TestAuthFileSurvivesRestart(t *testing.T) {
	t.Setenv("SMTP_HOST", "mail.example")
	e := newAuthEnv()
	e.auth.path = filepath.Join(t.TempDir(), "auth.json")
	const email = "link@example.com"
	sub := subForEmail(email)
	const anon = "ffffffffffffffffffffffffffffff01"
	sess := verifyToken(t, e, email, "203.0.113.7")
	if rec := authedBest(e, http.MethodGet, anon, sess, ""); rec.Code != http.StatusOK {
		t.Fatalf("link GET status %d", rec.Code)
	}
	if err := e.auth.dump(); err != nil {
		t.Fatalf("dump: %v", err)
	}

	b2 := newBestStore("")
	s2 := newSaveStore("")
	r2 := newAuthStore(e.auth.path, b2, s2)
	// The file refuses nothing it wrote: the session authenticates and the
	// alias survived.
	if rec := authedBest(&authEnv{best: b2, save: s2, auth: r2}, http.MethodGet, "ffffffffffffffffffffffffffffff02", sess, ""); rec.Code != http.StatusOK {
		t.Fatalf("reloaded session GET status %d, wanted 200", rec.Code)
	}
	r2.mu.Lock()
	got := r2.aliases[anon]
	n := len(r2.sessions)
	r2.mu.Unlock()
	if got != sub {
		t.Errorf("reloaded alias = %q, wanted the sub", got)
	}
	if n != 1 {
		t.Errorf("reloaded sessions = %d, wanted 1", n)
	}

	// Junk in, junk out — dropped, never fatal.
	junk := `{"sessions":{
		"zz":{"sub":"` + sub + `","exp":9999999999},
		"` + strings.Repeat("cd", 32) + `":{"sub":"not an id!","exp":9999999999},
		"` + strings.Repeat("ef", 32) + `":{"sub":"` + sub + `","exp":0},
		"` + strings.Repeat("ab", 32) + `":{"sub":"` + sub + `","exp":9999999999}},
		"aliases":{"bad id!":"` + sub + `","` + anon + `":"bad sub!","0123456789abcdef0123456789abcdef":"` + sub + `"}}`
	path := filepath.Join(t.TempDir(), "junk.json")
	if err := os.WriteFile(path, []byte(junk), 0o644); err != nil {
		t.Fatalf("fixture: %v", err)
	}
	j := newAuthStore(path, newBestStore(""), newSaveStore(""))
	j.mu.Lock()
	defer j.mu.Unlock()
	if len(j.sessions) != 1 {
		t.Errorf("junk load kept %d sessions, wanted the one good one", len(j.sessions))
	}
	if len(j.aliases) != 1 || j.aliases["0123456789abcdef0123456789abcdef"] != sub {
		t.Errorf("junk load aliases = %v", j.aliases)
	}
}

// TestAuthFailedDumpStaysDirty: the blocker-file fixture from the sibling
// stores — a failed dump leaves dirty set, so the next tick tries again.
func TestAuthFailedDumpStaysDirty(t *testing.T) {
	blocker := filepath.Join(t.TempDir(), "blocker")
	if err := os.WriteFile(blocker, []byte("x"), 0o644); err != nil {
		t.Fatalf("setup: %v", err)
	}
	e := newAuthEnv()
	e.auth.path = filepath.Join(blocker, "sub", "auth.json")
	e.auth.mu.Lock()
	e.auth.sessions[strings.Repeat("ab", 32)] = authSession{Sub: subForEmail("a@b.c"), Exp: time.Now().Add(time.Hour).Unix()}
	e.auth.dirty = true
	e.auth.mu.Unlock()

	if err := e.auth.dump(); err == nil {
		t.Fatalf("dump into %s unexpectedly succeeded", e.auth.path)
	}
	e.auth.mu.Lock()
	dirty := e.auth.dirty
	e.auth.mu.Unlock()
	if !dirty {
		t.Fatalf("a failed dump left the store clean — every later tick is a no-op")
	}
}

// TestAuthIsNotOnHealthz: the compile-level guard extends to the auth store —
// healthzHandler takes the hub and nothing else, and with the auth dump
// failing every time /healthz still answers 200 ok:true.
func TestAuthIsNotOnHealthz(t *testing.T) {
	hub := NewHub()
	blocker := filepath.Join(t.TempDir(), "blocker")
	if err := os.WriteFile(blocker, []byte("x"), 0o644); err != nil {
		t.Fatalf("setup: %v", err)
	}
	e := newAuthEnv()
	e.auth.path = filepath.Join(blocker, "sub", "auth.json")
	e.auth.mu.Lock()
	e.auth.sessions[strings.Repeat("cd", 32)] = authSession{Sub: subForEmail("a@b.c"), Exp: time.Now().Add(time.Hour).Unix()}
	e.auth.dirty = true
	e.auth.mu.Unlock()
	if err := e.auth.dump(); err == nil {
		t.Fatalf("dump unexpectedly succeeded — the premise is gone")
	}

	rec := httptest.NewRecorder()
	healthzHandler(hub)(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("/healthz answered %d while the auth dump was failing", rec.Code)
	}
	var body struct {
		OK bool `json:"ok"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil || !body.OK {
		t.Fatalf("/healthz body %q while the auth dump was failing", rec.Body.String())
	}
}

// TestAuthSweeperDropsExpired: expired pending, expired sessions and elapsed
// windows go; the living stay — and only a dropped session dirties the file.
func TestAuthSweeperDropsExpired(t *testing.T) {
	e := newAuthEnv()
	base := time.Now()
	// Explicit lock pairs throughout: sweepOnce takes the lock itself, so no
	// lock is ever held across one (a deferred Unlock across a sweep
	// self-deadlocks).
	e.auth.mu.Lock()
	e.auth.pending["deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"] = authPending{Sub: "s", Exp: base.Add(-time.Minute).Unix()}
	e.auth.pending["feedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeedfeed"] = authPending{Sub: "s", Exp: base.Add(time.Minute).Unix()}
	e.auth.sessions[strings.Repeat("ab", 32)] = authSession{Sub: "s", Exp: base.Add(-time.Minute).Unix()}
	e.auth.sessions[strings.Repeat("cd", 32)] = authSession{Sub: "s", Exp: base.Add(2 * time.Hour).Unix()}
	e.auth.limits["ip:old"] = authWindow{n: 9, until: base.Add(-time.Minute)}
	e.auth.limits["ip:new"] = authWindow{n: 1, until: base.Add(time.Minute)}
	e.auth.dirty = false
	e.auth.mu.Unlock()

	e.auth.sweepOnce(base)

	e.auth.mu.Lock()
	np, ns, nl, dirty := len(e.auth.pending), len(e.auth.sessions), len(e.auth.limits), e.auth.dirty
	e.auth.mu.Unlock()
	if np != 1 {
		t.Errorf("sweep kept %d pending, wanted the live one", np)
	}
	if ns != 1 {
		t.Errorf("sweep kept %d sessions, wanted the live one", ns)
	}
	if nl != 1 {
		t.Errorf("sweep kept %d windows, wanted the live one", nl)
	}
	if !dirty {
		t.Errorf("a dropped session left the store clean — the file keeps the corpse")
	}

	// Pending alone never dirties: the file holds no pending.
	e.auth.mu.Lock()
	e.auth.pending["cafecafecafecafecafecafecafecafecafecafecafecafecafecafecafecafe"] = authPending{Sub: "s", Exp: base.Add(-time.Minute).Unix()}
	e.auth.dirty = false
	e.auth.mu.Unlock()
	e.auth.sweepOnce(base.Add(time.Hour))
	e.auth.mu.Lock()
	np, dirty = len(e.auth.pending), e.auth.dirty
	e.auth.mu.Unlock()
	if np != 0 {
		t.Errorf("second sweep kept %d pending", np)
	}
	if dirty {
		t.Errorf("dropped pending dirtied the file it is not in")
	}
}

// TestAuthCapsHold: pending past a thousand refuses magic with 429, and a
// verify past ten thousand sessions evicts the earliest — never grows.
func TestAuthCapsHold(t *testing.T) {
	t.Setenv("SMTP_HOST", "mail.example")
	e := newAuthEnv()
	e.auth.send = func(to, link string) error { return nil }
	e.auth.mu.Lock()
	for i := 0; i < maxAuthPending; i++ {
		e.auth.pending[fmt.Sprintf("%064x", i)] = authPending{Sub: "s", Exp: time.Now().Add(time.Hour).Unix()}
	}
	e.auth.mu.Unlock()
	if rec := postMagic(e, "player@example.com", "203.0.113.7"); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("magic past the pending cap status %d, wanted 429", rec.Code)
	}

	e.auth.mu.Lock()
	e.auth.pending = map[string]authPending{}
	base := time.Now().Unix()
	// Fill sessions with staggered expiries through the real shape.

	for i := 0; i < maxAuthSessions; i++ {
		e.auth.sessions[fmt.Sprintf("%064x", i)] = authSession{Sub: subForEmail("a@b.c"), Exp: base + int64(i)}
	}
	earliest := fmt.Sprintf("%064x", 0)
	e.auth.pending[tokenKey(strings.Repeat("ff", 32))] = authPending{Sub: subForEmail("a@b.c"), Exp: base + 3600}
	e.auth.mu.Unlock()
	rec := httptest.NewRecorder()
	e.auth.verifyHandler(rec, httptest.NewRequest(http.MethodGet, "/auth/verify?t="+strings.Repeat("ff", 32), nil))
	if rec.Code != http.StatusFound {
		t.Fatalf("verify at the session cap status %d, wanted 302", rec.Code)
	}
	e.auth.mu.Lock()
	defer e.auth.mu.Unlock()
	if len(e.auth.sessions) != maxAuthSessions {
		t.Errorf("sessions = %d past the cap, wanted exactly %d", len(e.auth.sessions), maxAuthSessions)
	}
	if _, ok := e.auth.sessions[earliest]; ok {
		t.Errorf("the earliest session survived a verify past the cap")
	}
}

// TestAuthMiddlewareConcurrent hammers the link the way best_test hammers the
// merge: one anon id, one session, readers and writers interleaved — every
// request 200, the alias recorded once, the sub holding the anon's max.
func TestAuthMiddlewareConcurrent(t *testing.T) {
	t.Setenv("SMTP_HOST", "mail.example")
	e := newAuthEnv()
	const anon = "99999999999999999999999999999999"
	sess := insertSession(e, subForEmail("race@example.com"), time.Now().Add(sessionTTL).Unix())

	const writers = 8
	const rounds = 25
	var wg sync.WaitGroup
	for g := 0; g < writers; g++ {
		wg.Add(1)
		go func(g int) {
			defer wg.Done()
			for r := 0; r < rounds; r++ {
				body, err := json.Marshal(map[string]any{"distance": r})
				if err != nil {
					t.Errorf("fixture: %v", err)
					return
				}
				if w := authedBest(e, http.MethodPost, anon, sess, string(body)); w.Code != http.StatusOK {
					t.Errorf("concurrent POST status %d, wanted 200", w.Code)
					return
				}
				if w := authedBest(e, http.MethodGet, anon, sess, ""); w.Code != http.StatusOK {
					t.Errorf("concurrent GET status %d, wanted 200", w.Code)
					return
				}
				if w := authedSave(e, http.MethodGet, anon, sess, ""); w.Code != http.StatusOK {
					t.Errorf("concurrent save GET status %d, wanted 200", w.Code)
					return
				}
			}
		}(g)
	}
	wg.Wait()

	if rec := authedBest(e, http.MethodGet, anon, sess, ""); rec.Code != http.StatusOK {
		t.Fatalf("final GET status %d", rec.Code)
	} else if br := decodeAuthBest(t, rec); br.Distance != rounds-1 {
		t.Errorf("final distance %d, wanted %d", br.Distance, rounds-1)
	}
	e.auth.mu.Lock()
	got := e.auth.aliases[anon]
	e.auth.mu.Unlock()
	if got != subForEmail("race@example.com") {
		t.Errorf("alias = %q past the hammering", got)
	}
}
