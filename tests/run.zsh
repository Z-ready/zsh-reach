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
  "$SEARCH_ROOT/stale-cache" \
  "$SEARCH_ROOT/reindex-stale" \
  "$SEARCH_ROOT/workspace-school" \
  "$SEARCH_ROOT/repos/nginx/.git" \
  "$SEARCH_ROOT/other/backend"

export HOME="$HOME_DIR"
export TO_CONFIG_HOME="$CONFIG"
export TO_MAX_DEPTH=8

TO_ROOTS=("$HOME_DIR")
source "${0:A:h}/../to.plugin.zsh"
assert_eq "$(to roots)" "${HOME_DIR:A}/Projects
${HOME_DIR:A}/Downloads" "source ignores stale in-shell roots"
assert_eq "$TO_WATCH_DEBOUNCE" "2" "watch debounce default"
assert_eq "$TO_AI_RANK_COMMAND" "" "ai rank command default"

to use "$SEARCH_ROOT" >/dev/null

# Regression: sqlite reindex must run in a single active transaction; a split
# begin/import/commit across processes emits "cannot commit - no transaction".
reindex_errors="$(to --reindex 2>&1 >/dev/null)"
[[ "$reindex_errors" != *"cannot commit"* && "$reindex_errors" != *"Error:"* ]] \
  || fail "reindex emitted sqlite error: $reindex_errors"
ok "reindex runs without sqlite errors"

[[ -r "$TO_INDEX_FILE" || -r "$TO_INDEX_TSV_FILE" ]] || fail "index file was not created"
ok "reindex creates cache"

# Regression: fd emits absolute paths, so indexed paths must not be re-prefixed
# with the root (which produced doubled, non-existent paths).
indexed_assignment="$(_to_index_query exact assignment)"
assert_path_eq "$indexed_assignment" "$SEARCH_ROOT/Assignment" "index stores un-doubled paths"
while IFS= read -r indexed_path; do
  [[ -z "$indexed_path" || -d "$indexed_path" ]] \
    || fail "index contains a non-existent (doubled?) path: $indexed_path"
done < <(_to_index_query path "$SEARCH_ROOT")
ok "all indexed paths exist"

if command -v sqlite3 >/dev/null 2>&1 && [[ -r "$TO_INDEX_FILE" ]]; then
  token_count="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from tokens where token = 'backend';")"
  (( token_count >= 1 )) || fail "backend token was not indexed"
  ok "reindex creates token index"
  dir_id_count="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from dirs where id is not null;")"
  (( dir_id_count >= 1 )) || fail "dirs.id was not populated"
  token_dir_id_count="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from tokens where dir_id is not null;")"
  (( token_dir_id_count >= 1 )) || fail "tokens.dir_id was not populated"
  ok "index uses dir ids for tokens"

  root_meta_count="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from roots where path = '${SEARCH_ROOT:A}';")"
  assert_eq "$root_meta_count" "1" "reindex records root metadata"
  root_config_key="$(sqlite3 "$TO_INDEX_FILE" "select config_key from roots where path = '${SEARCH_ROOT:A}';")"
  [[ "$root_config_key" == *"depth=$TO_MAX_DEPTH"* ]] || fail "root metadata did not record config key"
  ok "reindex records root config metadata"

  second_reindex_output="$(to --reindex 2>&1)"
  [[ "$second_reindex_output" == *"skipped"* ]] || fail "fresh reindex did not skip roots: $second_reindex_output"
  ok "fresh roots are skipped during incremental reindex"

  old_max_depth="$TO_MAX_DEPTH"
  TO_MAX_DEPTH=7
  config_reindex_output="$(to --reindex 2>&1)"
  [[ "$config_reindex_output" == *"indexed"* ]] || fail "config change did not refresh roots: $config_reindex_output"
  TO_MAX_DEPTH="$old_max_depth"
  ok "index config changes refresh roots"

  sleep 1
  mkdir -p "$SEARCH_ROOT/incremental-target"
  touch "$SEARCH_ROOT"
  incremental_reindex_output="$(to --reindex 2>&1)"
  [[ "$incremental_reindex_output" == *"indexed"* ]] || fail "changed root was not reindexed: $incremental_reindex_output"
  incremental_match="$(_to_index_query exact incremental-target)"
  assert_path_eq "$incremental_match" "$SEARCH_ROOT/incremental-target" "changed root refresh indexes new directories"

  rmdir "$SEARCH_ROOT/reindex-stale" || fail "could not remove reindex-stale fixture"
  sleep 1
  touch "$SEARCH_ROOT"
  to --reindex >/dev/null 2>&1
  reindex_stale_path="${SEARCH_ROOT:A}/reindex-stale"
  reindex_stale_count="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from dirs where path = '$reindex_stale_path';")"
  assert_eq "$reindex_stale_count" "0" "changed root refresh removes stale directories"

  fake_helper="$ROOT/to-helper"
  helper_log="$ROOT/helper.log"
  cat > "$fake_helper" <<'EOF'
