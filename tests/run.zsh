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

sql_quote() {
  local value="${1//\'/\'\'}"
  print -r -- "'$value'"
}

ROOT="${TMPDIR:-/tmp}/to-test.$$"
CONFIG="$ROOT/config"
HOME_DIR="$ROOT/home"
SEARCH_ROOT="$ROOT/search"
TEST_DIR="${0:A:h}"
export TO_HELPER="$TEST_DIR/../target/release/reach-helper"

mkdir -p \
  "$CONFIG" \
  "$HOME_DIR/Downloads" \
  "$HOME_DIR/any shelf" \
  "$HOME_DIR/Pictures/头像" \
  "$HOME_DIR/Random Shelf/lightroom" \
  "$HOME_DIR/i" \
  "$ROOT/empty-root" \
  "$ROOT/external-parent/external-target" \
  "$SEARCH_ROOT/app/src/components" \
  "$SEARCH_ROOT/app/services/backend" \
  "$SEARCH_ROOT/app/node_modules/backend" \
  "$SEARCH_ROOT/Assignment/source" \
  "$SEARCH_ROOT/docs/README" \
  "$SEARCH_ROOT/docs/assets" \
  "$SEARCH_ROOT/media/audio" \
  "$SEARCH_ROOT/media/photos" \
  "$SEARCH_ROOT/media/space names" \
  "$SEARCH_ROOT/blog" \
  "$SEARCH_ROOT/projects/rust/tokio-tool/src" \
  "$SEARCH_ROOT/projects/node/react-panel/src" \
  "$SEARCH_ROOT/projects/python/fastapi-service/app" \
  "$SEARCH_ROOT/projects/docker/nginx-stack" \
  "$SEARCH_ROOT/projects/code/auth-module/lib" \
  "$SEARCH_ROOT/gh/issues/issue-42-login" \
  "$SEARCH_ROOT/gh/pulls/pull-77-docs" \
  "$SEARCH_ROOT/stale-cache" \
  "$SEARCH_ROOT/reindex-stale" \
  "$SEARCH_ROOT/moved-before" \
  "$SEARCH_ROOT/Space Dir/child target" \
  "$SEARCH_ROOT/unicode/naïve-café" \
  "$SEARCH_ROOT/workspace-school" \
  "$SEARCH_ROOT/repos/nginx/.git" \
  "$SEARCH_ROOT/repos/ai-template/.git" \
  "$SEARCH_ROOT/repos/openai-api/.git" \
  "$SEARCH_ROOT/repos/openai-api/src/plugin/test" \
  "$SEARCH_ROOT/history/hot-target" \
  "$SEARCH_ROOT/history/cold-target" \
  "$SEARCH_ROOT/history/hot-file" \
  "$SEARCH_ROOT/history/cold-file" \
  "$SEARCH_ROOT/other/backend"

touch \
  "$SEARCH_ROOT/history/hot-file/project spec.md" \
  "$SEARCH_ROOT/history/cold-file/project spec.md" \
  "$SEARCH_ROOT/history/hot-file/音乐 mix.mp3"

cat > "$SEARCH_ROOT/projects/rust/tokio-tool/Cargo.toml" <<'EOF'
[package]
name = "tokio-tool"
version = "0.1.0"

[dependencies]
tokio = "1"
EOF

cat > "$SEARCH_ROOT/projects/node/react-panel/package.json" <<'EOF'
{"name":"react-panel","dependencies":{"react":"latest"}}
EOF

cat > "$SEARCH_ROOT/projects/python/fastapi-service/pyproject.toml" <<'EOF'
[project]
name = "fastapi-service"
dependencies = ["fastapi"]
EOF

cat > "$SEARCH_ROOT/projects/docker/nginx-stack/Dockerfile" <<'EOF'
FROM nginx:alpine
EOF

cat > "$SEARCH_ROOT/projects/code/auth-module/lib/auth.zsh" <<'EOF'
authenticate_user() {
  print auth
}
EOF

export HOME="$HOME_DIR"
export TO_CONFIG_HOME="$CONFIG"
export TO_MAX_DEPTH=8
cat > "$CONFIG/config.zsh" <<'EOF'
TO_MAX_DEPTH=bad
TO_INTERACTIVE_THRESHOLD=bad
TO_SEARCH_PATH_FRAGMENTS=bad
TO_FOLLOW_SYMLINKS=bad
TO_ROOT_MODE=bad
TO_WATCH_DEBOUNCE=bad
TO_FRECENCY=bad
TO_FRECENCY_THRESHOLD=bad
EOF

