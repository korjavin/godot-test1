package main

// main.go — process entry: config from the environment, six routes, and one
// small piece of state. The lobby does signalling, membership and master-naming
// and no game logic, but it is no longer entirely stateless: /best keeps
// per-player best-run records (best.go), because the game's own `user://` store
// does not survive on the web export. Still no database.

import (
	"crypto/hmac"
	"crypto/sha1" //nolint:gosec // the TURN REST API specifies HMAC-SHA1; coturn implements exactly that
	"embed"
	"encoding/base64"
	"io/fs"
	"log"
	"net/http"
	"net/url"
	"os"
	"path"
	"strconv"
	"strings"
	"time"
)

//go:embed static
var staticFS embed.FS

// allowedOrigins gates websocket upgrades. "*" (the default) means any page may
// connect: the lobby is intentionally public and holds no credential a
// cross-origin page could ride on. Narrow it with LOBBY_ALLOWED_ORIGINS when the
// game is served from a known host.
var allowedOrigins = []string{"*"}

func main() {
	addr := env("LOBBY_ADDR", ":8080")
	if o := env("LOBBY_ALLOWED_ORIGINS", "*"); o != "" {
		parsed := splitList(o)
		// An unparseable list yields NO origins, which refuses every upgrade and
		// makes corsOrigin answer "" for everything — i.e. multiplayer is simply
		// broken, with `origins=[]` in the startup log and nothing complaining.
		// Fail loudly instead.
		if len(parsed) == 0 {
			log.Fatalf("lobby: LOBBY_ALLOWED_ORIGINS=%q parsed to no origins", o)
		}
		allowedOrigins = parsed
	}

	hub := NewHub()
	// The lobby's ONE piece of persistent state — see best.go for why it exists at
	// all. LOBBY_BEST_FILE unset means memory-only: records still work for the
	// life of the process, they just do not survive a redeploy.
	best := newBestStore(env("LOBBY_BEST_FILE", ""))
	go best.runDumper()

	mux := http.NewServeMux()
	mux.HandleFunc("/ws", hub.ServeWS)
	mux.HandleFunc("/ice", iceHandler)
	mux.HandleFunc("/rooms", hub.roomsHandler)
	// ⚠️ A NEW ROUTE ALSO NEEDS THE TRAEFIK PATH LIST in server/docker-compose.yml
	// — the game client's catch-all owns `/` in production, so a route missing
	// from the lobby's narrow rule silently serves index.html instead.
	mux.HandleFunc("/best", best.handler)
	mux.HandleFunc("/healthz", healthzHandler(hub))
	sub, err := fs.Sub(staticFS, "static")
	if err != nil {
		log.Fatalf("lobby: embedded static: %v", err)
	}
	mux.Handle("/", http.FileServer(http.FS(sub)))

	srv := &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
		// No WriteTimeout: it would guillotine long-lived websockets.
		// IdleTimeout DOES apply, though — a hijacked websocket is outside the
		// keep-alive loop entirely, while an ordinary client that fetches
		// /healthz once and then goes silent would otherwise hold its fd forever
		// on a public unauthenticated service.
		IdleTimeout: 60 * time.Second,
	}
	log.Printf("lobby: listening on %s (origins=%v)", addr, allowedOrigins)
	// ponytail: no graceful shutdown. Rooms are in-memory and disposable — on
	// SIGTERM the peers reconnect and re-create their room from its invite code.
	if err := srv.ListenAndServe(); err != nil {
		log.Fatalf("lobby: %v", err)
	}
}

// healthzHandler answers the Docker HEALTHCHECK, and it reports on SIGNALLING ONLY.
//
// ⚠️ IT MUST NEVER CONSULT THE BEST-SCORES STORE (bead godot-test1-xuz,
// 2026-09-05). It never has — this is a rule written down, not a bug fixed, and
// saying so plainly matters because the incident is easy to misread.
//
// WHAT ACTUALLY HAPPENED: the prod host filled its disk, every `bestStore.dump`
// began failing with ENOSPC, the container went UNHEALTHY, Traefik dropped the
// unhealthy router, and /ws /ice /rooms /best all fell through to the web client's
// catch-all. But the dump failure did not cause the UNHEALTHY — this handler was
// already answering `ok:true` unconditionally. On a 100%-full disk the Docker
// daemon cannot exec the container's HEALTHCHECK or write its state file, so the
// probe fails whatever we answer. **The lobby is therefore NOT hardened against a
// full disk, and any other filler reproduces the same chain.** The fix for the
// cause is the deploy job's image prune (.github/workflows/build.yml).
//
// WHAT THE RULE IS FOR, then: the obvious future "improvement" — reporting dump
// health here so operators can see a broken scoreboard — is precisely the change
// that would make a disk fault take signalling down for real. What this service is
// FOR is introducing peers, and that holds no disk, no database and no file handle.
// A lobby that can still do it is healthy however broken its optional scoreboard
// is; an unwritable /best is a LOG LINE (bestStore.runDumper) and records stay
// correct in memory, with the store's `dirty` flag surviving the failure so one
// recovered write flushes everything.
//
// THE GUARD IS THE SIGNATURE, not a test assertion: this takes `*Hub` and nothing
// else, so widening it to reach a store is a compile-level change that drags the
// author through server/health_test.go and this comment. (That file's
// TestHealthzSurvivesFailedDump is an honest unit test of the handler — 200,
// ok:true, a live room count — and its failing-store fixture documents the scenario
// rather than measuring it; the store is not reachable from here to measure.)
//
// A free function taking the hub, rather than the closure it used to be, purely so
// a test can drive it without standing up a listener.
func healthzHandler(hub *Hub) http.HandlerFunc {
	return func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write(mustJSON(map[string]any{"ok": true, "rooms": hub.Rooms()}))
	}
}

