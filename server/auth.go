package main

// auth.go — magic-link email sign-in, the SECOND persistence exception on the
// lobby after best.go (owner order 2026-09-20, magic-link pick over the
// earlier Telegram draft).
//
// The flow (parent bead godot-test1-i8yu.7, re-spec, binding): POST
// /auth/magic mails a one-shot link, GET /auth/verify?t= deletes it and 302s
// to AUTH_GAME_URL#session=<session>, and every /best and /save request may
// carry X-Session. The first authed request naming an anon ?id= links it to
// the session's sub once (/best merged monotone, /save by LWW); anonymous
// requests never follow aliases.
//
// WHY THE ADDRESS IS NEVER STORED: delivery needs it for one send and
// identity needs one stable key. hex(sha256(lower(trim(address)))) is the key
// (sub), and it is irreversible for the purpose — the pending and session
// maps, the dump file and the logs hold hashes, never addresses.
//
// WHY TOKENS ARE KEYED BY THEIR SHA256: a leaked auth.json must hold nothing
// usable, and a digest lookup needs no comparison at all — the presented
// token's shape is validated first (^[0-9a-f]{64}$), then hashed, then looked
// up. There is no stored token to compare against, constant-time or
// otherwise.
//
// WHY PENDING TOKENS ARE MEMORY-ONLY: a 15-minute single-use token that must
// survive a redeploy is a database with a janitor; a redeploy mid-flow costs
// one re-send instead, and the dump file stays to sessions + aliases only.
//
// THE LOBBY STILL NEVER INSPECTS A GAME PAYLOAD: the middleware reads one
// header (X-Session) and rewrites one query param (?id=) before the inner
// handlers run. Records and blobs keep their own shapes and merges.
//
// SHAPE CHOICE: this store, its load/dump/dumper/sweeper and its caps are a
// copy of save.go's, adapted — a generic store would abstract over a monotone
// merge, a last-write-wins put AND a token table to save one small file's
// worth of obvious code. The copy is the smaller diff and each file stays
// readable alone.

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/mail"
	"net/smtp"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"
)

const (
	// magicTTL is a pending link's life: single use, fifteen minutes. A
	// redeploy inside it costs the player one re-send (pending is memory-only).
	magicTTL = 15 * time.Minute
	// sessionTTL is fixed at thirty days with no sliding renewal: at the end
	// the next request 401s, the client signs out and says why, and the
	// player sends a new link.
	sessionTTL = 30 * 24 * time.Hour
	// authDumpInterval matches the sibling stores: no graceful shutdown (see
	// main), so a SIGTERM can lose up to this much of sessions and aliases.
	authDumpInterval = 30 * time.Second
	// sweepInterval drops expired pending, expired sessions and elapsed rate
	// windows. A minute late is invisible at these lifetimes.
	sweepInterval = 1 * time.Minute
	// maxAuthBody bounds POST /auth/magic: an address plus JSON envelope can
	// never honestly reach a kilobyte. Over the cap is a 400, never a
	// truncation.
	maxAuthBody = 1024
	// maxEmailLen is the whole address rule's length bound (RFC 5321's 254).
	maxEmailLen = 254
	// maxAuthSessions bounds the session map; at the cap a new verify evicts
	// the earliest-expiring session. maxAuthAliases bounds the alias map; a
	// link beyond the cap is refused SILENTLY — the request still runs under
	// sub, it just records no alias. maxAuthPending bounds the pending map; a
	// magic request beyond it answers 429.
	maxAuthSessions = 10000
	maxAuthAliases  = 10000
	maxAuthPending  = 1000
	// magicPerIP: 10 links per 10 minutes per client ip.
	// magicPerEmail: 3 links per 15 minutes per email hash.
	magicPerIP          = 10
	magicPerIPWindow    = 10 * time.Minute
	magicPerEmail       = 3
	magicPerEmailWindow = 15 * time.Minute
)

// tokenRe validates a PRESENTED token by shape before it is ever hashed: 32
// random bytes as 64 lowercase hex. Nothing else is looked up.
var tokenRe = regexp.MustCompile(`^[0-9a-f]{64}$`)

// authSession is one live login: whose (sub), until when (unix seconds).
type authSession struct {
	Sub string `json:"sub"`
	Exp int64  `json:"exp"`
}

// authPending is one mailed link not yet opened: whose, until when. Memory
// only — the dump file never sees these.
type authPending struct {
	Sub string
	Exp int64
}

