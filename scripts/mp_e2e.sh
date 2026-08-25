#!/usr/bin/env bash
# Two-instance headless end-to-end check of the multiplayer LOBBY RELAY path:
# start a local lobby, host a room from one Godot instance, check the room shows
# up in the public `/rooms` list, join it from a second instance, and prove both
# ended up on the SAME world seed.
#
#     bash scripts/mp_e2e.sh
#
# Exits 0 on agreement, non-zero on a mismatch, a timeout, or a missing line —
# a failure here is a real failure, not a note. This is the automated evidence
# for the production bug where a joiner silently walked its own private world
# (the seed used to be latched only after the /ice fetch; see Task 9a).
#
# ponytail: covers the relay only — the room, the seed and its adoption. The
# WebRTC mesh and the remote avatars still need two real browsers, because
# desktop headless has no `webrtc-native` addon (hence `--lobby-only`). Wiring
# this into CI is a one-job follow-up; `.github/workflows/` is owned elsewhere.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-godot}"
# A per-run port, so two copies of the suite do not collide. Not a free-port
# probe: that needs a helper binary, and a busy port shows up as "lobby never
# became healthy" with the bind error right there in the log.
PORT="${PORT:-$((18000 + $$ % 1000))}"
HOST_HOLD=45
LOG_DIR="$(mktemp -d)"
LOBBY_PID=""
HOST_PID=""

cleanup() {
	[ -n "$HOST_PID" ] && kill "$HOST_PID" 2>/dev/null
	[ -n "$LOBBY_PID" ] && kill "$LOBBY_PID" 2>/dev/null
	wait 2>/dev/null
	rm -rf "$LOG_DIR"
}
trap cleanup EXIT INT TERM

fail() {
	echo "E2E FAILED: $*" >&2
	for f in "$LOG_DIR"/*.log; do
		[ -e "$f" ] || continue
		echo "--- $f ---" >&2
		tail -n 25 "$f" >&2
	done
	exit 1
}

command -v go >/dev/null || fail "go is not installed"
command -v "$GODOT" >/dev/null || fail "godot is not on PATH (override with GODOT=...)"

LOBBY_URL="ws://127.0.0.1:${PORT}"

# BUILT, not `go run`: `go run` execs the compiled binary as a CHILD, so killing
# the `go run` process on cleanup would leave the lobby holding the port.
echo "E2E: building lobby"
(cd "$ROOT/server" && go build -o "$LOG_DIR/lobby" .) >"$LOG_DIR/build.log" 2>&1 \
	|| fail "go build failed"

echo "E2E: starting lobby on ${PORT}"
LOBBY_ADDR="127.0.0.1:${PORT}" "$LOG_DIR/lobby" >"$LOG_DIR/lobby.log" 2>&1 &
LOBBY_PID=$!

for _ in $(seq 1 60); do
	if curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1; then
		break
	fi
	sleep 1
done
curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null 2>&1 || fail "lobby never became healthy"

run_instance() {
	# run_instance <logfile> <extra args...>
	local log="$1"
	shift
	"$GODOT" --headless --path "$ROOT" --script res://scripts/mp_e2e.gd -- \
		--lobby="$LOBBY_URL" --lobby-only "$@" >"$log" 2>&1
}

echo "E2E: hosting"
run_instance "$LOG_DIR/host.log" --role=host --hold="$HOST_HOLD" &
HOST_PID=$!

ROOM=""
for _ in $(seq 1 90); do
	ROOM="$(grep -m1 '^E2E_ROOM=' "$LOG_DIR/host.log" 2>/dev/null | cut -d= -f2 | tr -d '\r')"
	[ -n "$ROOM" ] && break
	kill -0 "$HOST_PID" 2>/dev/null || break
	sleep 1
done
[ -n "$ROOM" ] || fail "host never printed E2E_ROOM"

# The public room list, against the same live lobby the game is talking to. The
# Go tests cover ListRooms' logic; this covers the thing they cannot — that a
# room a real client actually hosted is reachable over HTTP at /rooms, which is
# the single request the Join panel's list is built from.
echo "E2E: checking /rooms lists ${ROOM}"
ROOMS_BODY="$(curl -fsS "http://127.0.0.1:${PORT}/rooms" 2>/dev/null)" \
	|| fail "/rooms request failed"
case "$ROOMS_BODY" in
	*"\"$ROOM\""*) ;;
	*) fail "/rooms did not list the hosted room ${ROOM}: ${ROOMS_BODY}" ;;
esac

echo "E2E: room ${ROOM}, joining"

run_instance "$LOG_DIR/join.log" --role=join --code="$ROOM"
JOIN_STATUS=$?

HOST_SEED="$(grep -m1 '^E2E_SEED=' "$LOG_DIR/host.log" | cut -d= -f2 | tr -d '\r')"
JOIN_SEED="$(grep -m1 '^E2E_SEED=' "$LOG_DIR/join.log" | cut -d= -f2 | tr -d '\r')"

[ "$JOIN_STATUS" -eq 0 ] || fail "joiner exited ${JOIN_STATUS} (timeout?)"
[ -n "$HOST_SEED" ] || fail "host never printed E2E_SEED"
[ -n "$JOIN_SEED" ] || fail "joiner never printed E2E_SEED"
[ "$HOST_SEED" = "$JOIN_SEED" ] || fail "seed mismatch: host=${HOST_SEED} join=${JOIN_SEED}"

echo "E2E OK: room ${ROOM}, shared seed ${HOST_SEED}"
exit 0