TO_ROOTS=("$HOME_DIR")
source "$TEST_DIR/../to.plugin.zsh"
assert_eq "$TO_MAX_DEPTH" "8" "invalid config max depth falls back to default"
assert_eq "$TO_INTERACTIVE_THRESHOLD" "3" "invalid config interactive threshold falls back to default"
assert_eq "$TO_SEARCH_PATH_FRAGMENTS" "0" "invalid config path fragment setting falls back to default"
assert_eq "$TO_FOLLOW_SYMLINKS" "0" "invalid config symlink setting falls back to default"
assert_eq "$TO_ROOT_MODE" "home" "invalid root mode falls back to home"
assert_eq "$TO_WATCH_DEBOUNCE" "2" "invalid config watch debounce falls back to default"
assert_eq "$TO_AUTOWATCH" "0" "invalid config autowatch falls back to default"
assert_eq "$TO_AUTO_ADD_ROOTS" "0" "invalid config auto add roots falls back to default"
assert_eq "$TO_FRECENCY" "1" "invalid config frecency falls back to default"
assert_eq "$TO_FRECENCY_THRESHOLD" "1" "invalid config frecency threshold falls back to default"
assert_eq "$(gt --version)" "reach 1.6.0" "default gt version output"
assert_eq "$(to --version)" "reach 1.6.0" "legacy to version output"
assert_eq "$(to roots)" "${HOME_DIR:A}" "source ignores stale in-shell roots"
assert_eq "$TO_WATCH_DEBOUNCE" "2" "watch debounce default"
assert_eq "$TO_AI_RANK_COMMAND" "" "ai rank command default"
assert_eq "$(_to_unique_existing_dirs "$HOME_DIR/any shelf" "$HOME_DIR")" "${HOME_DIR:A}" "broader roots prune descendants"
assert_eq "$(_to_unique_existing_dirs "$HOME_DIR" "$HOME_DIR/any shelf")" "${HOME_DIR:A}" "descendant roots are redundant after broader roots"

EXPLICIT_ROOT="$ROOT/explicit-root"
EXPLICIT_CONFIG="$ROOT/explicit-config"
mkdir -p "$EXPLICIT_ROOT/only-target" "$HOME_DIR/home-only-target" "$EXPLICIT_CONFIG"
{
  print -r -- "TO_ROOT_MODE=explicit"
  printf 'TO_ROOTS=(%q)\n' "$EXPLICIT_ROOT"
} > "$EXPLICIT_CONFIG/config.zsh"
explicit_roots="$(
  HOME="$HOME_DIR" TO_CONFIG_HOME="$EXPLICIT_CONFIG" zsh -fc '
    source "$1"
    to roots
  ' zsh "$TEST_DIR/../to.plugin.zsh"
)"
assert_eq "$explicit_roots" "${EXPLICIT_ROOT:A}" "explicit root mode omits home"
explicit_jump="$(
  HOME="$HOME_DIR" TO_CONFIG_HOME="$EXPLICIT_CONFIG" zsh -fc '
    source "$1"
    cd "$2" || exit 1
    to only-target >/dev/null || exit 1
    print -r -- "$PWD"
  ' zsh "$TEST_DIR/../to.plugin.zsh" "$ROOT"
)"
assert_path_eq "$explicit_jump" "$EXPLICIT_ROOT/only-target" "explicit root mode searches configured roots"
explicit_miss="$(
  HOME="$HOME_DIR" TO_CONFIG_HOME="$EXPLICIT_CONFIG" zsh -fc '
    source "$1"
    to home-only-target
  ' zsh "$TEST_DIR/../to.plugin.zsh" 2>&1 >/dev/null
)"
[[ "$explicit_miss" == *"searched explicit roots"* && "$explicit_miss" == *"${EXPLICIT_ROOT:A}"* ]] \
  || fail "explicit root miss did not describe searched roots: $explicit_miss"
ok "explicit root mode reports searched roots"

broad_root_output="$(to use / 2>&1 >/dev/null || true)"
[[ "$broad_root_output" == *"refusing broad system root"* ]] || fail "broad root was not refused: $broad_root_output"
ok "broad system roots are refused"

STAT_BIN="$ROOT/stat-bin"
mkdir -p "$STAT_BIN"
cat > "$STAT_BIN/stat" <<'EOF'
#!/usr/bin/env zsh
if [[ "$1" == "-f" ]]; then
  print -r -- /
else
  print -r -- 1234567890
fi
EOF
chmod +x "$STAT_BIN/stat"
OLD_PATH="$PATH"
PATH="$STAT_BIN:$PATH"
assert_eq "$(_to_root_mtime "$SEARCH_ROOT")" "1234567890" "linux stat mount output falls back to mtime"
PATH="$OLD_PATH"

