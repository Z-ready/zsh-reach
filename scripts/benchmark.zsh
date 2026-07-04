#!/usr/bin/env zsh
set -euo pipefail

ROOT="${REACH_BENCH_ROOT:-${TMPDIR:-/tmp}/reach-bench}"
COUNT="${REACH_BENCH_COUNT:-100000}"
CONFIG="${REACH_BENCH_CONFIG:-${TMPDIR:-/tmp}/reach-bench-config}"
PLUGIN="${REACH_BENCH_PLUGIN:-${0:A:h:h}/to.plugin.zsh}"

make_tree() {
  local i shard project dir

  mkdir -p "$ROOT" "$CONFIG"
  i=1
  while (( i <= COUNT )); do
    shard=$(( i / 1000 ))
    project="project-$i"
    dir="$ROOT/shard-$shard/$project/src/module-$(( i % 97 ))"
    mkdir -p "$dir"
    if (( i % 5000 == 0 )); then
      mkdir -p "$ROOT/repos/$project/.git"
    fi
    (( ++i ))
  done
}

elapsed_ms() {
  local start="$1"
  local end="$2"
  print -r -- "$(( (end - start) / 1000000 ))"
}

run_reach() {
  REACH_CONFIG_HOME="$CONFIG" TO_CONFIG_HOME="$CONFIG" zsh -fc '
    source "$1"
    shift
    gt "$@"
  ' zsh "$PLUGIN" "$@"
}

print "reach benchmark"
print "root: $ROOT"
print "entries target: $COUNT"
make_tree

run_reach use "$ROOT" >/dev/null

start="$(date +%s%N)"
run_reach --reindex >/dev/null
end="$(date +%s%N)"
print "cold reindex ms: $(elapsed_ms "$start" "$end")"

start="$(date +%s%N)"
repeat 50 run_reach "project-99999" >/dev/null
end="$(date +%s%N)"
print "cached query p50 proxy ms: $(( $(elapsed_ms "$start" "$end") / 50 ))"

success_file="$CONFIG/concurrent-success"
: > "$success_file"
repeat 20 {
  (
    run_reach "project-$(( RANDOM % COUNT + 1 ))" >/dev/null \
      && print ok >> "$success_file"
  ) &
}
wait
print "concurrent writes ok: $(wc -l < "$success_file" | tr -d ' ') / 20"
