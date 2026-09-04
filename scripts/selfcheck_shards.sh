#!/bin/sh
# Which self-checks does shard <index> of <total> run?
#
#   sh scripts/selfcheck_shards.sh <index> <total>   # prints one path per line
#   sh scripts/selfcheck_shards.sh --count           # how many checks the glob names
#   sh scripts/selfcheck_shards.sh --selftest        # asserts the properties below
#
# THE GLOB IS STILL THE SOURCE OF TRUTH. `scripts/*_selfcheck.gd` is what gets
# partitioned, exactly as before; selfcheck_durations.json only says how HEAVY
# each name is, and a name it does not carry is treated as the heaviest thing in
# the table. So a check added to scripts/ is gated the day it lands (CLAUDE.md's
# rule — never a list of check names in the workflow) and, until somebody
# measures it, it is assumed to be the slowest check in the suite rather than
# silently landing in a bin that already holds one.
#
# WHY NOT "every Nth file", which is what this replaces: that partition is
# POSITIONAL, so adding or renaming a file reshuffles every shard. boss (3m01)
# and tower_interior (1m30) landed in the same bin after PR #233 split two
# checks in two, and the gate every push waits on went 4m30 -> 6m00 with the
# other four shards idle at ~1m20. Cost-aware packing is the fix; the numbers
# are a committed table because CI cannot measure a job before it runs it.
#
# THE PACKING is longest-processing-time-first: sort descending by weight (ties
# broken by name, so every shard computes the identical partition from the
# identical checkout), then hand each check to the lightest bin so far. That
# gives the property the acceptance asks for FOR FREE: the first `total` items
# each land in a bin that is empty at the time, so THE N HEAVIEST CHECKS ARE
# ALWAYS IN N DIFFERENT SHARDS — a new file cannot pair the two slowest ones,
# whatever its weight. LPT's classic (4/3 - 1/(3n)) bound is far more than good
# enough here: the suite is one 3m item and a long tail, so the 3m item is the
# floor no partition can beat and LPT reaches it.
#
# REFRESHING THE TABLE: the shard step prints `OK   <name>  (Ns)` for every
# check it runs, so
#   gh run view <run-id> --log | grep -o "OK   [a-z_]*  ([0-9]*s)"
# across the shards of one master run is the whole measurement. Stale weights
# only cost balance, never correctness — but a name in the table that no longer
# exists is a typo or a deleted check, and --selftest (run in CI) fails on it.
#
# POSIX sh + awk, no bashisms: the godot-ci image ships no bash, so the workflow
# runs `sh -e {0}` and a bashism is an exit 127 before the first check runs.
set -e

WEIGHTS=scripts/selfcheck_durations.json
TMP="${TMPDIR:-/tmp}"

# The one place the partition is computed. Reads the file list on stdin, prints
# "<bin> <path>" for each of them, in assignment order (so the first N lines are
# the N heaviest checks).
assign() {
  awk -v weights="$WEIGHTS" -v bins="$1" '
    BEGIN {
      if (bins < 1) { print "bad shard count: " bins > "/dev/stderr"; exit 1 }
      while ((getline line < weights) > 0) {
        if (!match(line, /"[a-z0-9_]+"[[:space:]]*:/)) continue
        k = substr(line, RSTART, RLENGTH)
        sub(/^"/, "", k); sub(/"[[:space:]]*:$/, "", k)
        v = substr(line, RSTART + RLENGTH); gsub(/[^0-9.]/, "", v)
        w[k] = v + 0
        if (w[k] > maxw) maxw = w[k]
      }
      close(weights)
      if (maxw <= 0) { print "no weights read from " weights > "/dev/stderr"; exit 1 }
    }
    { name = $0; sub(/.*\//, "", name); sub(/\.gd$/, "", name)
      n++; path[n] = $0; key[n] = name
      cost[n] = (name in w) ? w[name] : maxw }          # unmeasured == heaviest
    END {
      if (n == 0) { print "no self-checks on stdin" > "/dev/stderr"; exit 1 }
      # Descending by cost, ties by name — every shard must agree on the order.
      for (i = 1; i <= n; i++)
        for (j = i + 1; j <= n; j++)
          if (cost[j] > cost[i] || (cost[j] == cost[i] && key[j] < key[i])) {
            t = cost[i]; cost[i] = cost[j]; cost[j] = t
            t = key[i];  key[i]  = key[j];  key[j]  = t
            t = path[i]; path[i] = path[j]; path[j] = t
          }
      for (i = 1; i <= n; i++) {
        b = 0                                            # lightest bin so far
        for (k = 1; k < bins; k++) if (load[k] < load[b]) b = k
        load[b] += cost[i]
        print b " " path[i]
      }
    }'
}

globbed() {
  for f in scripts/*_selfcheck.gd; do
    [ -e "$f" ] || { echo "scripts/*_selfcheck.gd matched nothing" >&2; exit 1; }
    echo "$f"
  done
}

selftest() {
  fail=0

  # 1. The table may not name a check that no longer exists — a renamed or
  #    deleted check leaves behind a weight nothing will ever look up again.
  for name in $(sed -n 's/.*"\([a-z0-9_]*\)"[[:space:]]*:.*/\1/p' "$WEIGHTS"); do
    [ -f "scripts/${name}.gd" ] \
      || { echo "::error::${WEIGHTS} weighs ${name}, which is not a scripts/*.gd — rename it or drop the entry"; fail=1; }
  done

  # 2. The partition is a partition, and an UNWEIGHED newcomer cannot land on
  #    the heaviest check. Simulated over the real glob PLUS a dummy file, which
  #    is the acceptance no live shard can demonstrate.
  { globbed; echo "scripts/zzz_brand_new_selfcheck.gd"; } | sort > "${TMP}/sc_in.$$"
  for bins in 3 5 7; do
    assign "$bins" < "${TMP}/sc_in.$$" > "${TMP}/sc_all.$$"
    i=0
    : > "${TMP}/sc_out.$$"
    while [ "$i" -lt "$bins" ]; do
      sed -n "s/^${i} //p" "${TMP}/sc_all.$$" >> "${TMP}/sc_out.$$"
      i=$((i + 1))
    done
    sort "${TMP}/sc_out.$$" > "${TMP}/sc_got.$$"
    diff -u "${TMP}/sc_in.$$" "${TMP}/sc_got.$$" \
      || { echo "::error::${bins} shards do not cover the glob exactly once"; fail=1; }
    spread=$(head -n "$bins" "${TMP}/sc_all.$$" | awk '{print $1}' | sort -u | wc -l)
    [ "$spread" -eq "$bins" ] \
      || { echo "::error::the ${bins} heaviest checks landed in ${spread} shards, not ${bins}"; fail=1; }
  done
  rm -f "${TMP}/sc_in.$$" "${TMP}/sc_all.$$" "${TMP}/sc_out.$$" "${TMP}/sc_got.$$"

  [ "$fail" -eq 0 ] || exit 1
  echo "selfcheck_shards: the table is current, and the partition holds for 3/5/7 shards"
}

case "$1" in
  --selftest) selftest ;;
  --count) globbed | wc -l | tr -d ' ' ;;
  '' | *[!0-9]*) echo "usage: sh $0 <index> <total> | --count | --selftest" >&2; exit 2 ;;
  *)
    [ -n "$2" ] || { echo "usage: sh $0 <index> <total>" >&2; exit 2; }
    globbed | assign "$2" | sed -n "s/^${1} //p"
    ;;
esac