DATE_FAIL_BIN="$ROOT/date-fail-bin"
mkdir -p "$DATE_FAIL_BIN"
cat > "$DATE_FAIL_BIN/date" <<'EOF'
#!/usr/bin/env zsh
exit 1
EOF
chmod +x "$DATE_FAIL_BIN/date"
OLD_PATH="$PATH"
PATH="$DATE_FAIL_BIN:$PATH"
if _to_now >/dev/null 2>&1; then
  fail "_to_now should fail when date fails"
fi
TIME_FAIL_CONFIG="$ROOT/time-failure-config"
TIME_FAIL_HOME="$ROOT/time-failure-home"
mkdir -p "$TIME_FAIL_CONFIG" "$TIME_FAIL_HOME/no-frecency"
time_failure_frecency="$(
  HOME="$TIME_FAIL_HOME" \
  TO_CONFIG_HOME="$TIME_FAIL_CONFIG" \
  TO_HELPER="$TO_HELPER" \
  PATH="$DATE_FAIL_BIN:$OLD_PATH" \
  zsh -fc '
    source "$1"
    _to_index_ensure_sqlite_schema >/dev/null || exit 1
    _to_record_frecency "$HOME/no-frecency"
    "$TO_HELPER" frecency-query --db "$TO_INDEX_FILE" --threshold 0 --now 999999 -- no-frecency 2>/dev/null
  ' zsh "$TEST_DIR/../to.plugin.zsh"
)"
assert_eq "$time_failure_frecency" "" "time failure skips frecency write"
PATH="$OLD_PATH"
ok "_to_now reports failure instead of epoch zero"

if to -r "$ROOT/empty-root" no-state-match >/dev/null 2>&1; then
  fail "empty root should not resolve missing directory"
fi
[[ ! -e "$TO_INDEX_FILE" ]] || fail "alias/workspace miss should not create sqlite index"
ok "state lookup stays lazy before index exists"

cd "$ROOT" || fail "could not reset cwd"
to 头像
assert_path_eq "$PWD" "$HOME_DIR/Pictures/头像" "default roots include Pictures"

cd "$ROOT" || fail "could not reset cwd"
to lightroom
assert_path_eq "$PWD" "$HOME_DIR/Random Shelf/lightroom" "default root searches arbitrary home subdirectories"

mkdir -p "$HOME_DIR/fresh-home-target"
cd "$ROOT" || fail "could not reset cwd"
to fresh-home-target
assert_path_eq "$PWD" "$HOME_DIR/fresh-home-target" "fallback finds new directory under home"
if command -v sqlite3 >/dev/null 2>&1 && [[ -r "$TO_INDEX_FILE" ]]; then
  fresh_home_path="${HOME_DIR:A}/fresh-home-target"
  fresh_home_count="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from dirs where path = $(sql_quote "$fresh_home_path");")"
  assert_eq "$fresh_home_count" "1" "fallback caches new home directory"
  fresh_home_cached="$(_to_index_query exact fresh-home-target)"
  assert_path_eq "$fresh_home_cached" "$HOME_DIR/fresh-home-target" "cached home directory is found without fallback"
fi

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

  root_meta_count="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from roots where path = $(sql_quote "${SEARCH_ROOT:A}");")"
  assert_eq "$root_meta_count" "1" "reindex records root metadata"
  root_config_key="$(sqlite3 "$TO_INDEX_FILE" "select config_key from roots where path = $(sql_quote "${SEARCH_ROOT:A}");")"
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
  reindex_stale_count="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from dirs where path = $(sql_quote "$reindex_stale_path");")"
  assert_eq "$reindex_stale_count" "0" "changed root refresh removes stale directories"

  mv "$SEARCH_ROOT/moved-before" "$SEARCH_ROOT/moved-after" || fail "could not move indexed fixture"
  sleep 1
  touch "$SEARCH_ROOT"
  to --reindex >/dev/null 2>&1
  moved_before_count="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from dirs where path = $(sql_quote "${SEARCH_ROOT:A}/moved-before");")"
  moved_after_count="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from dirs where path = $(sql_quote "${SEARCH_ROOT:A}/moved-after");")"
  assert_eq "$moved_before_count" "0" "changed root refresh removes moved source"
  assert_eq "$moved_after_count" "1" "changed root refresh indexes moved destination"

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

  hot_target="${SEARCH_ROOT:A}/history/hot-target"
  cold_target="${SEARCH_ROOT:A}/history/cold-target"
  now="$(_to_now)"
  sqlite3 "$TO_INDEX_FILE" >/dev/null <<SQL