#!/usr/bin/env zsh
print -r -- "$*" >> "$TO_FAKE_HELPER_LOG"
print -r -- "$TO_FAKE_HELPER_TARGET"
EOF
  chmod +x "$fake_helper"
  old_helper="$TO_HELPER"
  export TO_FAKE_HELPER_LOG="$helper_log"
  export TO_FAKE_HELPER_TARGET="${SEARCH_ROOT:A}/Assignment"
  TO_HELPER="$fake_helper"
  helper_match="$(_to_index_query exact assignment)"
  assert_path_eq "$helper_match" "$SEARCH_ROOT/Assignment" "sqlite query can use helper"
  [[ -s "$helper_log" ]] || fail "helper was not invoked"
  TO_HELPER="$old_helper"
fi

rmdir "$SEARCH_ROOT/stale-cache" || fail "could not remove stale-cache fixture"
stale_matches="$(_to_index_query exact stale-cache)"
assert_eq "$stale_matches" "" "stale index paths are filtered"
if command -v sqlite3 >/dev/null 2>&1 && [[ -r "$TO_INDEX_FILE" ]]; then
  stale_path="${SEARCH_ROOT:A}/stale-cache"
  stale_count="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from dirs where path = '$stale_path';")"
  assert_eq "$stale_count" "0" "stale sqlite row is deleted"
fi

mkdir -p "$SEARCH_ROOT/new-cache-target"
cd "$ROOT" || fail "could not reset cwd"
to -r "$SEARCH_ROOT" new-cache-target
assert_path_eq "$PWD" "$SEARCH_ROOT/new-cache-target" "fallback search finds new directory"
if command -v sqlite3 >/dev/null 2>&1 && [[ -r "$TO_INDEX_FILE" ]]; then
  cached_path="${SEARCH_ROOT:A}/new-cache-target"
  cached_count="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from dirs where path = '$cached_path';")"
  assert_eq "$cached_count" "1" "fallback result is written to sqlite"
  cached_token_count="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from tokens t join dirs d on d.id = t.dir_id where d.path = '$cached_path' and t.token = 'cache';")"
  assert_eq "$cached_token_count" "1" "fallback result tokens are written to sqlite"
fi

cd "$ROOT" || fail "could not reset cwd"
to -r "$SEARCH_ROOT" assignment
assert_path_eq "$PWD" "$SEARCH_ROOT/Assignment" "exact directory name wins over children"
if command -v sqlite3 >/dev/null 2>&1 && [[ -r "$TO_INDEX_FILE" ]]; then
  assignment_path="${SEARCH_ROOT:A}/Assignment"
  assignment_hits="$(sqlite3 "$TO_INDEX_FILE" "select hit_count from dirs where path = '$assignment_path';")"
  (( assignment_hits >= 1 )) || fail "hit_count was not updated for Assignment"
  ok "successful jump updates hit_count"
fi

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
if command -v sqlite3 >/dev/null 2>&1 && [[ -r "$TO_INDEX_FILE" ]]; then
  token_match="$(_to_index_query token app backend | head -n 1)"
  assert_path_eq "$token_match" "$SEARCH_ROOT/app/services/backend" "multi-keyword query uses token index"
fi

AI_RANKER="$ROOT/ai-ranker"
cat > "$AI_RANKER" <<'EOF'
#!/usr/bin/env zsh
awk 'NR == 1 { first = $0; next } NR == 2 { print; print first; next } { print }'
EOF
chmod +x "$AI_RANKER"
old_ai_rank_command="$TO_AI_RANK_COMMAND"
TO_AI_RANK_COMMAND="$AI_RANKER"
ranked_backend=("${(@f)$(printf '%s\n' "$SEARCH_ROOT/app/services/backend" "$SEARCH_ROOT/other/backend" | _to_rank_matches backend)}")
assert_path_eq "$ranked_backend[1]" "$SEARCH_ROOT/other/backend" "ai rank hook can reorder candidates"
TO_AI_RANK_COMMAND="$old_ai_rank_command"

cd "$ROOT" || fail "could not reset cwd"
to download
assert_path_eq "$PWD" "$HOME_DIR/Downloads" "built-in alias jump"

