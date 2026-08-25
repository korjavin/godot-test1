#!/usr/bin/env bash
# Two-instance headless end-to-end check of the multiplayer LOBBY RELAY path:
# start a local lobby, host a room from one Godot instance, check the room shows
# up in the public `/rooms` list, join it from a second instance, and prove both
# ended up on the SAME world seed. Then a second phase proves phase 5's MASTER
# MIGRATION over the same relay: the host stops heartbeating while keeping its
# socket open (a throttled tab), and a fresh joiner must vote it out and come out
# master itself.
#
#     bash scripts/mp_e2e.sh
#
# Exits 0 on agreement, non-zero on a mismatch, a timeout, or a missing line —
# a failure here is a real failure, not a note. This is the automated evidence
# for the production bug where a joiner silently walked its own private world
# (the seed used to be latched only after the /ice fetch; see Task 9a).
#
# ponytail: covers the relay only — the room, the seed, its adoption and the
# stall vote. The WebRTC mesh, the remote avatars and the croc sync still need
# two real browsers, because desktop headless has no `webrtc-native` addon
# (hence `--lobby-only`). Wiring this into CI is a one-job follow-up;
# `.github/workflows/` is owned elsewhere.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-godot}"
# A per-run port, so two copies of the suite do not collide. Not a free-port
# probe: that needs a helper binary, and a busy port shows up as "lobby never
# became healthy" with the bind error right there in the log.
PORT="${PORT:-$((18000 + $$ % 1000))}"
# The one host process outlives BOTH phases (the stall phase needs the deposed
# host still connected, or the lobby's ordinary disconnect re-election would fire
# instead of a vote). Cleanup kills it the moment the script ends, so an
# over-generous hold costs nothing but a slow one fails the run.
# ABOVE INSTANCE_TIMEOUT (180), deliberately. The hold never needs to expire —
# the EXIT trap kills the host either way — and an expiring hold is precisely the
# trap the stall phase's liveness check exists to catch, yet cannot: the returning
# _hold_open calls leave(), whose disconnect fires the lobby's ORDINARY
# re-election, while `kill -0` (which runs only after the joiner has exited) still
# sees the process during SceneTree teardown. Below the timeout it is also a plain
# flake on a cold runner — two headless boots plus the ~6 s vote can outrun 120 s.
HOST_HOLD=240
LOG_DIR="$(mktemp -d)"
LOBBY_PID=""
HOST_PID=""

cleanup() {
	[ -n "$HOST_PID" ] && kill "$HOST_PID" 2>/dev/null
	[ -n "$LOBBY_PID" ] && kill "$LOBBY_PID" 2>/dev/null
	wait 2>/dev/null
	rm -rf "$LOG_DIR"
}
# INT/TERM must EXIT, not just clean up: `cleanup` returns, and a bare
# `trap cleanup INT` would hand control back to the interrupted line with the
# lobby killed and $LOG_DIR already removed — the run then carries on and fails
# with a nonsense message, cleaning up a second time on the way out.
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

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
# Probed like the other two: without curl the health loop below fails all 60
# iterations and reports "lobby never became healthy", pointing the reader at
# entirely the wrong component after burning a minute.
command -v curl >/dev/null || fail "curl is not installed"
command -v perl >/dev/null || fail "perl is not installed (used as the instance timeout)"

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

# A HARD EXTERNAL LIMIT on every instance. mp_e2e.gd's own TIMEOUT_SEC only
# fires while _run() is still running, and a GDScript runtime error unwinds the
# erroring function and returns — so an error anywhere in _run() means quit() is
# never reached and the process idles forever, blocking this script (and
# cleanup's `wait`) with no failure ever reported. macOS has no timeout(1), hence
# perl's alarm.
INSTANCE_TIMEOUT=180

run_instance() {
	# run_instance <logfile> <extra args...>
	local log="$1"
	shift
	perl -e 'alarm shift; exec @ARGV or exit 127' "$INSTANCE_TIMEOUT" \
		"$GODOT" --headless --path "$ROOT" --script res://scripts/mp_e2e.gd -- \
		--lobby="$LOBBY_URL" --lobby-only "$@" >"$log" 2>&1
}