insert or replace into history(path, visits, last_used) values($(sql_quote "$hot_target"), 4, $now);
insert or replace into history(path, visits, last_used) values($(sql_quote "$cold_target"), 1, $(( now - 1209600 )));
update dirs set last_used = $now + 10, hit_count = 20 where path = $(sql_quote "$cold_target");
update dirs set last_used = 1, hit_count = 1 where path = $(sql_quote "$hot_target");
SQL
  frecency_match="$(_to_frecency_query_sqlite TO_ROOTS hot-target | head -n 1)"
  assert_path_eq "$frecency_match" "$SEARCH_ROOT/history/hot-target" "frecency query returns visited directory"
  cd "$ROOT" || fail "could not reset cwd"
  to -r "$SEARCH_ROOT" hot-target
  assert_path_eq "$PWD" "$SEARCH_ROOT/history/hot-target" "frecency jump runs before index and fallback"

  mkdir -p "$SEARCH_ROOT/history/preferred/target" "$SEARCH_ROOT/history/indexed/target"
  preferred_target="${SEARCH_ROOT:A}/history/preferred/target"
  indexed_target="${SEARCH_ROOT:A}/history/indexed/target"
  _to_index_upsert_dir "$preferred_target"
  _to_index_upsert_dir "$indexed_target"
  now="$(_to_now)"
  sqlite3 "$TO_INDEX_FILE" >/dev/null <<SQL
insert or replace into history(path, visits, last_used) values($(sql_quote "$preferred_target"), 3, $now);
insert or replace into history(path, visits, last_used) values($(sql_quote "$indexed_target"), 1, $(( now - 1209600 )));
update dirs set last_used = 1, hit_count = 1 where path = $(sql_quote "$preferred_target");
update dirs set last_used = $now + 10, hit_count = 20 where path = $(sql_quote "$indexed_target");
SQL
  cd "$ROOT" || fail "could not reset cwd"
  to -r "$SEARCH_ROOT" target
  assert_path_eq "$PWD" "$SEARCH_ROOT/history/preferred/target" "frecency ranks same-name directories before index ranking"
  sqlite3 "$TO_INDEX_FILE" >/dev/null <<SQL
update dirs set last_used = 1, hit_count = 1 where path = $(sql_quote "$preferred_target");
update dirs set last_used = $now + 10, hit_count = 20 where path = $(sql_quote "$indexed_target");
SQL
  TO_FRECENCY=0
  cd "$ROOT" || fail "could not reset cwd"
  to -r "$SEARCH_ROOT" target
  assert_path_eq "$PWD" "$SEARCH_ROOT/history/indexed/target" "disabling frecency restores index ranking"
  TO_FRECENCY=1

  hot_file_parent="${SEARCH_ROOT:A}/history/hot-file"
  cold_file_parent="${SEARCH_ROOT:A}/history/cold-file"
  now="$(_to_now)"
  sqlite3 "$TO_INDEX_FILE" >/dev/null <<SQL
insert or replace into history(path, visits, last_used) values($(sql_quote "$hot_file_parent"), 5, $now);
insert or replace into history(path, visits, last_used) values($(sql_quote "$cold_file_parent"), 1, $(( now - 1209600 )));
update dirs set last_used = 1, hit_count = 1 where path = $(sql_quote "$hot_file_parent");
update dirs set last_used = $now + 10, hit_count = 20 where path = $(sql_quote "$cold_file_parent");
SQL
  cd "$ROOT" || fail "could not reset cwd"
  to -r "$SEARCH_ROOT" "project spec.md"
  assert_path_eq "$PWD" "$SEARCH_ROOT/history/hot-file" "file-name jump ranks containing directories by frecency"
  history_after_file="$(sqlite3 "$TO_INDEX_FILE" "select visits from history where path = $(sql_quote "$hot_file_parent");")"
  (( history_after_file >= 6 )) || fail "file-name jump did not update frecency history"
  ok "file-name jump updates frecency history"

  cd "$ROOT" || fail "could not reset cwd"
  to -r "$SEARCH_ROOT" "音乐 mix.mp3"
  assert_path_eq "$PWD" "$SEARCH_ROOT/history/hot-file" "unicode and space file-name jump works with frecency"

  old_only="${SEARCH_ROOT:A}/history/old-only"
  mkdir -p "$old_only"
  _to_index_upsert_dir "$old_only"
  sqlite3 "$TO_INDEX_FILE" "insert or replace into history(path, visits, last_used) values($(sql_quote "$old_only"), 1, $(( now - 1209600 )));" >/dev/null
  old_history_match="$(_to_frecency_query_sqlite TO_ROOTS old-only)"
  assert_eq "$old_history_match" "" "old low-score history falls below frecency threshold"
fi

rmdir "$SEARCH_ROOT/stale-cache" || fail "could not remove stale-cache fixture"
stale_matches="$(_to_index_query exact stale-cache)"
assert_eq "$stale_matches" "" "stale index paths are filtered"
if command -v sqlite3 >/dev/null 2>&1 && [[ -r "$TO_INDEX_FILE" ]]; then
  stale_path="${SEARCH_ROOT:A}/stale-cache"
  stale_count="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from dirs where path = $(sql_quote "$stale_path");")"
  assert_eq "$stale_count" "0" "stale sqlite row is deleted"
