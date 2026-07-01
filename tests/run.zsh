#!/usr/bin/env zsh

set -u

fail() {
  print -u2 -- "not ok - $1"
  exit 1
}

ok() {
  print -- "ok - $1"
}

assert_eq() {
  local got="$1"
  local expected="$2"
  local name="$3"

  [[ "$got" == "$expected" ]] || fail "$name: expected '$expected', got '$got'"
  ok "$name"
}

assert_path_eq() {
  local got="${1:A}"
  local expected="${2:A}"
  local name="$3"

  assert_eq "$got" "$expected" "$name"
}

ROOT="${TMPDIR:-/tmp}/to-test.$$"
CONFIG="$ROOT/config"
HOME_DIR="$ROOT/home"
SEARCH_ROOT="$ROOT/search"

mkdir -p \
  "$CONFIG" \
  "$HOME_DIR/Downloads" \
  "$HOME_DIR/Projects" \
  "$SEARCH_ROOT/app/src/components" \
  "$SEARCH_ROOT/app/services/backend" \
  "$SEARCH_ROOT/app/node_modules/backend" \
  "$SEARCH_ROOT/Assignment/source" \
  "$SEARCH_ROOT/blog" \
  "$SEARCH_ROOT/workspace-school" \
  "$SEARCH_ROOT/repos/nginx/.git" \
  "$SEARCH_ROOT/other/backend"

export HOME="$HOME_DIR"
export TO_CONFIG_HOME="$CONFIG"
export TO_MAX_DEPTH=8

source "${0:A:h}/../to.plugin.zsh"

to use "$SEARCH_ROOT" >/dev/null
to --reindex >/dev/null
[[ -r "$TO_INDEX_FILE" || -r "$TO_INDEX_TSV_FILE" ]] || fail "index file was not created"
ok "reindex creates cache"

to -r "$SEARCH_ROOT" assignment
assert_path_eq "$PWD" "$SEARCH_ROOT/Assignment" "exact directory name wins over children"

cd "$ROOT" || fail "could not reset cwd"
if to -r "$SEARCH_ROOT" sign >/dev/null 2>&1; then
  fail "plain partial path fragment should be disabled by default"
fi
ok "plain partial path fragment disabled by default"

TO_SEARCH_PATH_FRAGMENTS=1
to -r "$SEARCH_ROOT" sign
assert_path_eq "$PWD" "$SEARCH_ROOT/Assignment" "plain partial path fragment can be enabled"
TO_SEARCH_PATH_FRAGMENTS=0

cd "$ROOT" || fail "could not reset cwd"
to -r "$SEARCH_ROOT" src/components
assert_path_eq "$PWD" "$SEARCH_ROOT/app/src/components" "path fragment jump"

cd "$ROOT" || fail "could not reset cwd"
to -r "$SEARCH_ROOT" app backend
assert_path_eq "$PWD" "$SEARCH_ROOT/app/services/backend" "multi-keyword jump"

cd "$ROOT" || fail "could not reset cwd"
to download
assert_path_eq "$PWD" "$HOME_DIR/Downloads" "built-in alias jump"

cd "$ROOT" || fail "could not reset cwd"
to add blog "$SEARCH_ROOT/blog" >/dev/null
to blog
assert_path_eq "$PWD" "$SEARCH_ROOT/blog" "user alias jump"

cd "$ROOT" || fail "could not reset cwd"
to workspace school "$SEARCH_ROOT/workspace-school" >/dev/null
to work school
assert_path_eq "$PWD" "$SEARCH_ROOT/workspace-school" "workspace jump"

cd "$ROOT" || fail "could not reset cwd"
to repo nginx
assert_path_eq "$PWD" "$SEARCH_ROOT/repos/nginx" "git repo jump"

: > "$TO_RECENT_FILE"
_to_record_recent "$SEARCH_ROOT/app/src/components"
cd "$ROOT" || fail "could not reset cwd"
to recent
assert_path_eq "$PWD" "$SEARCH_ROOT/app/src/components" "recent jump"

cd "$SEARCH_ROOT" || fail "could not enter search root"
to use . >/dev/null
assert_eq "$(to roots)" "${SEARCH_ROOT:A}
${HOME_DIR:A}/Projects
${HOME_DIR:A}/Downloads" "use and roots persistence"

to unuse "$SEARCH_ROOT" >/dev/null
assert_eq "$(to roots)" "${HOME_DIR:A}/Projects
${HOME_DIR:A}/Downloads" "unuse removes root"

doctor_output="$(to --doctor)"
[[ "$doctor_output" == *"to config: $CONFIG/config.zsh"* ]] || fail "doctor config path"
[[ "$doctor_output" == *"max depth: 8"* ]] || fail "doctor max depth"
[[ "$doctor_output" == *"path fragment search: 0"* ]] || fail "doctor path fragment search"
[[ "$doctor_output" == *"follow symlinks: 0"* ]] || fail "doctor follow symlinks"
[[ "$doctor_output" == *"sqlite3:"* ]] || fail "doctor sqlite status"
ok "doctor output"

print -- "all tests passed"
