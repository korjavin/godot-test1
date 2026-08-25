package main

// main.go — process entry: config from the environment, five routes, no state of
// its own. The lobby does signalling, membership and master-naming and nothing
// else: no game logic, no persistence, no database.

import (
	"embed"
	"io/fs"
	"log"
	"net/http"
	"net/url"
	"os"
	"path"
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
		allowedOrigins = splitList(o)
	}

	hub := NewHub()
	mux := http.NewServeMux()
	mux.HandleFunc("/ws", hub.ServeWS)
	mux.HandleFunc("/ice", iceHandler)
	mux.HandleFunc("/rooms", hub.roomsHandler)
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write(mustJSON(map[string]any{"ok": true, "rooms": hub.Rooms()}))
	})
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
	}
	log.Printf("lobby: listening on %s (origins=%v)", addr, allowedOrigins)
	// ponytail: no graceful shutdown. Rooms are in-memory and disposable — on
	// SIGTERM the peers reconnect and re-create their room from its invite code.
	if err := srv.ListenAndServe(); err != nil {
		log.Fatalf("lobby: %v", err)
	}
}

// corsOrigin returns the Access-Control-Allow-Origin value for this request, or
// "" when the origin is not allowed.
//
// /ice is fetched cross-origin by design — the game is served from GitHub Pages
// while the lobby lives on its own host — so without this header the browser
// discards the response and the client never gets its TURN credentials. Because
// the body *is* the TURN credentials, it honours the same allowlist as the
// websocket upgrade instead of answering "*" unconditionally.
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
		servers = append(servers, map[string]any{
			"urls":       splitList(turn),
			"username":   env("TURN_USER", ""),
			"credential": env("TURN_PASSWORD", ""),
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
	_, _ = w.Write(mustJSON(map[string]any{"rooms": h.ListRooms()}))
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
