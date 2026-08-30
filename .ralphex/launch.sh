#!/bin/bash
# Detach ralphex from the harness process tree: the ( … &) double-fork reparents it
# to launchd so it outlives the Bash tool call (which is reaped at 1h).
# -m 50: the local default is 2, which is one iteration per task and not enough.
cd /Users/iv/Projects/godot-test1/.claude/worktrees/agent-abb41355869a62e65
mkdir -p .ralphex
( nohup ralphex -m 50 --task-model opus --review-model opus \
    docs/plans/20260830-tower-retire-the-legacy-keep.md \
    >> .ralphex/ralphex.log 2>&1 < /dev/null & )
sleep 3
pgrep -fl 'ralphex -m 50' | head -3
