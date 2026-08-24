package main

// main.go — process entry: config from the environment, four routes, no state of
// its own. The lobby does signalling, membership and master-naming and nothing
// else: no game logic, no persistence, no database.

import (
	"embed"
	"io/fs"
	"log"
	"net/http"
	"os"
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

// iceHandler hands clients the ICE server list so TURN credentials live in the
// deployment's environment rather than baked into the game build.
func iceHandler(w http.ResponseWriter, r *http.Request) {
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