fi

mkdir -p "$SEARCH_ROOT/new-cache-target"
cd "$ROOT" || fail "could not reset cwd"
to -r "$SEARCH_ROOT" new-cache-target
assert_path_eq "$PWD" "$SEARCH_ROOT/new-cache-target" "fallback search finds new directory"
if command -v sqlite3 >/dev/null 2>&1 && [[ -r "$TO_INDEX_FILE" ]]; then
  cached_path="${SEARCH_ROOT:A}/new-cache-target"
  cached_count="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from dirs where path = $(sql_quote "$cached_path");")"
  assert_eq "$cached_count" "1" "fallback result is written to sqlite"
  cached_token_count="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from tokens t join dirs d on d.id = t.dir_id where d.path = $(sql_quote "$cached_path") and t.token = 'cache';")"
  assert_eq "$cached_token_count" "1" "fallback result tokens are written to sqlite"
fi

cd "$ROOT" || fail "could not reset cwd"
to -r "$SEARCH_ROOT" assignment
assert_path_eq "$PWD" "$SEARCH_ROOT/Assignment" "exact directory name wins over children"
if command -v sqlite3 >/dev/null 2>&1 && [[ -r "$TO_INDEX_FILE" ]]; then
  assignment_path="${SEARCH_ROOT:A}/Assignment"
  assignment_hits="$(sqlite3 "$TO_INDEX_FILE" "select hit_count from dirs where path = $(sql_quote "$assignment_path");")"
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
to -r "$SEARCH_ROOT" "child target"
assert_path_eq "$PWD" "$SEARCH_ROOT/Space Dir/child target" "space-containing path jump"

cd "$ROOT" || fail "could not reset cwd"
to -r "$SEARCH_ROOT" naïve-café
assert_path_eq "$PWD" "$SEARCH_ROOT/unicode/naïve-café" "unicode path jump"

cd "$ROOT" || fail "could not reset cwd"
to -r "$SEARCH_ROOT" app backend
assert_path_eq "$PWD" "$SEARCH_ROOT/app/services/backend" "multi-keyword jump"
if command -v sqlite3 >/dev/null 2>&1 && [[ -r "$TO_INDEX_FILE" ]]; then
  token_match="$(_to_index_query token app backend | head -n 1)"
  assert_path_eq "$token_match" "$SEARCH_ROOT/app/services/backend" "multi-keyword query uses token index"
fi

touch "$SEARCH_ROOT/app/services/backend/settings.toml" "$SEARCH_ROOT/other/backend/settings.toml"
cd "$ROOT" || fail "could not reset cwd"
to -r "$SEARCH_ROOT" settings.toml
assert_path_eq "$PWD" "$SEARCH_ROOT/app/services/backend" "file-name jump prefers recently used containing directory"
if command -v sqlite3 >/dev/null 2>&1 && [[ -r "$TO_INDEX_FILE" ]]; then
  file_parent_count="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from dirs where path = $(sql_quote "${SEARCH_ROOT:A}/app/services/backend");")"
  assert_eq "$file_parent_count" "1" "file-name jump caches containing directory"
fi

touch \
  "$SEARCH_ROOT/docs/Guide.md" \
  "$SEARCH_ROOT/docs/assets/README.md" \
  "$SEARCH_ROOT/media/audio/音乐.mp3" \
  "$SEARCH_ROOT/media/photos/证件照.jpg" \
  "$SEARCH_ROOT/media/space names/cover photo.jpg"

cd "$ROOT" || fail "could not reset cwd"
to -r "$SEARCH_ROOT" README
assert_path_eq "$PWD" "$SEARCH_ROOT/docs/README" "plain query prefers directory over file stem"

cd "$ROOT" || fail "could not reset cwd"
to -r "$SEARCH_ROOT" README.md
assert_path_eq "$PWD" "$SEARCH_ROOT/docs/assets" "extension query jumps to containing directory"

cd "$ROOT" || fail "could not reset cwd"
to -r "$SEARCH_ROOT" Guide
assert_path_eq "$PWD" "$SEARCH_ROOT/docs" "plain query falls back to matching file stem"

cd "$ROOT" || fail "could not reset cwd"
to -r "$SEARCH_ROOT" 音乐
assert_path_eq "$PWD" "$SEARCH_ROOT/media/audio" "unicode file stem jump"

cd "$ROOT" || fail "could not reset cwd"
to -r "$SEARCH_ROOT" 证件照.jpg
assert_path_eq "$PWD" "$SEARCH_ROOT/media/photos" "unicode extension file jump"

cd "$ROOT" || fail "could not reset cwd"
to -r "$SEARCH_ROOT" "cover photo"
assert_path_eq "$PWD" "$SEARCH_ROOT/media/space names" "space-containing file stem jump"