cd "$ROOT" || fail "could not reset cwd"
to add blog "$SEARCH_ROOT/blog" >/dev/null
to blog
assert_path_eq "$PWD" "$SEARCH_ROOT/blog" "user alias jump"
if command -v sqlite3 >/dev/null 2>&1 && [[ -r "$TO_INDEX_FILE" ]]; then
  alias_path="$(sqlite3 "$TO_INDEX_FILE" "select path from aliases where name = 'blog';")"
  assert_path_eq "$alias_path" "$SEARCH_ROOT/blog" "user alias is stored in sqlite"
fi

cd "$ROOT" || fail "could not reset cwd"
to workspace school "$SEARCH_ROOT/workspace-school" >/dev/null
to work school
assert_path_eq "$PWD" "$SEARCH_ROOT/workspace-school" "workspace jump"
if command -v sqlite3 >/dev/null 2>&1 && [[ -r "$TO_INDEX_FILE" ]]; then
  workspace_path="$(sqlite3 "$TO_INDEX_FILE" "select path from workspaces where name = 'school';")"
  assert_path_eq "$workspace_path" "$SEARCH_ROOT/workspace-school" "workspace is stored in sqlite"
fi

cd "$ROOT" || fail "could not reset cwd"
to repo nginx
assert_path_eq "$PWD" "$SEARCH_ROOT/repos/nginx" "git repo jump"
if command -v sqlite3 >/dev/null 2>&1 && [[ -r "$TO_INDEX_FILE" ]]; then
  repo_match="$(_to_index_query git nginx | head -n 1)"
  assert_path_eq "$repo_match" "$SEARCH_ROOT/repos/nginx" "git repo query uses token index"
fi
missing_repo_output="$(to repo missing-repo 2>&1 >/dev/null)"
[[ "$missing_repo_output" == *"no matching Git repository"* ]] || fail "missing repo did not explain failure: $missing_repo_output"
ok "missing git repo reports no match"

: > "$TO_RECENT_FILE"
if command -v sqlite3 >/dev/null 2>&1 && [[ -r "$TO_INDEX_FILE" ]]; then
  sqlite3 "$TO_INDEX_FILE" "delete from recent;" >/dev/null
fi
_to_record_recent "$SEARCH_ROOT/app/src/components"
cd "$ROOT" || fail "could not reset cwd"
to recent
assert_path_eq "$PWD" "$SEARCH_ROOT/app/src/components" "recent jump"
if command -v sqlite3 >/dev/null 2>&1 && [[ -r "$TO_INDEX_FILE" ]]; then
  recent_path="$(sqlite3 "$TO_INDEX_FILE" "select path from recent order by last_used desc, rowid desc limit 1;")"
  assert_path_eq "$recent_path" "$SEARCH_ROOT/app/src/components" "recent destination is stored in sqlite"
fi

cd "$ROOT" || fail "could not reset cwd"
missing_dir_output="$(to does-not-exist-here 2>&1 >/dev/null)"
[[ "$missing_dir_output" == *"no matching directory"* ]] || fail "missing directory did not explain failure: $missing_dir_output"
ok "missing directory reports no match"

cd "$SEARCH_ROOT" || fail "could not enter search root"
to use . >/dev/null
assert_eq "$(to roots)" "${SEARCH_ROOT:A}
${HOME_DIR:A}/Projects
${HOME_DIR:A}/Downloads" "use and roots persistence"

to unuse "$SEARCH_ROOT" >/dev/null
assert_eq "$(to roots)" "${HOME_DIR:A}/Projects
${HOME_DIR:A}/Downloads" "unuse removes root"

WATCH_BIN="$ROOT/watch-bin"
mkdir -p "$WATCH_BIN"
cat > "$WATCH_BIN/fswatch" <<'EOF'
#!/usr/bin/env zsh
exit 0
EOF
chmod +x "$WATCH_BIN/fswatch"
OLD_PATH="$PATH"
PATH="$WATCH_BIN:$PATH"
assert_eq "$(_to_watch_backend)" "fswatch" "watcher detects fswatch"
PATH="$OLD_PATH"

doctor_output="$(to --doctor)"
[[ "$doctor_output" == *"to config: $CONFIG/config.zsh"* ]] || fail "doctor config path"
[[ "$doctor_output" == *"max depth: 8"* ]] || fail "doctor max depth"
[[ "$doctor_output" == *"path fragment search: 0"* ]] || fail "doctor path fragment search"
[[ "$doctor_output" == *"follow symlinks: 0"* ]] || fail "doctor follow symlinks"
[[ "$doctor_output" == *"watch debounce: 2"* ]] || fail "doctor watch debounce"
[[ "$doctor_output" == *"watcher:"* ]] || fail "doctor watcher status"
[[ "$doctor_output" == *"sqlite3:"* ]] || fail "doctor sqlite status"
[[ "$doctor_output" == *"ai rank command:"* ]] || fail "doctor ai rank command status"
ok "doctor output"

print -- "all tests passed"