// corsOrigin returns the Access-Control-Allow-Origin value for this request, or
// "" when the origin is not allowed.
//
// /ice is fetched cross-origin by design — the game is served from GitHub Pages
// while the lobby lives on its own host — so without this header the browser
// discards the response and the client never gets its TURN credentials. It
// honours the same allowlist as the websocket upgrade instead of answering "*"
// unconditionally, which narrows which PAGES may read the body.
//
// ⚠️ IT IS NOT ACCESS CONTROL. CORS is enforced by browsers only: `curl /ice`
// returns the TURN credentials in full whatever the allowlist says, and the
// shipped default is "*" anyway. What bounds the damage is that the credentials
// EXPIRE — see turnCredentials, which mints coturn REST credentials whenever the
// deployment has a TURN_SECRET.
func corsOrigin(origin string) string {
	if len(allowedOrigins) == 1 && allowedOrigins[0] == "*" {
		return "*"
	}
	if origin == "" {
		return ""
	}
	u, err := url.Parse(origin)
	if err != nil || u.Host == "" {
		return ""
	}
	host := strings.ToLower(u.Host)
	for _, pat := range allowedOrigins {
		// path.Match gives "*.example.com" wildcards for free; a host has no "/",
		// so its one restriction does not bite.
		if ok, err := path.Match(strings.ToLower(pat), host); ok && err == nil {
			return origin
		}
	}
	return ""
}

// iceHandler hands clients the ICE server list so TURN credentials live in the
// deployment's environment rather than baked into the game build.
func iceHandler(w http.ResponseWriter, r *http.Request) {
	if o := corsOrigin(r.Header.Get("Origin")); o != "" {
		w.Header().Set("Access-Control-Allow-Origin", o)
		w.Header().Set("Vary", "Origin")
	}
	servers := []map[string]any{}
	if stun := env("STUN_URL", "stun:stun.l.google.com:19302"); stun != "" {
		servers = append(servers, map[string]any{"urls": splitList(stun)})
	}
	if turn := env("TURN_URL", ""); turn != "" {
		user, cred := turnCredentials(time.Now())
		servers = append(servers, map[string]any{
			"urls":       splitList(turn),
			"username":   user,
			"credential": cred,
		})
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	_, _ = w.Write(mustJSON(map[string]any{"iceServers": servers}))
}

// roomsHandler publishes the open-room list, so a player picks a room from a
// list instead of being handed a code by a friend.
//
// It is HTTP rather than a websocket message ON PURPOSE: `/ws` *joins* on
// connect, and an unknown-but-well-formed code CREATES a room (see `Hub.Join`),
// so a client asking "what rooms exist?" over the socket would first have to
// make a junk room to ask from — which would then appear in its own answer.
//
// Same CORS rule as /ice: the game is served from a different origin than the
// lobby, so without the header the browser discards the response. Unlike /ice
// the body is not a credential, but honouring one allowlist rather than two is
// the simpler thing to keep correct.
func (h *Hub) roomsHandler(w http.ResponseWriter, r *http.Request) {
	if o := corsOrigin(r.Header.Get("Origin")); o != "" {
		w.Header().Set("Access-Control-Allow-Origin", o)
		w.Header().Set("Vary", "Origin")
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	// Cached for a second — see listedRoomsJSON: this route is unauthenticated
	// and unrated, and ListRooms holds the hub mutex every signal serialises on.
	_, _ = w.Write(h.listedRoomsJSON())
}

// turnCredentialTTL is how long a minted TURN credential stays usable.
//
// It is a CEILING ON A LEAK, not a session timer, and it has a floor as well as
// a ceiling: coturn re-checks the timestamp on every authentication, so a
// credential that expires mid-room kills the relay under a player who is still
// in it. A day covers any browser session while still meaning a scraped /ice
// response is worthless tomorrow.
const turnCredentialTTL = 24 * time.Hour

// turnCredentials builds the username/credential pair /ice hands out.
//
// With TURN_SECRET set this is coturn's REST form (`--use-auth-secret`):
// username "<unix expiry>:ck", credential base64(HMAC-SHA1(secret, username)).
// The shared secret never leaves the deployment, and a scraped credential stops
// relaying at the expiry instead of never — /ice is unauthenticated by
// necessity (the game build cannot hold a secret) and CORS is browser-only, so
// expiry is the only bound there is. SHA-1 is not a choice: the TURN REST API
// specifies HMAC-SHA1 and coturn implements exactly that.
//
// UNSET, IT FALLS BACK TO THE STATIC PAIR ON PURPOSE. coturn's --use-auth-secret
// and its static --user list are mutually exclusive — measured against
// coturn 4.6.3, with the secret configured the static user is refused with
// "check_stun_auth: Cannot find credentials of user <alice>" — so this returning
// a REST pair against a relay the operator has not migrated yet would take TURN
// down for everybody. The two halves flip together off one environment variable:
// docker-compose.yml passes coturn --use-auth-secret/--static-auth-secret only
// when TURN_SECRET is set, and this mints the matching credential.
func turnCredentials(now time.Time) (string, string) {
	secret := env("TURN_SECRET", "")
	if secret == "" {
		return env("TURN_USER", ""), env("TURN_PASSWORD", "")
	}
	user := strconv.FormatInt(now.Add(turnCredentialTTL).Unix(), 10) + ":ck"
	mac := hmac.New(sha1.New, []byte(secret))
	mac.Write([]byte(user))
	return user, base64.StdEncoding.EncodeToString(mac.Sum(nil))
}

func env(key, def string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return def
}

// splitList parses a comma-separated env value into non-empty trimmed entries.
func splitList(s string) []string {
	parts := strings.Split(s, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}