if command -v sqlite3 >/dev/null 2>&1 && [[ -r "$TO_INDEX_FILE" ]]; then
  readme_file_count="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from files where lower_name = 'readme.md' and parent = $(sql_quote "${SEARCH_ROOT:A}/docs/assets");")"
  assert_eq "$readme_file_count" "1" "file-name jump writes file cache"
  music_cached="$(_to_index_query_files_sqlite 音乐 | head -n 1)"
  assert_path_eq "$music_cached" "$SEARCH_ROOT/media/audio" "unicode file cache can satisfy later lookup"
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
to ws school
assert_path_eq "$PWD" "$SEARCH_ROOT/workspace-school" "object workspace jump"

cd "$ROOT" || fail "could not reset cwd"
to file README.md
assert_path_eq "$PWD" "$SEARCH_ROOT/docs/assets" "object file jump"

cd "$ROOT" || fail "could not reset cwd"
to dir backend
assert_path_eq "$PWD" "$SEARCH_ROOT/app/services/backend" "object dir jump"

cd "$ROOT" || fail "could not reset cwd"
to cargo tokio
assert_path_eq "$PWD" "$SEARCH_ROOT/projects/rust/tokio-tool" "cargo object jump"

cd "$ROOT" || fail "could not reset cwd"
to npm react
assert_path_eq "$PWD" "$SEARCH_ROOT/projects/node/react-panel" "npm object jump"

cd "$ROOT" || fail "could not reset cwd"
to py fastapi
assert_path_eq "$PWD" "$SEARCH_ROOT/projects/python/fastapi-service" "python object jump"

cd "$ROOT" || fail "could not reset cwd"
to docker nginx
assert_path_eq "$PWD" "$SEARCH_ROOT/projects/docker/nginx-stack" "docker object jump"

cd "$ROOT" || fail "could not reset cwd"
to code authenticate_user
assert_path_eq "$PWD" "$SEARCH_ROOT/projects/code/auth-module/lib" "code object jump"

cd "$ROOT" || fail "could not reset cwd"
to issue 42
assert_path_eq "$PWD" "$SEARCH_ROOT/gh/issues/issue-42-login" "issue shortcut jumps to local clone"

cd "$ROOT" || fail "could not reset cwd"
to pr 77
assert_path_eq "$PWD" "$SEARCH_ROOT/gh/pulls/pull-77-docs" "pr shortcut jumps to local clone"

EXTERNAL_BIN="$ROOT/external-bin"
mkdir -p "$EXTERNAL_BIN"
cat > "$EXTERNAL_BIN/open-url" <<'EOF'
#!/usr/bin/env zsh
print -r -- "$1" > "$TO_EXTERNAL_COMMAND_LOG"
EOF
cat > "$EXTERNAL_BIN/code" <<'EOF'
#!/usr/bin/env zsh
print -r -- "$1" > "$TO_EXTERNAL_COMMAND_LOG"
EOF
cat > "$EXTERNAL_BIN/fig" <<'EOF'
#!/usr/bin/env zsh
print -r -- "$1" > "$TO_EXTERNAL_COMMAND_LOG"
EOF
chmod +x "$EXTERNAL_BIN/open-url" "$EXTERNAL_BIN/code" "$EXTERNAL_BIN/fig"
OLD_PATH="$PATH"
PATH="$EXTERNAL_BIN:$PATH"
OPEN_LOG="$ROOT/open.log"
export TO_EXTERNAL_COMMAND_LOG="$OPEN_LOG"
TO_OPEN_COMMAND="$EXTERNAL_BIN/open-url"
to gh z-ready/zsh-to
assert_eq "$(cat "$OPEN_LOG")" "https://github.com/z-ready/zsh-to" "gh shortcut opens owner repo URL"
TO_OPEN_COMMAND=""
to vscode backend
assert_path_eq "$(cat "$OPEN_LOG")" "$SEARCH_ROOT/app/services/backend" "vscode shortcut opens matching directory"
to fig backend
assert_path_eq "$(cat "$OPEN_LOG")" "$SEARCH_ROOT/app/services/backend" "fig shortcut opens matching directory"
PATH="$OLD_PATH"

cd "$ROOT" || fail "could not reset cwd"
to repo nginx
assert_path_eq "$PWD" "$SEARCH_ROOT/repos/nginx" "git repo jump"
if command -v sqlite3 >/dev/null 2>&1 && [[ -r "$TO_INDEX_FILE" ]]; then
  repo_count="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from dirs where repo = 1 and repo_name in ('nginx', 'ai-template', 'openai-api');")"
  assert_eq "$repo_count" "3" "reindex records repo metadata"
  repo_match="$(_to_repo_query_sqlite nginx | head -n 1)"
  assert_path_eq "$repo_match" "$SEARCH_ROOT/repos/nginx" "git repo query uses token index"
  ai_template_match="$(_to_repo_query_sqlite ai template | head -n 1)"
  assert_path_eq "$ai_template_match" "$SEARCH_ROOT/repos/ai-template" "repo query supports multiple keywords"
  now="$(_to_now)"
  sqlite3 "$TO_INDEX_FILE" >/dev/null <<SQL
