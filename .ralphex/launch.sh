#!/bin/bash
# Detach ralphex from the harness process tree: the ( … &) double-fork reparents it
# to launchd so it outlives the Bash tool call (which is reaped at 1h).
cd /Users/iv/Projects/godot-test1/.claude/worktrees/agent-abb41355869a62e65
mkdir -p .ralphex
( nohup ralphex --task-model opus --review-model opus \
    docs/plans/20260830-tower-retire-the-legacy-keep.md \
    > .ralphex/ralphex.log 2>&1 < /dev/null & )
sleep 3
pgrep -fl 'ralphex --task-model' | head -3