// authWindow is one fixed rate-limit window: hits so far, until when. Memory
// only.
type authWindow struct {
	n     int
	until time.Time
}

type authStore struct {
	mu       sync.Mutex
	sessions map[string]authSession // key = hex(sha256(session token)); DUMPED
	aliases  map[string]string      // anon player id -> sub; DUMPED
	pending  map[string]authPending // key = hex(sha256(magic token)); memory only
	limits   map[string]authWindow  // "ip:<ip>" / "em:<subhash>"; memory only
	path     string                 // "" = memory only (tests, no volume)
	dirty    bool
	best     *bestStore
	save     *saveStore
	send     func(to, link string) error // the mailer; tests replace it
	now      func() time.Time            // the clock; tests advance it
}

func newAuthStore(path string, best *bestStore, save *saveStore) *authStore {
	a := &authStore{
		sessions: map[string]authSession{},
		aliases:  map[string]string{},
		pending:  map[string]authPending{},
		limits:   map[string]authWindow{},
		path:     path,
		best:     best,
		save:     save,
		send:     sendMagicMail,
		now:      time.Now,
	}
	// Local end-to-end only, never production: log the link instead of
	// mailing it (and skip the unconfigured-relay refusal below).
	if env("AUTH_DEV_LOG_LINK", "") == "1" {
		a.send = func(to, link string) error {
			log.Printf("lobby: auth: dev link for %s: %s", to, link)
			return nil
		}
	}
	if path != "" {
		if err := a.load(); err != nil {
			// A missing file is the first-run path, not an error.
			if !errors.Is(err, os.ErrNotExist) {
				log.Printf("lobby: auth: could not load %s: %v (starting empty)", path, err)
			}
		}
	}
	return a
}

// normalizeEmail is the whole canonicalisation: trim, lowercase. Everything
// downstream — validation, sub, the email rate window — takes this form.
func normalizeEmail(s string) string {
	return strings.ToLower(strings.TrimSpace(s))
}

// subForEmail is the identity key: hex(sha256(normalized address)). 64 chars,
// inside playerIDRe, so /best and /save need no schema change — a signed-in
// player's records live under sub in the same maps.
func subForEmail(email string) string {
	sum := sha256.Sum256([]byte(normalizeEmail(email)))
	return hex.EncodeToString(sum[:])
}

// validEmail is the whole address rule: after trim+lowercase, exactly one @
// with non-empty sides, no whitespace/CR/LF anywhere (the header-injection
// guard), length within bound. The mail bouncing is the rest of the
// validation.
func validEmail(email string) bool {
	e := normalizeEmail(email)
	if len(e) == 0 || len(e) > maxEmailLen {
		return false
	}
	if strings.ContainsAny(e, " \t\r\n") {
		return false
	}
	parts := strings.Split(e, "@")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return false
	}
	return true
}

// mintToken makes one 32-byte random token as 64 hex characters.
func mintToken() (string, error) {
	var b [32]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", err
	}
	return hex.EncodeToString(b[:]), nil
}

// tokenKey is the only form a token takes in memory: hex(sha256(token)).
func tokenKey(tok string) string {
	sum := sha256.Sum256([]byte(tok))
	return hex.EncodeToString(sum[:])
}