insert or replace into history(path, visits, last_used) values($(sql_quote "${SEARCH_ROOT:A}/repos/openai-api"), 5, $now);
insert or replace into history(path, visits, last_used) values($(sql_quote "${SEARCH_ROOT:A}/repos/ai-template"), 1, $(( now - 1209600 )));
SQL
  repo_list="$(to repo | head -n 1)"
  assert_path_eq "$repo_list" "$SEARCH_ROOT/repos/openai-api" "repo without query lists frecent repositories first"
fi
cd "$ROOT" || fail "could not reset cwd"
to repo ai template
assert_path_eq "$PWD" "$SEARCH_ROOT/repos/ai-template" "repo command jumps with multiple keywords"
cd "$SEARCH_ROOT/repos/openai-api/src/plugin/test" || fail "could not enter nested repo fixture"
to git
assert_path_eq "$PWD" "$SEARCH_ROOT/repos/openai-api" "to git jumps to nearest repo root"
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
[[ "$missing_dir_output" == *"searched home-first roots"* && "$missing_dir_output" == *"to roots"* ]] \
  || fail "missing directory did not include root advice: $missing_dir_output"
ok "missing directory reports no match"

unknown_option_output="$(to --definitely-not-a-to-option 2>&1 >/dev/null)"
[[ "$unknown_option_output" == "to: unknown option: --definitely-not-a-to-option" ]] \
  || fail "unknown option should report only the option error: $unknown_option_output"
ok "unknown option reports a single clear error"

cd "$SEARCH_ROOT" || fail "could not enter search root"
to use . >/dev/null
assert_eq "$(to roots)" "${SEARCH_ROOT:A}
${HOME_DIR:A}" "use and roots persistence"

to unuse "$SEARCH_ROOT" >/dev/null
assert_eq "$(to roots)" "${HOME_DIR:A}" "unuse removes root"

cd "$ROOT" || fail "could not reset cwd"
EXTERNAL_OUTPUT="$ROOT/external-output"
to -r "$ROOT/external-parent" external-target > /dev/null 2> "$EXTERNAL_OUTPUT"
external_prompt_output="$(<"$EXTERNAL_OUTPUT")"
assert_path_eq "$PWD" "$ROOT/external-parent/external-target" "temporary external root can find directory"
[[ "$external_prompt_output" == *"outside your roots"* && "$external_prompt_output" == *"to use"* ]] \
  || fail "external temporary match did not suggest adding root: $external_prompt_output"
assert_eq "$(to roots)" "${HOME_DIR:A}" "external temporary match does not add root by default"

TO_AUTO_ADD_ROOTS=1
mkdir -p "$ROOT/auto-parent/auto-target"
cd "$ROOT" || fail "could not reset cwd"
AUTO_ROOT_OUTPUT="$ROOT/auto-root-output"
to -r "$ROOT/auto-parent" auto-target > /dev/null 2> "$AUTO_ROOT_OUTPUT"
auto_root_output="$(<"$AUTO_ROOT_OUTPUT")"
assert_path_eq "$PWD" "$ROOT/auto-parent/auto-target" "auto add roots still jumps to external target"
[[ "$auto_root_output" == *"added search root"* ]] || fail "auto add roots did not report added root: $auto_root_output"
assert_eq "$(to roots)" "${ROOT:A}/auto-parent
${HOME_DIR:A}" "auto add roots persists parent root"
TO_AUTO_ADD_ROOTS=0
to unuse "$ROOT/auto-parent" >/dev/null

assert_eq "$(_to_watch_backend)" "notify" "watcher uses helper notify backend"