# `--stall` from the start: it only silences the heartbeat, and the seed phase's
# joiner is gone long before the manager's 4 s + 2 s stall clock could fire.
echo "E2E: hosting"
# NOT `run_instance ... &`. Backgrounding a shell FUNCTION forks a subshell, and
# with traps installed bash cannot apply its last-command exec optimisation — so
# `$!` was the wrapper, `kill "$HOST_PID"` in `cleanup` killed only the wrapper,
# and the exec'd Godot was reparented to init and ran on for the rest of its 180 s
# alarm: one stray headless instance per run (and per Ctrl-C), still talking to a
# lobby this script had already killed and writing into a $LOG_DIR it had already
# removed. `exec` inside the subshell makes the backgrounded job BE perl, which
# then execs Godot in place, so $! names the process under test. (`run_instance`
# stays as it is — the two joiner calls run in the foreground.)
(
	exec perl -e 'alarm shift; exec @ARGV or exit 127' "$INSTANCE_TIMEOUT" \
		"$GODOT" --headless --path "$ROOT" --script res://scripts/mp_e2e.gd -- \
		--lobby="$LOBBY_URL" --lobby-only --role=host --hold="$HOST_HOLD" --stall \
		>"$LOG_DIR/host.log" 2>&1
) &
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

# ---------------------------------------------------------------------------
# Phase 2: the stalled host is voted out and the joiner becomes master.
# ---------------------------------------------------------------------------
echo "E2E: stall phase — waiting for the vote to depose the host"
kill -0 "$HOST_PID" 2>/dev/null || fail "host exited before the stall phase"

run_instance "$LOG_DIR/join2.log" --role=join --code="$ROOM" --await-master
STALL_STATUS=$?

# THE HOST MUST STILL BE CONNECTED. Checking only before the joiner runs leaves
# the trap the header warns about wide open: if the host's --hold expired
# mid-phase (a cold import on a CI runner easily outruns it), it called leave()
# and the lobby's ORDINARY disconnect re-election made the joiner master with
# zero votes cast — every assertion below then holds while proving nothing about
# stall detection.
kill -0 "$HOST_PID" 2>/dev/null \
	|| fail "host's hold expired during the stall phase — the migration would be a plain disconnect re-election, not a vote"

HOST_ID="$(grep -m1 '^E2E_YOU=' "$LOG_DIR/host.log" | cut -d= -f2 | tr -d '\r')"
HOST_MASTER="$(grep -m1 '^E2E_MASTER=' "$LOG_DIR/host.log" | cut -d= -f2 | tr -d '\r')"
JOIN2_ID="$(grep -m1 '^E2E_YOU=' "$LOG_DIR/join2.log" | cut -d= -f2 | tr -d '\r')"
NEW_MASTER="$(grep -m1 '^E2E_NEWMASTER=' "$LOG_DIR/join2.log" | cut -d= -f2 | tr -d '\r')"

[ "$STALL_STATUS" -eq 0 ] || fail "stall joiner exited ${STALL_STATUS} (never became master?)"
[ -n "$HOST_ID" ] || fail "host never printed E2E_YOU"
# Without this the "master migrated off the host" test below is satisfied by any
# run in which the host was never master to begin with.
[ "$HOST_MASTER" = "$HOST_ID" ] || fail "host was not the master to begin with (${HOST_MASTER:-<none>}) — nothing to migrate off"
[ -n "$JOIN2_ID" ] || fail "stall joiner never printed E2E_YOU"
[ -n "$NEW_MASTER" ] || fail "stall joiner never printed E2E_NEWMASTER"
[ "$NEW_MASTER" = "$JOIN2_ID" ] || fail "new master ${NEW_MASTER} is not the joiner ${JOIN2_ID}"
[ "$NEW_MASTER" != "$HOST_ID" ] || fail "master never migrated off the stalled host ${HOST_ID}"

echo "E2E OK: room ${ROOM}, shared seed ${HOST_SEED}, master migrated ${HOST_ID} -> ${NEW_MASTER}"
exit 0