// clientIP is the rate-limit identity: X-Real-Ip when Traefik set it (the
// container is only reachable through the traefik network, so it is not
// spoofable from outside — hence the comment, not a check), else the
// connection's host.
func clientIP(r *http.Request) string {
	if ip := strings.TrimSpace(r.Header.Get("X-Real-Ip")); ip != "" {
		return ip
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// writeAuthError answers a JSON refusal with no-store, the shape every /auth
// error takes (the client shows `error` verbatim — every refusal says why).
func writeAuthError(w http.ResponseWriter, r *http.Request, code int, text string) {
	if o := corsOrigin(r.Header.Get("Origin")); o != "" {
		w.Header().Set("Access-Control-Allow-Origin", o)
		w.Header().Set("Vary", "Origin")
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(code)
	_, _ = w.Write(mustJSON(map[string]any{"error": text}))
}

// authCORS opens the shared CORS block: the allow-origin pair every handler
// here repeats.
func authCORS(w http.ResponseWriter, r *http.Request) {
	if o := corsOrigin(r.Header.Get("Origin")); o != "" {
		w.Header().Set("Access-Control-Allow-Origin", o)
		w.Header().Set("Vary", "Origin")
	}
}

// magicLinkBase builds the link the mail carries: <scheme>://r.Host +
// /auth/verify?t=<token>. The scheme prefers X-Forwarded-Proto (behind
// Traefik it is https); r.Host is LOBBY_HOST there, because Traefik matches
// the Host rule before the path rule ever runs.
func magicLinkBase(r *http.Request) string {
	scheme := "http"
	if p := r.Header.Get("X-Forwarded-Proto"); p != "" {
		scheme = strings.ToLower(strings.TrimSpace(strings.Split(p, ",")[0]))
		if scheme == "" {
			scheme = "http"
		}
	}
	return scheme + "://" + r.Host
}

// rateMinutesLeft is the 429's N: the window's remainder, rounded UP to whole
// minutes, at least one.
func rateMinutesLeft(now time.Time, until time.Time) int {
	m := int((until.Sub(now) + 59*time.Second) / time.Minute)
	if m < 1 {
		m = 1
	}
	return m
}

// magicHandler answers POST /auth/magic: validate, rate-limit, mint a pending
// token, 200 {"ok":1} and mail the link from a goroutine. Every refusal is
// JSON with no-store and says why; the send failing later is a log line,
// never a second response (the handler already answered).
func (a *authStore) magicHandler(w http.ResponseWriter, r *http.Request) {
	authCORS(w, r)
	if r.Method == http.MethodOptions {
		w.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		w.Header().Set("Access-Control-Max-Age", "86400")
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", "POST, OPTIONS")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var body struct {
		Email string `json:"email"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxAuthBody)).Decode(&body); err != nil {
		writeAuthError(w, r, http.StatusBadRequest, "bad body")
		return
	}
	if !validEmail(body.Email) {
		writeAuthError(w, r, http.StatusBadRequest, "That does not look like an email address")
		return
	}
	sub := subForEmail(body.Email)
	to := strings.TrimSpace(body.Email)

	// No relay configured and not the local dev flag: refuse, plainly.
	if env("SMTP_HOST", "") == "" && env("AUTH_DEV_LOG_LINK", "") != "1" {
		writeAuthError(w, r, http.StatusServiceUnavailable, "Sign-in is not set up on this lobby")
		return
	}

	// Fixed windows, checked email-first so its text wins when both trip, and
	// bumped only on a well-formed address.
	now := a.now()
	a.mu.Lock()
	emKey, ipKey := "em:"+sub, "ip:"+clientIP(r)
	em, emOK := a.limits[emKey]
	emLive := emOK && now.Before(em.until)
	ip, ipOK := a.limits[ipKey]
	ipLive := ipOK && now.Before(ip.until)
	bump := func(key string, window time.Duration) {
		win, ok := a.limits[key]
		if !ok || !now.Before(win.until) {
			win = authWindow{n: 0, until: now.Add(window)}
		}
		win.n++
		a.limits[key] = win
	}
	if emLive && em.n >= magicPerEmail {
		a.mu.Unlock()
		n := rateMinutesLeft(now, em.until)
		writeAuthError(w, r, http.StatusTooManyRequests,
			fmt.Sprintf("Too many sign-in links — try again in %d minutes", n))
		return
	}
	if ipLive && ip.n >= magicPerIP {
		bump(emKey, magicPerEmailWindow)
		a.mu.Unlock()
		n := rateMinutesLeft(now, ip.until)
		writeAuthError(w, r, http.StatusTooManyRequests,
			fmt.Sprintf("Too many sign-in links — try again in %d minutes", n))
		return
	}
	bump(emKey, magicPerEmailWindow)
	bump(ipKey, magicPerIPWindow)
	if len(a.pending) >= maxAuthPending {
		a.mu.Unlock()
		writeAuthError(w, r, http.StatusTooManyRequests, "The lobby is busy — try again in a minute")
		return
	}
	tok, err := mintToken()
	if err != nil {
		a.mu.Unlock()
		writeAuthError(w, r, http.StatusInternalServerError, "Could not send a sign-in link")
		return
	}
	a.pending[tokenKey(tok)] = authPending{Sub: sub, Exp: now.Add(magicTTL).Unix()}
	a.mu.Unlock()

	link := magicLinkBase(r) + "/auth/verify?t=" + tok
	// Bound per request: the goroutine below must not read the store's send
	// field, which tests (and only tests) replace between requests.
	send := a.send
	go func() {
		// The handler already answered 200 below: a send failure is a log
		// line, addressed by its sub hash — never the address.
		if err := send(to, link); err != nil {
			log.Printf("lobby: auth: mail to %s failed: %v", sub[:8], err)
		}
	}()

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	_, _ = w.Write(mustJSON(map[string]any{"ok": 1}))
}

// expiredPage is the dead link: unknown, malformed, used or expired token.
// Never a 4xx — a GET, a paste, a prefetch and a double-open all land here,
// and 200 keeps every one of them on the same human page.
func expiredPage(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	_, _ = w.Write([]byte("This sign-in link has expired or was already used. Go back to the game and send a new one."))
}

// gameURL is where a verified session lands: AUTH_GAME_URL (the game build's
// URL on its own host) plus the #session=<session> fragment.
func gameURL() string {
	return env("AUTH_GAME_URL", "/")
}

// verifyHandler answers GET /auth/verify?t=: shape-check the token, consume
// the pending entry ATOMICALLY under the lock (the double-open race resolves
// here — first opener wins, second finds nothing), mint a session, 302 to the
// game URL with the session in the fragment. Sessions over the cap evict the
// earliest-expiring one.
func (a *authStore) verifyHandler(w http.ResponseWriter, r *http.Request) {
	tok := strings.TrimSpace(r.URL.Query().Get("t"))
	if !tokenRe.MatchString(tok) {
		expiredPage(w)
		return
	}
	now := a.now()
	a.mu.Lock()
	p, ok := a.pending[tokenKey(tok)]
	if !ok || !now.Before(time.Unix(p.Exp, 0)) {
		a.mu.Unlock()
		expiredPage(w)
		return
	}
	delete(a.pending, tokenKey(tok))
	sess, err := mintToken()
	if err != nil {
		a.mu.Unlock()
		writeAuthError(w, r, http.StatusInternalServerError, "Could not sign in")
		return
	}
	key := tokenKey(sess)
	a.sessions[key] = authSession{Sub: p.Sub, Exp: now.Add(sessionTTL).Unix()}
	if len(a.sessions) > maxAuthSessions {
		a.evictEarliestSessionLocked()
	}
	a.dirty = true
	a.mu.Unlock()

	w.Header().Set("Location", gameURL()+"#session="+sess)
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(http.StatusFound)
}

// evictEarliestSessionLocked drops the earliest-expiring session. Call with
// the lock held; paid only on an insert past the cap.
func (a *authStore) evictEarliestSessionLocked() {
	var victim string
	var victimExp int64
	for k, s := range a.sessions {
		if victim == "" || s.Exp < victimExp {
			victim, victimExp = k, s.Exp
		}
	}
	if victim != "" {
		delete(a.sessions, victim)
	}
}

// sessionHandler answers DELETE /auth/session: delete the named session if it
// exists, 204 always — idempotent, unauthenticated by design, like the rest
// of the lobby.
func (a *authStore) sessionHandler(w http.ResponseWriter, r *http.Request) {
	authCORS(w, r)
	if r.Method == http.MethodOptions {
		w.Header().Set("Access-Control-Allow-Methods", "DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		w.Header().Set("Access-Control-Max-Age", "86400")
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if r.Method != http.MethodDelete {
		w.Header().Set("Allow", "DELETE, OPTIONS")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if tok := r.Header.Get("X-Session"); tokenRe.MatchString(tok) {
		a.mu.Lock()
		if _, ok := a.sessions[tokenKey(tok)]; ok {
			delete(a.sessions, tokenKey(tok))
			a.dirty = true
		}
		a.mu.Unlock()
	}
	w.WriteHeader(http.StatusNoContent)
}

// withSession wraps /best and /save. OPTIONS and sessionless requests pass
// through untouched; a malformed, unknown or expired session answers 401 with
// the CORS origin header set (or the browser hides the body). Otherwise the
// ?id= rewrites to the session's sub — AFTER the one-time link below — and
// the inner handlers run exactly as they do for anonymous requests.
//
// THE LINK, guarded once so garbage can never re-point a record: on the
// FIRST authed request whose ?id= is well-formed and different from sub, the
// anon's numbers merge into sub's (/best monotone, /save last-write-wins by
// stamp), then the alias is recorded under the auth lock — re-checked there,
// because two first-links can race and only the first may record. Later
// requests skip the merge entirely, so an anon record written after the link
// never arrives (it still has its own life under its own id). An alias that
// already points elsewhere is never re-pointed. Past the alias cap the link
// is refused SILENTLY: the request still runs under sub.
//
// Lock order, stated because the race test leans on it: the auth lock is
// taken for the alias check/record ONLY. The stores' merges take their own
// locks while the auth lock is released — never nested either way.
func (a *authStore) withSession(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodOptions {
			next(w, r)
			return
		}
		tok := r.Header.Get("X-Session")
		if tok == "" {
			next(w, r)
			return
		}
		if !tokenRe.MatchString(tok) {
			writeAuthError(w, r, http.StatusUnauthorized, "Your sign-in has expired — send a new link")
			return
		}
		now := a.now()
		a.mu.Lock()
		sess, ok := a.sessions[tokenKey(tok)]
		if !ok || !now.Before(time.Unix(sess.Exp, 0)) {
			if ok {
				delete(a.sessions, tokenKey(tok))
				a.dirty = true
			}
			a.mu.Unlock()
			writeAuthError(w, r, http.StatusUnauthorized, "Your sign-in has expired — send a new link")
			return
		}
		sub := sess.Sub
		a.mu.Unlock()

		if anon := strings.TrimSpace(r.URL.Query().Get("id")); playerIDRe.MatchString(anon) && anon != sub {
			a.mu.Lock()
			_, linked := a.aliases[anon]
			a.mu.Unlock()
			if !linked {
				linkAuthAlias(a, anon, sub)
			}
		}

		q := r.URL.Query()
		q.Set("id", sub)
		r.URL.RawQuery = q.Encode()
		next(w, r)
	}
}

// linkAuthAlias merges one anon id into sub once and records the alias. The
// merges run lock-free (each store serialises itself); the alias check and
// record take the auth lock and nothing else.
func linkAuthAlias(a *authStore, anon, sub string) {
	rec := a.best.get(anon)
	a.best.merge(sub, rec.Distance, rec.Coins, rec.Lifetime, rec.Spent, rec.Found)
	sv := a.save.get(anon)
	if sv.Blob != "" {
		a.save.put(sub, sv.Blob, sv.SavedAt)
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	if _, linked := a.aliases[anon]; linked {
		return
	}
	if len(a.aliases) >= maxAuthAliases {
		return
	}
	a.aliases[anon] = sub
	a.dirty = true
}

// sendMagicMail delivers one link through the deployment's relay: plain SMTP
// on 587 with STARTTLS, direct TLS on 465, auth when SMTP_USER is set. ~25
// lines of stdlib and no new dependency — the relay string stays generic on
// purpose (the operator's MTA is their business; the required half is the
// shape: plain text, the link, the one-shot sentence, no address in any
// header but To).
func sendMagicMail(to, link string) error {
	host := env("SMTP_HOST", "")
	port := env("SMTP_PORT", "587")
	user := env("SMTP_USER", "")
	pass := env("SMTP_PASSWORD", "")
	from := env("SMTP_FROM", "")
	name := env("SMTP_FROM_NAME", "CrimeKickers")

	addr := net.JoinHostPort(host, port)
	var c *smtp.Client
	if port == "465" {
		tlsConn, err := tls.DialWithDialer(&net.Dialer{Timeout: 10 * time.Second}, "tcp", addr, &tls.Config{ServerName: host})
		if err != nil {
			return err
		}
		var err2 error
		if c, err2 = smtp.NewClient(tlsConn, host); err2 != nil {
			_ = tlsConn.Close()
			return err2
		}
	} else {
		conn, err := net.DialTimeout("tcp", addr, 10*time.Second)
		if err != nil {
			return err
		}
		var err2 error
		if c, err2 = smtp.NewClient(conn, host); err2 != nil {
			_ = conn.Close()
			return err2
		}
		if err2 = c.StartTLS(&tls.Config{ServerName: host}); err2 != nil {
			_ = c.Close()
			return err2
		}
	}
	defer func() { _ = c.Quit() }()
	if user != "" {
		if err := c.Auth(smtp.PlainAuth("", user, pass, host)); err != nil {
			return err
		}
	}
	fromAddr := (&mail.Address{Name: name, Address: from}).String()
	var msg strings.Builder
	msg.WriteString("From: " + fromAddr + "\r\n")
	msg.WriteString("To: " + to + "\r\n")
	msg.WriteString("Subject: Your CrimeKickers sign-in link\r\n")
	msg.WriteString("Date: " + time.Now().UTC().Format(time.RFC1123Z) + "\r\n")
	msg.WriteString("MIME-Version: 1.0\r\n")
	msg.WriteString("Content-Type: text/plain; charset=utf-8\r\n")
	msg.WriteString("\r\n")
	msg.WriteString(link + "\r\n\r\n")
	msg.WriteString("It works once and expires in 15 minutes.\r\n")
	msg.WriteString("Open it on the computer you play on.\r\n")
	msg.WriteString("If you did not ask for it, ignore this mail.\r\n")
	if err := c.Mail(from); err != nil {
		return err
	}
	if err := c.Rcpt(to); err != nil {
		return err
	}
	w, err := c.Data()
	if err != nil {
		return err
	}
	if _, err := w.Write([]byte(msg.String())); err != nil {
		_ = w.Close()
		return err
	}
	return w.Close()
}

// authDump is the file shape: sessions and aliases. Pending tokens and rate
// windows are memory-only by design (see the banner) and never serialised.
type authDump struct {
	Sessions map[string]authSession `json:"sessions"`
	Aliases  map[string]string      `json:"aliases"`
}

// load reads the dump back, re-applying every bound the request path
// enforces — a hand-edited file cannot smuggle past them — and stopping at
// the caps. Malformed keys and values are dropped, never fatal.
func (a *authStore) load() error {
	data, err := os.ReadFile(a.path)
	if err != nil {
		return err
	}
	var dump authDump
	if err := json.Unmarshal(data, &dump); err != nil {
		return err
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	for k, s := range dump.Sessions {
		if len(a.sessions) >= maxAuthSessions {
			break
		}
		if !tokenRe.MatchString(k) || !playerIDRe.MatchString(s.Sub) || s.Exp <= 0 {
			continue
		}
		a.sessions[k] = s
	}
	for k, v := range dump.Aliases {
		if len(a.aliases) >= maxAuthAliases {
			break
		}
		if !playerIDRe.MatchString(k) || !playerIDRe.MatchString(v) {
			continue
		}
		a.aliases[k] = v
	}
	return nil
}

// dump writes sessions and aliases atomically (temp file + rename), exactly
// like the sibling stores. A failure leaves `dirty` set: the next tick tries
// again, and a failed dump is a log line — the lobby keeps serving from
// memory (see main.go's healthz rule: an unwritable auth file is nothing a
// probe may consult).
func (a *authStore) dump() error {
	a.mu.Lock()
	dump := authDump{
		Sessions: make(map[string]authSession, len(a.sessions)),
		Aliases:  make(map[string]string, len(a.aliases)),
	}
	for k, v := range a.sessions {
		dump.Sessions[k] = v
	}
	for k, v := range a.aliases {
		dump.Aliases[k] = v
	}
	a.mu.Unlock()

	data, err := json.Marshal(dump)
	if err != nil {
		return err
	}
	dir := filepath.Dir(a.path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(dir, "auth-*.tmp")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		_ = os.Remove(tmpName)
		return err
	}
	if err := tmp.Close(); err != nil {
		_ = os.Remove(tmpName)
		return err
	}
	if err := os.Rename(tmpName, a.path); err != nil {
		_ = os.Remove(tmpName)
		return err
	}

	a.mu.Lock()
	a.dirty = false
	a.mu.Unlock()
	return nil
}

// runDumper flushes a dirty store on the sibling stores' interval.
func (a *authStore) runDumper() {
	t := time.NewTicker(authDumpInterval)
	defer t.Stop()
	for range t.C {
		a.mu.Lock()
		dirty := a.dirty
		a.mu.Unlock()
		if !dirty || a.path == "" {
			continue
		}
		if err := a.dump(); err != nil {
			log.Printf("lobby: auth: dump failed: %v", err)
		}
	}
}

// sweepOnce drops what time killed: expired pending, expired sessions, elapsed
// rate windows. Only a dropped SESSION dirties the file — pending and windows
// are memory-only, so losing them writes nothing. Factored to take `now` so
// the test advances the clock instead of sleeping.
func (a *authStore) sweepOnce(now time.Time) {
	a.mu.Lock()
	defer a.mu.Unlock()
	for k, p := range a.pending {
		if !now.Before(time.Unix(p.Exp, 0)) {
			delete(a.pending, k)
		}
	}
	for k, s := range a.sessions {
		if !now.Before(time.Unix(s.Exp, 0)) {
			delete(a.sessions, k)
			a.dirty = true
		}
	}
	for k, w := range a.limits {
		if !now.Before(w.until) {
			delete(a.limits, k)
		}
	}
}

// runSweeper drops expired state on sweepInterval, from the process clock.
func (a *authStore) runSweeper() {
	t := time.NewTicker(sweepInterval)
	defer t.Stop()
	for range t.C {
		a.sweepOnce(time.Now())
	}
}