doctor_output="$(to --doctor)"
[[ "$doctor_output" == *"to config: $CONFIG/config.zsh"* ]] || fail "doctor config path"
[[ "$doctor_output" == *"Search"* ]] || fail "doctor search category"
[[ "$doctor_output" == *"Discovery"* ]] || fail "doctor discovery category"
[[ "$doctor_output" == *"Performance"* ]] || fail "doctor performance category"
[[ "$doctor_output" == *"Statistics"* ]] || fail "doctor statistics category"
[[ "$doctor_output" == *"max depth: 8"* ]] || fail "doctor max depth"
[[ "$doctor_output" == *"path fragment search: off"* ]] || fail "doctor path fragment search"
[[ "$doctor_output" == *"follow symlinks: off"* ]] || fail "doctor follow symlinks"
[[ "$doctor_output" == *"watch debounce: 2s"* ]] || fail "doctor watch debounce"
[[ "$doctor_output" == *"autowatch: off"* ]] || fail "doctor autowatch"
[[ "$doctor_output" == *"auto add roots: off"* ]] || fail "doctor auto add roots"
[[ "$doctor_output" == *"frecency: on"* ]] || fail "doctor frecency"
[[ "$doctor_output" == *"frecency threshold: 1"* ]] || fail "doctor frecency threshold"
[[ "$doctor_output" == *"mode: home-first"* ]] || fail "doctor discovery mode"
[[ "$doctor_output" == *"watcher:"* ]] || fail "doctor watcher status"
[[ "$doctor_output" == *"sqlite entries:"* ]] || fail "doctor sqlite entry count"
[[ "$doctor_output" == *"sqlite dirs:"* ]] || fail "doctor sqlite dir count"
[[ "$doctor_output" == *"directory history:"* ]] || fail "doctor history count"
[[ "$doctor_output" == *"file cache:"* ]] || fail "doctor file cache count"
[[ "$doctor_output" == *"cache hit rate:"* ]] || fail "doctor cache hit rate"
[[ "$doctor_output" == *"last search:"* ]] || fail "doctor last search"
[[ "$doctor_output" != *"ai rank command:"* ]] || fail "doctor default output should hide ai rank command"
doctor_verbose_output="$(to --doctor --verbose)"
[[ "$doctor_verbose_output" == *"Verbose"* ]] || fail "doctor verbose category"
[[ "$doctor_verbose_output" == *"sqlite3 path:"* ]] || fail "doctor verbose sqlite path"
[[ "$doctor_verbose_output" == *"ai rank command:"* ]] || fail "doctor verbose ai rank command status"
[[ "$doctor_verbose_output" == *"open command:"* ]] || fail "doctor verbose open command status"
ok "doctor output"

bin_doctor_output="$("$TEST_DIR/../bin/to" --doctor)"
[[ "$bin_doctor_output" == *"to config: $CONFIG/config.zsh"* ]] || fail "bin wrapper doctor config path"
[[ "$bin_doctor_output" == *"max depth: 8"* ]] || fail "bin wrapper doctor config defaults"
ok "bin wrapper runs doctor before shell integration"

assert_eq "$("$TEST_DIR/../bin/to" --version)" "reach 1.6.0" "bin wrapper version output"

bin_roots_output="$("$TEST_DIR/../bin/to" roots)"
assert_eq "$bin_roots_output" "${HOME_DIR:A}" "bin wrapper runs roots before shell integration"

bin_reach_version="$("$TEST_DIR/../bin/reach" --version)"
assert_eq "$bin_reach_version" "reach 1.6.0" "reach wrapper version output"
bin_reach_init="$("$TEST_DIR/../bin/reach" init zsh)"
[[ "$bin_reach_init" == source*to.plugin.zsh* ]] || fail "reach wrapper init did not print plugin source command: $bin_reach_init"
ok "reach wrapper init output"

READONLY_CONFIG="$ROOT/readonly-config"
READONLY_HOME="$ROOT/readonly-home"
mkdir -p "$READONLY_CONFIG" "$READONLY_HOME/anywhere/missing-target"
TO_CONFIG_HOME="$READONLY_CONFIG" HOME="$READONLY_HOME" zsh -fc '
  source "$1"
  _to_index_ensure_sqlite_schema >/dev/null || exit 1
  chmod 444 "$TO_INDEX_FILE"
  output="$(to missing 2>&1 >/dev/null)"
  case "$output" in
    *"readonly database"*|*"Runtime error"*) exit 2 ;;
    *"no matching directory"*) exit 0 ;;
    *) print -u2 -- "$output"; exit 3 ;;
  esac
' zsh "$TEST_DIR/../to.plugin.zsh" || fail "readonly sqlite should not leak low-level errors"
ok "readonly sqlite reports user-facing miss"

TO_CONFIG_HOME="$READONLY_CONFIG" HOME="$READONLY_HOME" zsh -fc '
  source "$1"
  chmod 555 "$TO_CONFIG_HOME"
  cd "$HOME" || exit 1
  output="$(to missing-target 2>&1 >/dev/null)"
  code=$?
  chmod 755 "$TO_CONFIG_HOME"
  [[ "$code" == 0 ]] || exit 1
  case "$output" in
    *"operation not permitted"*|*"permission denied"*) exit 2 ;;
  esac
' zsh "$TEST_DIR/../to.plugin.zsh" || fail "recent write failure should not leak low-level errors"
chmod 755 "$READONLY_CONFIG"
ok "recent write failure stays quiet after successful jump"

print -- "all tests passed"
