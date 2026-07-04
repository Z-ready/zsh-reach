# reach: fast directory and object jumper for zsh. Default command: gt.

: ${TO_WATCH_DEBOUNCE:=2}
: ${TO_AUTOWATCH:=0}
: ${TO_AUTO_ADD_ROOTS:=0}
: ${TO_ROOT_MODE:=home}
: ${TO_FRECENCY:=1}
: ${TO_FRECENCY_THRESHOLD:=1}

typeset -ga TO_ROOTS
typeset -ga TO_EXCLUDES
typeset -g TO_MAX_DEPTH
typeset -g TO_INTERACTIVE_THRESHOLD
typeset -g TO_SEARCH_PATH_FRAGMENTS
typeset -g TO_FOLLOW_SYMLINKS
typeset -g TO_WATCH_DEBOUNCE
typeset -g TO_AUTOWATCH
typeset -g TO_AUTO_ADD_ROOTS
typeset -g TO_ROOT_MODE
typeset -g TO_FRECENCY
typeset -g TO_FRECENCY_THRESHOLD
typeset -g TO_OPEN_COMMAND
typeset -g TO_VSCODE_COMMAND
typeset -g TO_FIG_COMMAND
typeset -g TO_REACHIGNORE
typeset -g TO_USE_GITIGNORE
typeset -g TO_SHOW_DEEP_SCAN_PROMPT
typeset -g _TO_SQLITE_SCHEMA_READY_FILE
typeset -g _TO_AUTOWATCH_PID
typeset -g _TO_AUTOWATCH_PID_FILE
if (( ! $+_TO_VERSION )); then
  typeset -gr _TO_VERSION="1.6.0"
fi

_to_apply_positive_int_default() {
  local name="$1"
  local default="$2"
  local value="${(P)name}"

  if [[ "$value" == <-> && "$value" -gt 0 ]]; then
    typeset -gi "$name=$value"
  else
    typeset -gi "$name=$default"
  fi
}

_to_apply_bool_default() {
  local name="$1"
  local default="$2"
  local value="${(P)name}"

  if [[ "$value" == 0 || "$value" == 1 ]]; then
    typeset -gi "$name=$value"
  else
    typeset -gi "$name=$default"
  fi
}

_to_apply_nonnegative_int_default() {
  local name="$1"
  local default="$2"
  local value="${(P)name}"

  if [[ "$value" == <-> ]]; then
    typeset -gi "$name=$value"
  else
    typeset -gi "$name=$default"
  fi
}

_to_apply_root_mode_default() {
  case "$TO_ROOT_MODE" in
    home|explicit) ;;
    *) TO_ROOT_MODE=home ;;
  esac
}

_to_apply_nonnegative_number_default() {
  local name="$1"
  local default="$2"
  local value="${(P)name}"

  if [[ "$value" == <-> || "$value" == <->.<-> ]]; then
    typeset -g "$name=$value"
  else
    typeset -g "$name=$default"
  fi
}

_to_apply_config_defaults() {
  _to_apply_positive_int_default TO_MAX_DEPTH 8
  _to_apply_positive_int_default TO_INTERACTIVE_THRESHOLD 3
  _to_apply_bool_default TO_SEARCH_PATH_FRAGMENTS 0
  _to_apply_bool_default TO_FOLLOW_SYMLINKS 0
  _to_apply_bool_default TO_AUTOWATCH 0
  _to_apply_bool_default TO_AUTO_ADD_ROOTS 0
  _to_apply_bool_default TO_FRECENCY 1
  _to_apply_bool_default TO_USE_GITIGNORE 1
  _to_apply_bool_default TO_SHOW_DEEP_SCAN_PROMPT 1
  _to_apply_nonnegative_number_default TO_FRECENCY_THRESHOLD 1
  _to_apply_nonnegative_int_default TO_WATCH_DEBOUNCE 2
  _to_apply_root_mode_default
}

: ${TO_CONFIG_HOME:="${REACH_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/reach}"}
: ${TO_CONFIG_FILE:="$TO_CONFIG_HOME/config.zsh"}
: ${TO_ROOTS_FILE:="$TO_CONFIG_HOME/roots"}
: ${TO_INDEX_FILE:="$TO_CONFIG_HOME/index.sqlite3"}
: ${TO_INDEX_TSV_FILE:="$TO_CONFIG_HOME/index.tsv"}
: ${TO_ALIASES_FILE:="$TO_CONFIG_HOME/aliases"}
: ${TO_WORKSPACES_FILE:="$TO_CONFIG_HOME/workspaces"}
: ${TO_RECENT_FILE:="$TO_CONFIG_HOME/recent"}
: ${TO_AI_COMMAND:=""}
: ${TO_AI_RANK_COMMAND:=""}
: ${TO_OPEN_COMMAND:=""}
: ${TO_VSCODE_COMMAND:=""}
: ${TO_FIG_COMMAND:=""}
: ${TO_HELPER:=""}
: ${TO_REACHIGNORE:="${REACH_IGNORE_FILE:-$HOME/.reachignore}"}
: ${TO_MAX_DEPTH:=8}
: ${TO_INTERACTIVE_THRESHOLD:=3}
: ${TO_SEARCH_PATH_FRAGMENTS:=0}
: ${TO_FOLLOW_SYMLINKS:=0}
: ${TO_WATCH_DEBOUNCE:=2}
: ${TO_AUTOWATCH:=0}
: ${TO_AUTO_ADD_ROOTS:=0}
: ${TO_ROOT_MODE:=home}
: ${TO_FRECENCY:=1}
: ${TO_FRECENCY_THRESHOLD:=1}
: ${TO_USE_GITIGNORE:=1}
: ${TO_SHOW_DEEP_SCAN_PROMPT:=1}
_TO_AUTOWATCH_PID_FILE="$TO_CONFIG_HOME/watch.pid"

TO_ROOTS=()
TO_EXCLUDES=(
  "${TO_EXCLUDES[@]}"
  .git
  node_modules
  target
  .venv
  __pycache__
  Library
  .cache
  Trash
)

if [[ -r "$TO_CONFIG_FILE" ]]; then
  source "$TO_CONFIG_FILE"
fi
_to_apply_config_defaults

if [[ -z "$TO_HELPER" ]] && command -v reach-helper >/dev/null 2>&1; then
  TO_HELPER="$(command -v reach-helper)"
fi

_to_expand_path() {
  print -r -- "${~1:A}"
}

_to_unique_existing_dirs() {
  local -a out next
  local dir key existing skip

  for dir in "$@"; do
    [[ -n "$dir" ]] || continue
    dir="$(_to_expand_path "$dir")"
    [[ -d "$dir" ]] || continue
    key="${dir:A}"
    skip=0
    next=()

    for existing in "${out[@]}"; do
      if [[ "$key" == "$existing" || "$key" == "$existing"/* ]]; then
        skip=1
        next+=("$existing")
      elif [[ "$existing" == "$key"/* ]]; then
        continue
      else
        next+=("$existing")
      fi
    done

    out=("${next[@]}")
    (( skip == 0 )) && out+=("$key")
  done

  printf '%s\n' "${out[@]}"
}

_to_load_roots() {
  local -a file_roots default_roots
  local line

  if [[ -r "$TO_ROOTS_FILE" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] && file_roots+=("$line")
    done < "$TO_ROOTS_FILE"
  fi

  if [[ "$TO_ROOT_MODE" == home ]]; then
    default_roots=("$HOME")
  else
    default_roots=()
  fi
  TO_ROOTS=("${(@f)$(_to_unique_existing_dirs "${TO_ROOTS[@]}" "${file_roots[@]}" "${default_roots[@]}")}")
}

_to_save_roots() {
  mkdir -p "$TO_CONFIG_HOME" || return 1
  printf '%s\n' "${TO_ROOTS[@]}" > "$TO_ROOTS_FILE"
}

_to_builtin_alias() {
  local query="${(L)1}"
  local target=

  case "$query" in
    download|downloads) target="$HOME/Downloads" ;;
    desktop) target="$HOME/Desktop" ;;
    document|documents) target="$HOME/Documents" ;;
  esac

  [[ -n "$target" && -d "$target" ]] && print -r -- "$target"
}

_to_sql_quote() {
  local value="$1"
  value="${value//\'/\'\'}"
  print -r -- "'$value'"
}

_to_now() {
  local now

  now="$(date +%s 2>/dev/null)" || {
    print -u2 -- "reach: warning: could not read epoch time; skipping timestamped database update"
    return 1
  }
  [[ "$now" == <-> ]] || {
    print -u2 -- "reach: warning: invalid epoch time from date: $now"
    return 1
  }
  print -r -- "$now"
}

_to_dir_depth() {
  local dir="${1:A}"
  local trimmed="${dir#/}"

  [[ -n "$trimmed" ]] || {
    print -r -- 0
    return
  }
  print -r -- "${#${(@s:/:)trimmed}}"
}

_to_dir_index_row() {
  local dir="${1:A}"
  local now="${2:-$(_to_now)}"
  local name parent depth is_git repo repo_name

  [[ -d "$dir" ]] || return 1
  name="${dir:t}"
  parent="${dir:h}"
  depth="$(_to_dir_depth "$dir")"
  is_git=0
  repo=0
  repo_name=""
  if [[ -d "$dir/.git" || -f "$dir/.git" ]]; then
    is_git=1
    repo=1
    repo_name="$name"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$dir" "$name" "${(L)name}" "$parent" "$depth" "$is_git" "$repo" "${(L)repo_name}" "$now" 0 0
}

_to_file_stem() {
  local name="$1"

  if [[ "$name" == *.* && "$name" != .* ]]; then
    print -r -- "${name%.*}"
  else
    print -r -- "$name"
  fi
}

_to_query_has_extension() {
  local query="$1"

  [[ "$query" == *.* && "$query" != .* ]]
}

_to_root_mtime() {
  local value

  value="$(stat -f %m "$1" 2>/dev/null)"
  if [[ "$value" == <-> ]]; then
    print -r -- "$value"
    return 0
  fi

  value="$(stat -c %Y "$1" 2>/dev/null)"
  if [[ "$value" == <-> ]]; then
    print -r -- "$value"
    return 0
  fi

  print -r -- 0
}

_to_index_config_key() {
  print -r -- "depth=$TO_MAX_DEPTH;follow=$TO_FOLLOW_SYMLINKS;excludes=${(j:,:)TO_EXCLUDES}"
}

_to_discovery_mode_label() {
  if [[ "$TO_ROOT_MODE" == explicit ]]; then
    print -r -- "explicit roots"
  else
    print -r -- "home-first"
  fi
}

_to_roots_summary() {
  _to_load_roots
  if (( ${#TO_ROOTS} == 0 )); then
    print -r -- "none"
  else
    print -r -- "${(j:, :)TO_ROOTS}"
  fi
}

_to_print_no_match_advice() {
  local kind="$1"
  shift

  print -u2 -- "to: no matching $kind: ${(j: :)@}"
  print -u2 -- "to: searched $(_to_discovery_mode_label) roots: $(_to_roots_summary)"
  print -u2 -- "to: inspect roots with: to roots"
  print -u2 -- "to: add another root with: to use <dir>"
}

_to_root_is_safe_to_add() {
  local dir="${1:A}"

  case "$dir" in
    /|/System|/System/*|/Library|/Library/*|/usr|/usr/*|/bin|/bin/*|/sbin|/sbin/*|/etc|/etc/*|/dev|/dev/*|/proc|/proc/*|/sys|/sys/*|/run|/run/*)
      return 1
      ;;
    /private|/var)
      return 1
      ;;
  esac

  return 0
}

_to_dir_tokens() {
  local dir="${1:A}"
  local lower="${(L)dir}"
  local -a parts pieces seen
  local part split_part token

  parts=("${(@s:/:)lower}")
  for part in "${parts[@]}"; do
    [[ -n "$part" ]] || continue
    if (( ${seen[(Ie)$part]} == 0 )); then
      seen+=("$part")
      print -r -- "$part"
    fi

    split_part="$part"
    split_part="${split_part//-/ }"
    split_part="${split_part//_/ }"
    split_part="${split_part//./ }"
    pieces=("${(@s: :)split_part}")
    for token in "${pieces[@]}"; do
      [[ -n "$token" ]] || continue
      if (( ${seen[(Ie)$token]} == 0 )); then
        seen+=("$token")
        print -r -- "$token"
      fi
    done
  done
}

_to_dir_has_token() {
  local dir="$1"
  local wanted="${(L)2}"
  local token

  while IFS= read -r token; do
    [[ "$token" == "$wanted" ]] && return 0
  done < <(_to_dir_tokens "$dir")
  return 1
}

_to_index_collect_tokens_tsv() {
  local dirs_file="$1"
  local tokens_file="$2"
  local row row_path token tmpfile

  tmpfile="$tokens_file.tmp.$$"
  : > "$tmpfile" || return 1
  while IFS=$'\t' read -r row_path _; do
    [[ -n "$row_path" ]] || continue
    while IFS= read -r token; do
      [[ -n "$token" ]] || continue
      printf '%s\t%s\n' "$token" "$row_path" >> "$tmpfile"
    done < <(_to_dir_tokens "$row_path")
  done < "$dirs_file"

  sort -u "$tmpfile" > "$tokens_file" 2>/dev/null || mv "$tmpfile" "$tokens_file"
  rm -f "$tmpfile"
}

_to_index_ensure_sqlite_schema() {
  local has_id has_parent has_depth has_last_seen has_last_used has_hit_count has_repo has_repo_name has_token_dir_id has_token_path has_config_key has_files has_history has_stats

  if [[ -n "$TO_HELPER" && -x "$TO_HELPER" ]]; then
    mkdir -p "$TO_CONFIG_HOME" || return 1
    "$TO_HELPER" init-db --db "$TO_INDEX_FILE" >/dev/null 2>/dev/null && {
      _TO_SQLITE_SCHEMA_READY_FILE="$TO_INDEX_FILE"
      return 0
    }
  fi

  command -v sqlite3 >/dev/null 2>&1 || return 1
  if [[ "$_TO_SQLITE_SCHEMA_READY_FILE" == "$TO_INDEX_FILE" && -r "$TO_INDEX_FILE" ]]; then
    return 0
  fi

  mkdir -p "$TO_CONFIG_HOME" || return 1
  sqlite3 "$TO_INDEX_FILE" >/dev/null 2>/dev/null <<SQL || return 1
create table if not exists dirs(
  id integer primary key,
  path text unique not null,
  name text not null,
  lower_name text not null,
  parent text not null default '',
  depth integer not null default 0,
  is_git integer not null default 0,
  repo integer not null default 0,
  repo_name text not null default '',
  last_seen integer not null default 0,
  last_used integer not null default 0,
  hit_count integer not null default 0
);
create table if not exists tokens(
  token text not null,
  dir_id integer not null,
  primary key(token, dir_id)
);
create table if not exists roots(
  path text primary key,
  mtime integer not null default 0,
  config_key text not null default '',
  last_indexed integer not null default 0
);
create table if not exists aliases(
  name text primary key,
  path text not null
);
create table if not exists workspaces(
  name text primary key,
  path text not null
);
create table if not exists recent(
  path text primary key,
  last_used integer not null
);
create table if not exists history(
  path text primary key,
  visits integer not null default 0,
  last_used integer not null default 0
);
create table if not exists files(
  path text primary key,
  name text not null,
  lower_name text not null,
  stem text not null,
  lower_stem text not null,
  parent text not null,
  depth integer not null default 0,
  last_seen integer not null default 0
);
create table if not exists stats(
  key text primary key,
  value text not null default ''
);
SQL
  has_id="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from pragma_table_info('dirs') where name = 'id';" 2>/dev/null)"
  has_parent="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from pragma_table_info('dirs') where name = 'parent';" 2>/dev/null)"
  has_depth="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from pragma_table_info('dirs') where name = 'depth';" 2>/dev/null)"
  has_last_seen="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from pragma_table_info('dirs') where name = 'last_seen';" 2>/dev/null)"
  has_last_used="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from pragma_table_info('dirs') where name = 'last_used';" 2>/dev/null)"
  has_hit_count="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from pragma_table_info('dirs') where name = 'hit_count';" 2>/dev/null)"
  has_repo="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from pragma_table_info('dirs') where name = 'repo';" 2>/dev/null)"
  has_repo_name="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from pragma_table_info('dirs') where name = 'repo_name';" 2>/dev/null)"
  has_token_dir_id="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from pragma_table_info('tokens') where name = 'dir_id';" 2>/dev/null)"
  has_token_path="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from pragma_table_info('tokens') where name = 'path';" 2>/dev/null)"
  has_config_key="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from pragma_table_info('roots') where name = 'config_key';" 2>/dev/null)"
  has_files="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from sqlite_master where type = 'table' and name = 'files';" 2>/dev/null)"
  has_history="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from sqlite_master where type = 'table' and name = 'history';" 2>/dev/null)"
  has_stats="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from sqlite_master where type = 'table' and name = 'stats';" 2>/dev/null)"

  if [[ "$has_id" != 1 ]]; then
    [[ "$has_parent" == 1 ]] || sqlite3 "$TO_INDEX_FILE" "alter table dirs add column parent text not null default '';" >/dev/null 2>/dev/null
    [[ "$has_depth" == 1 ]] || sqlite3 "$TO_INDEX_FILE" "alter table dirs add column depth integer not null default 0;" >/dev/null 2>/dev/null
    [[ "$has_last_seen" == 1 ]] || sqlite3 "$TO_INDEX_FILE" "alter table dirs add column last_seen integer not null default 0;" >/dev/null 2>/dev/null
    [[ "$has_last_used" == 1 ]] || sqlite3 "$TO_INDEX_FILE" "alter table dirs add column last_used integer not null default 0;" >/dev/null 2>/dev/null
    [[ "$has_hit_count" == 1 ]] || sqlite3 "$TO_INDEX_FILE" "alter table dirs add column hit_count integer not null default 0;" >/dev/null 2>/dev/null
    sqlite3 "$TO_INDEX_FILE" >/dev/null 2>/dev/null <<SQL || return 1
alter table dirs rename to dirs_legacy;
create table dirs(
  id integer primary key,
  path text unique not null,
  name text not null,
  lower_name text not null,
  parent text not null default '',
  depth integer not null default 0,
  is_git integer not null default 0,
  repo integer not null default 0,
  repo_name text not null default '',
  last_seen integer not null default 0,
  last_used integer not null default 0,
  hit_count integer not null default 0
);
insert into dirs(path, name, lower_name, parent, depth, is_git, repo, repo_name, last_seen, last_used, hit_count)
select
  path,
  name,
  lower_name,
  coalesce(parent, rtrim(substr(path, 1, length(path) - length(name)), '/')),
  coalesce(depth, length(path) - length(replace(path, '/', ''))),
  coalesce(is_git, 0),
  coalesce(is_git, 0),
  case when coalesce(is_git, 0) = 1 then lower_name else '' end,
  coalesce(last_seen, 0),
  coalesce(last_used, 0),
  coalesce(hit_count, 0)
from dirs_legacy;
drop table dirs_legacy;
SQL
    has_parent=1
    has_depth=1
    has_last_seen=1
    has_last_used=1
    has_hit_count=1
  fi

  [[ "$has_parent" == 1 ]] || sqlite3 "$TO_INDEX_FILE" "alter table dirs add column parent text not null default '';" >/dev/null 2>/dev/null
  [[ "$has_depth" == 1 ]] || sqlite3 "$TO_INDEX_FILE" "alter table dirs add column depth integer not null default 0;" >/dev/null 2>/dev/null
  [[ "$has_last_seen" == 1 ]] || sqlite3 "$TO_INDEX_FILE" "alter table dirs add column last_seen integer not null default 0;" >/dev/null 2>/dev/null
  [[ "$has_last_used" == 1 ]] || sqlite3 "$TO_INDEX_FILE" "alter table dirs add column last_used integer not null default 0;" >/dev/null 2>/dev/null
  [[ "$has_hit_count" == 1 ]] || sqlite3 "$TO_INDEX_FILE" "alter table dirs add column hit_count integer not null default 0;" >/dev/null 2>/dev/null
  [[ "$has_repo" == 1 ]] || sqlite3 "$TO_INDEX_FILE" "alter table dirs add column repo integer not null default 0;" >/dev/null 2>/dev/null
  [[ "$has_repo_name" == 1 ]] || sqlite3 "$TO_INDEX_FILE" "alter table dirs add column repo_name text not null default '';" >/dev/null 2>/dev/null
  [[ "$has_config_key" == 1 ]] || sqlite3 "$TO_INDEX_FILE" "alter table roots add column config_key text not null default '';" >/dev/null 2>/dev/null
  if [[ "$has_files" != 1 ]]; then
    sqlite3 "$TO_INDEX_FILE" >/dev/null 2>/dev/null <<SQL || return 1
create table files(
  path text primary key,
  name text not null,
  lower_name text not null,
  stem text not null,
  lower_stem text not null,
  parent text not null,
  depth integer not null default 0,
  last_seen integer not null default 0
);
SQL
  fi
  if [[ "$has_history" != 1 ]]; then
    sqlite3 "$TO_INDEX_FILE" "create table history(path text primary key, visits integer not null default 0, last_used integer not null default 0);" >/dev/null 2>/dev/null || return 1
  fi
  if [[ "$has_stats" != 1 ]]; then
    sqlite3 "$TO_INDEX_FILE" "create table stats(key text primary key, value text not null default '');" >/dev/null 2>/dev/null || return 1
  fi

  if [[ "$has_token_dir_id" != 1 ]]; then
    if [[ "$has_token_path" == 1 ]]; then
      sqlite3 "$TO_INDEX_FILE" >/dev/null 2>/dev/null <<SQL || return 1
alter table tokens rename to tokens_legacy;
create table tokens(
  token text not null,
  dir_id integer not null,
  primary key(token, dir_id)
);
insert or ignore into tokens(token, dir_id)
select t.token, d.id
from tokens_legacy t
join dirs d on d.path = t.path;
drop table tokens_legacy;
SQL
    else
      sqlite3 "$TO_INDEX_FILE" "drop table if exists tokens; create table tokens(token text not null, dir_id integer not null, primary key(token, dir_id));" >/dev/null || return 1
    fi
  fi

  sqlite3 "$TO_INDEX_FILE" >/dev/null 2>/dev/null <<SQL || return 1
update dirs set parent = rtrim(substr(path, 1, length(path) - length(name)), '/') where parent = '';
update dirs set depth = length(path) - length(replace(path, '/', '')) where depth = 0;
update dirs set repo = 1, repo_name = lower_name where is_git = 1 and (repo = 0 or repo_name = '');
create index if not exists idx_dirs_lower_name on dirs(lower_name);
create index if not exists idx_dirs_is_git on dirs(is_git);
create index if not exists idx_dirs_repo on dirs(repo);
create index if not exists idx_dirs_repo_name on dirs(repo_name);
create index if not exists idx_dirs_depth on dirs(depth);
create index if not exists idx_dirs_last_used on dirs(last_used);
create index if not exists idx_dirs_path on dirs(path);
create index if not exists idx_tokens_token on tokens(token);
create index if not exists idx_tokens_dir_id on tokens(dir_id);
create index if not exists idx_roots_last_indexed on roots(last_indexed);
create index if not exists idx_recent_last_used on recent(last_used);
create index if not exists idx_files_lower_name on files(lower_name);
create index if not exists idx_files_lower_stem on files(lower_stem);
create index if not exists idx_files_parent on files(parent);
create index if not exists idx_history_last_used on history(last_used);
create index if not exists idx_history_path on history(path);
create index if not exists idx_stats_key on stats(key);
SQL
  _TO_SQLITE_SCHEMA_READY_FILE="$TO_INDEX_FILE"
}

_to_read_map_value() {
  local file="$1"
  local key="${(L)2}"
  local table="$3"
  local line item value

  if [[ -n "$table" && ( -r "$TO_INDEX_FILE" || -r "$file" ) ]] && command -v sqlite3 >/dev/null 2>&1; then
    _to_index_ensure_sqlite_schema >/dev/null 2>&1
    _to_import_map_file_to_sqlite "$file" "$table"
    value="$(sqlite3 -noheader "$TO_INDEX_FILE" "select path from $table where name = $(_to_sql_quote "$key");" 2>/dev/null)"
    if [[ -n "$value" && -d "$value" ]]; then
      print -r -- "${value:A}"
      return
    fi
  fi

  [[ -r "$file" ]] || return 1
  while IFS= read -r line; do
    item="${line%%	*}"
    value="${line#*	}"
    if [[ "${(L)item}" == "$key" && "$value" != "$line" && -d "$value" ]]; then
      print -r -- "${value:A}"
      return
    fi
  done < "$file"

  return 1
}

_to_import_map_file_to_sqlite() {
  local file="$1"
  local table="$2"
  local line key value

  [[ -n "$table" && -r "$file" ]] || return 0
  command -v sqlite3 >/dev/null 2>&1 || return 0

  while IFS= read -r line; do
    key="${line%%	*}"
    value="${line#*	}"
    [[ -z "$key" || "$value" == "$line" || ! -d "$value" ]] && continue
    sqlite3 "$TO_INDEX_FILE" "insert or ignore into $table(name, path) values($(_to_sql_quote "${(L)key}"), $(_to_sql_quote "${value:A}"));" >/dev/null 2>/dev/null
  done < "$file"
}

_to_import_recent_file_to_sqlite() {
  local line when dir

  [[ -r "$TO_RECENT_FILE" ]] || return 0
  command -v sqlite3 >/dev/null 2>&1 || return 0

  while IFS= read -r line; do
    when="${line%%	*}"
    dir="${line#*	}"
    [[ -z "$when" || "$dir" == "$line" || ! -d "$dir" ]] && continue
    sqlite3 "$TO_INDEX_FILE" "insert or ignore into recent(path, last_used) values($(_to_sql_quote "${dir:A}"), ${when});" >/dev/null 2>/dev/null
  done < "$TO_RECENT_FILE"
}

_to_write_map_value() {
  local file="$1"
  local key="$2"
  local dir="$3"
  local table="$4"
  local tmp="$file.tmp.$$"
  local line item

  if [[ -n "$table" ]] && command -v sqlite3 >/dev/null 2>&1; then
    _to_index_ensure_sqlite_schema >/dev/null 2>&1
    sqlite3 "$TO_INDEX_FILE" "insert or replace into $table(name, path) values($(_to_sql_quote "${(L)key}"), $(_to_sql_quote "${dir:A}"));" >/dev/null 2>/dev/null
  fi

  mkdir -p "$TO_CONFIG_HOME" || return 1
  : > "$tmp" || return 1

  if [[ -r "$file" ]]; then
    while IFS= read -r line; do
      item="${line%%	*}"
      [[ "${(L)item}" == "${(L)key}" ]] && continue
      print -r -- "$line" >> "$tmp"
    done < "$file"
  fi

  printf '%s\t%s\n' "$key" "${dir:A}" >> "$tmp"
  mv "$tmp" "$file"
}

_to_remove_map_value() {
  local file="$1"
  local key="$2"
  local table="$3"
  local tmp="$file.tmp.$$"
  local line item

  if [[ -n "$table" ]] && command -v sqlite3 >/dev/null 2>&1; then
    _to_index_ensure_sqlite_schema >/dev/null 2>&1
    sqlite3 "$TO_INDEX_FILE" "delete from $table where name = $(_to_sql_quote "${(L)key}");" >/dev/null 2>/dev/null
  fi

  [[ -r "$file" ]] || return 0
  : > "$tmp" || return 1
  while IFS= read -r line; do
    item="${line%%	*}"
    [[ "${(L)item}" == "${(L)key}" ]] && continue
    print -r -- "$line" >> "$tmp"
  done < "$file"

  mv "$tmp" "$file"
}

_to_print_map() {
  local file="$1"
  local table="$2"
  local line key value

  if [[ -n "$table" ]] && command -v sqlite3 >/dev/null 2>&1; then
    _to_index_ensure_sqlite_schema >/dev/null 2>&1
    _to_import_map_file_to_sqlite "$file" "$table"
    sqlite3 -noheader -separator ' -> ' "$TO_INDEX_FILE" "select name, path from $table order by name;" 2>/dev/null
    return 0
  fi

  [[ -r "$file" ]] || return 0
  while IFS= read -r line; do
    key="${line%%	*}"
    value="${line#*	}"
    [[ "$value" == "$line" ]] && continue
    printf '%s -> %s\n' "$key" "$value"
  done < "$file"
}

_to_user_alias() {
  _to_read_map_value "$TO_ALIASES_FILE" "$1" aliases
}

_to_workspace() {
  _to_read_map_value "$TO_WORKSPACES_FILE" "$1" workspaces
}

_to_record_recent() {
  local dir="${1:A}"
  local tmp="$TO_RECENT_FILE.tmp.$$"
  local line item
  local count=0
  local now

  [[ -d "$dir" ]] || return 0
  mkdir -p "$TO_CONFIG_HOME" || return 0
  now="$(_to_now)" || return 0

  if [[ -n "$TO_HELPER" && -x "$TO_HELPER" ]]; then
    _to_index_ensure_sqlite_schema >/dev/null 2>&1 \
      && "$TO_HELPER" record-recent --db "$TO_INDEX_FILE" --path "$dir" --now "$now" >/dev/null 2>/dev/null
  fi

  if [[ -z "$TO_HELPER" ]] && command -v sqlite3 >/dev/null 2>&1; then
    _to_index_ensure_sqlite_schema >/dev/null 2>&1
    sqlite3 "$TO_INDEX_FILE" >/dev/null 2>/dev/null <<SQL
insert or replace into recent(path, last_used)
values($(_to_sql_quote "$dir"), $now);
delete from recent
where path not in (
  select path from recent order by last_used desc, rowid desc limit 50
);
SQL
  fi

  { printf '%s\t%s\n' "$now" "$dir" > "$tmp" } 2>/dev/null || return 0

  if [[ -r "$TO_RECENT_FILE" ]]; then
    while IFS= read -r line; do
      item="${line#*	}"
      [[ "$item" == "$line" || "${item:A}" == "$dir" ]] && continue
      { print -r -- "$line" >> "$tmp" } 2>/dev/null || break
      (( ++count >= 49 )) && break
    done < "$TO_RECENT_FILE"
  fi

  mv "$tmp" "$TO_RECENT_FILE" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}

_to_recent_dirs() {
  local line dir
  local -a sqlite_recent

  if [[ -n "$TO_HELPER" && -x "$TO_HELPER" && -r "$TO_INDEX_FILE" ]]; then
    _to_index_ensure_sqlite_schema >/dev/null 2>&1
    sqlite_recent=("${(@f)$("$TO_HELPER" recent --db "$TO_INDEX_FILE" 2>/dev/null)}")
    if (( ${#sqlite_recent} > 0 )); then
      for dir in "${sqlite_recent[@]}"; do
        [[ -d "$dir" ]] && print -r -- "${dir:A}"
      done
      return 0
    fi
  fi

  if command -v sqlite3 >/dev/null 2>&1; then
    _to_index_ensure_sqlite_schema >/dev/null 2>&1
    _to_import_recent_file_to_sqlite
    sqlite_recent=("${(@f)$(sqlite3 -noheader "$TO_INDEX_FILE" "select path from recent order by last_used desc, rowid desc limit 50;" 2>/dev/null)}")
    if (( ${#sqlite_recent} > 0 )); then
      for dir in "${sqlite_recent[@]}"; do
        [[ -d "$dir" ]] && print -r -- "${dir:A}"
      done
      return 0
    fi
  fi

  [[ -r "$TO_RECENT_FILE" ]] || return 1
  while IFS= read -r line; do
    dir="${line#*	}"
    [[ "$dir" != "$line" && -d "$dir" ]] && print -r -- "${dir:A}"
  done < "$TO_RECENT_FILE"
}

_to_frecency_score_sql() {
  local now="$1"

  print -r -- "case when $now - last_used <= 3600 then visits * 4.0 when $now - last_used <= 86400 then visits * 2.0 when $now - last_used <= 604800 then visits * 0.5 else visits * 0.25 end"
}

_to_record_frecency() {
  local dir="${1:A}"
  local now

  (( TO_FRECENCY == 1 )) || return 0
  [[ -d "$dir" ]] || return 0
  _to_index_ensure_sqlite_schema >/dev/null 2>&1 || return 0
  now="$(_to_now)" || return 0

  if [[ -n "$TO_HELPER" && -x "$TO_HELPER" ]]; then
    "$TO_HELPER" record-frecency --db "$TO_INDEX_FILE" --path "$dir" --threshold "$TO_FRECENCY_THRESHOLD" --now "$now" >/dev/null 2>/dev/null
    return 0
  fi
  command -v sqlite3 >/dev/null 2>&1 || return 0

  sqlite3 "$TO_INDEX_FILE" >/dev/null 2>/dev/null <<SQL
insert into history(path, visits, last_used)
values($(_to_sql_quote "$dir"), 1, $now)
on conflict(path) do update set
  visits = history.visits + 1,
  last_used = excluded.last_used;
delete from history
where not exists (select 1 from dirs d where d.path = history.path)
  and last_used < $(( now - 604800 ));
delete from history
where $(_to_frecency_score_sql "$now") < $TO_FRECENCY_THRESHOLD
  and last_used < $(( now - 604800 ));
SQL
}

_to_stat_set() {
  local key="$1"
  local value="$2"

  _to_index_ensure_sqlite_schema >/dev/null 2>&1 || return 0
  if [[ -n "$TO_HELPER" && -x "$TO_HELPER" ]]; then
    "$TO_HELPER" stat-set --db "$TO_INDEX_FILE" --key "$key" --value "$value" >/dev/null 2>/dev/null
    return 0
  fi
  command -v sqlite3 >/dev/null 2>&1 || return 0
  sqlite3 "$TO_INDEX_FILE" "insert or replace into stats(key, value) values($(_to_sql_quote "$key"), $(_to_sql_quote "$value"));" >/dev/null 2>/dev/null
}

_to_stat_increment() {
  local key="$1"

  _to_index_ensure_sqlite_schema >/dev/null 2>&1 || return 0
  if [[ -n "$TO_HELPER" && -x "$TO_HELPER" ]]; then
    "$TO_HELPER" stat-inc --db "$TO_INDEX_FILE" --key "$key" >/dev/null 2>/dev/null
    return 0
  fi
  command -v sqlite3 >/dev/null 2>&1 || return 0
  sqlite3 "$TO_INDEX_FILE" "insert into stats(key, value) values($(_to_sql_quote "$key"), '1') on conflict(key) do update set value = cast(stats.value as integer) + 1;" >/dev/null 2>/dev/null
}

_to_record_search_outcome() {
  local outcome="$1"

  [[ "$outcome" != "Miss" || -r "$TO_INDEX_FILE" ]] || return 0
  _to_stat_set last_search "$outcome"
  _to_stat_increment search_total
  case "$outcome" in
    *Hit|Repo\ Index|File\ Cache)
      _to_stat_increment search_hit
      ;;
  esac
}

_to_stat_get() {
  local key="$1"
  local fallback="${2:-0}"
  local value

  if [[ -n "$TO_HELPER" && -x "$TO_HELPER" && -r "$TO_INDEX_FILE" ]]; then
    value="$("$TO_HELPER" stat-get --db "$TO_INDEX_FILE" --key "$key" --fallback "$fallback" 2>/dev/null)"
    [[ -n "$value" ]] && print -r -- "$value" || print -r -- "$fallback"
    return
  fi
  command -v sqlite3 >/dev/null 2>&1 || {
    print -r -- "$fallback"
    return
  }
  [[ -r "$TO_INDEX_FILE" ]] || {
    print -r -- "$fallback"
    return
  }
  _to_index_ensure_sqlite_schema >/dev/null 2>&1 || {
    print -r -- "$fallback"
    return
  }
  value="$(sqlite3 -noheader "$TO_INDEX_FILE" "select value from stats where key = $(_to_sql_quote "$key");" 2>/dev/null)"
  [[ -n "$value" ]] && print -r -- "$value" || print -r -- "$fallback"
}

_to_dir_is_under_roots_ref() {
  local roots_ref="$1"
  local dir="${2:A}"
  local -a candidate_roots
  local root

  eval "candidate_roots=(\"\${${roots_ref}[@]}\")"
  for root in "${candidate_roots[@]}"; do
    root="${root:A}"
    [[ "$dir" == "$root" || "$dir" == "$root"/* ]] && return 0
  done

  return 1
}

_to_frecency_filter_roots() {
  local roots_ref="$1"
  local dir

  while IFS= read -r dir; do
    [[ -d "$dir" ]] || {
      _to_index_delete_path "$dir"
      command -v sqlite3 >/dev/null 2>&1 && [[ -r "$TO_INDEX_FILE" ]] \
        && sqlite3 "$TO_INDEX_FILE" "delete from history where path = $(_to_sql_quote "$dir");" >/dev/null 2>/dev/null
      continue
    }
    _to_dir_is_under_roots_ref "$roots_ref" "$dir" && print -r -- "${dir:A}"
  done
}

_to_frecency_query_sqlite() {
  local roots_ref="$1"
  shift
  local -a queries clauses
  local query first now score_sql where sql threshold

  (( TO_FRECENCY == 1 )) || return 1
  [[ -r "$TO_INDEX_FILE" ]] || return 1
  _to_index_ensure_sqlite_schema || return 1
  queries=("${(@L)@}")
  (( ${#queries} > 0 )) || return 1
  if (( ${#queries} == 1 )) && _to_query_has_extension "$queries[1]"; then
    return 1
  fi

  first="${queries[1]}"
  now="$(_to_now)" || return 1
  if [[ -n "$TO_HELPER" && -x "$TO_HELPER" ]]; then
    "$TO_HELPER" frecency-query --db "$TO_INDEX_FILE" --threshold "$TO_FRECENCY_THRESHOLD" --now "$now" -- "${queries[@]}" 2>/dev/null \
      | _to_frecency_filter_roots "$roots_ref"
    return
  fi
  command -v sqlite3 >/dev/null 2>&1 || return 1
  score_sql="$(_to_frecency_score_sql "$now")"
  threshold="$TO_FRECENCY_THRESHOLD"
  if (( ${#queries} == 1 )) && [[ "$queries[1]" != */* ]] && (( TO_SEARCH_PATH_FRAGMENTS == 0 )); then
    clauses+=("lower(h.path) like $(_to_sql_quote "%/$queries[1]")")
  else
    for query in "${queries[@]}"; do
      clauses+=("lower(h.path) like $(_to_sql_quote "%$query%")")
    done
  fi
  where="${(j: and :)clauses}"

  sql="select h.path from history h where $where and ($score_sql) >= $threshold order by case when lower(h.path) like $(_to_sql_quote "%/$first") then 0 else 1 end, ($score_sql) desc, h.last_used desc, length(h.path), h.path limit 50;"
  sqlite3 -noheader "$TO_INDEX_FILE" "$sql" 2>/dev/null | _to_frecency_filter_roots "$roots_ref"
}

_to_frecency_fields() {
  local dir="${1:A}"
  local now score_sql fields

  (( TO_FRECENCY == 1 )) || {
    print -r -- "0	0	0"
    return
  }
  command -v sqlite3 >/dev/null 2>&1 || {
    print -r -- "0	0	0"
    return
  }
  [[ -r "$TO_INDEX_FILE" ]] || {
    print -r -- "0	0	0"
    return
  }
  _to_index_ensure_sqlite_schema >/dev/null 2>&1 || {
    print -r -- "0	0	0"
    return
  }
  now="$(_to_now)" || {
    print -r -- "0	0	0"
    return
  }
  if [[ -n "$TO_HELPER" && -x "$TO_HELPER" ]]; then
    fields="$("$TO_HELPER" frecency-fields --db "$TO_INDEX_FILE" --path "$dir" --now "$now" 2>/dev/null)"
    [[ -n "$fields" ]] && print -r -- "$fields" || print -r -- "0	0	0"
    return
  fi
  score_sql="$(_to_frecency_score_sql "$now")"
  fields="$(sqlite3 -noheader "$TO_INDEX_FILE" "select printf('%.6f', $score_sql) || char(9) || last_used || char(9) || visits from history where path = $(_to_sql_quote "$dir");" 2>/dev/null)"
  [[ -n "$fields" ]] && print -r -- "$fields" || print -r -- "0	0	0"
}

_to_exclude_args_fd() {
  local item
  for item in "${TO_EXCLUDES[@]}"; do
    print -r -- --exclude
    print -r -- "$item"
  done
}

_to_prune_expr_find() {
  local -a expr
  local item

  for item in "${TO_EXCLUDES[@]}"; do
    expr+=(-name "$item" -o)
  done

  if (( ${#expr} > 0 )); then
    expr=("${expr[@]:0:${#expr}-1}")
    printf '%s\n' "${expr[@]}"
  fi
}

_to_search_dirs_with_fd() {
  local root="$1"
  shift
  local -a exclude_args follow_args

  exclude_args=("${(@f)$(_to_exclude_args_fd)}")
  (( TO_FOLLOW_SYMLINKS == 1 )) && follow_args=(--follow)
  fd --type d --hidden "${follow_args[@]}" --max-depth "$TO_MAX_DEPTH" "${exclude_args[@]}" . "$root" 2>/dev/null
}

_to_search_dirs_with_find() {
  local root="$1"
  local -a prune_expr

  prune_expr=("${(@f)$(_to_prune_expr_find)}")
  if (( ${#prune_expr} > 0 )); then
    find "$root" -maxdepth "$TO_MAX_DEPTH" \( "${prune_expr[@]}" \) -prune -o -type d -print 2>/dev/null
  else
    find "$root" -maxdepth "$TO_MAX_DEPTH" -type d -print 2>/dev/null
  fi
}

_to_search_exact_name_with_fd() {
  local root="$1"
  local query="$2"
  local limit="${3:-}"
  local -a exclude_args limit_args follow_args

  exclude_args=("${(@f)$(_to_exclude_args_fd)}")
  if [[ -n "$limit" ]]; then
    limit_args=(--max-results "$limit")
  fi
  (( TO_FOLLOW_SYMLINKS == 1 )) && follow_args=(--follow)

  fd --type d --hidden "${follow_args[@]}" --max-depth "$TO_MAX_DEPTH" --glob --ignore-case "${limit_args[@]}" "${exclude_args[@]}" "$query" "$root" 2>/dev/null
}

_to_search_exact_name_with_find() {
  local root="$1"
  local query="$2"
  local limit="${3:-}"
  local -a prune_expr quit_expr

  prune_expr=("${(@f)$(_to_prune_expr_find)}")
  [[ "$limit" == 1 ]] && quit_expr=(-quit)

  if (( ${#prune_expr} > 0 )); then
    find "$root" -maxdepth "$TO_MAX_DEPTH" \( "${prune_expr[@]}" \) -prune -o -type d -iname "$query" -print "${quit_expr[@]}" 2>/dev/null
  else
    find "$root" -maxdepth "$TO_MAX_DEPTH" -type d -iname "$query" -print "${quit_expr[@]}" 2>/dev/null
  fi
}

_to_search_exact_name() {
  local root="$1"
  local query="$2"
  local limit="${3:-}"
  local -a matches

  if [[ -n "$TO_HELPER" && -x "$TO_HELPER" ]]; then
    matches=("${(@f)$(_to_helper_scan_single_root "$root" dir exact 1 "$query")}")
    if [[ -n "$limit" ]]; then
      printf '%s\n' "${matches[@]:0:$limit}"
    else
      printf '%s\n' "${matches[@]}"
    fi
    return
  fi
  _to_search_exact_name_with_find "$root" "$query" "$limit"
}

_to_search_exact_file_with_fd() {
  local root="$1"
  local query="$2"
  local limit="${3:-100}"
  local pattern
  local -a exclude_args follow_args

  exclude_args=("${(@f)$(_to_exclude_args_fd)}")
  (( TO_FOLLOW_SYMLINKS == 1 )) && follow_args=(--follow)
  if _to_query_has_extension "$query"; then
    fd --type f --hidden "${follow_args[@]}" --max-depth "$TO_MAX_DEPTH" \
      --glob --ignore-case --max-results "$limit" "${exclude_args[@]}" "$query" "$root" 2>/dev/null
  else
    for pattern in "$query" "$query.*"; do
      fd --type f --hidden "${follow_args[@]}" --max-depth "$TO_MAX_DEPTH" \
        --glob --ignore-case --max-results "$limit" "${exclude_args[@]}" "$pattern" "$root" 2>/dev/null
    done
  fi
}

_to_search_exact_file_with_find() {
  local root="$1"
  local query="$2"
  local -a prune_expr
  local stem_pattern

  prune_expr=("${(@f)$(_to_prune_expr_find)}")
  stem_pattern="${query}.*"
  if (( ${#prune_expr} > 0 )); then
    if _to_query_has_extension "$query"; then
      find "$root" -maxdepth "$TO_MAX_DEPTH" \( "${prune_expr[@]}" \) -prune -o -type f -iname "$query" -print 2>/dev/null
    else
      find "$root" -maxdepth "$TO_MAX_DEPTH" \( "${prune_expr[@]}" \) -prune -o -type f \( -iname "$query" -o -iname "$stem_pattern" \) -print 2>/dev/null
    fi
  else
    if _to_query_has_extension "$query"; then
      find "$root" -maxdepth "$TO_MAX_DEPTH" -type f -iname "$query" -print 2>/dev/null
    else
      find "$root" -maxdepth "$TO_MAX_DEPTH" -type f \( -iname "$query" -o -iname "$stem_pattern" \) -print 2>/dev/null
    fi
  fi
}

_to_search_exact_file() {
  local root="$1"
  local query="$2"

  if [[ -n "$TO_HELPER" && -x "$TO_HELPER" ]]; then
    _to_helper_scan_single_root "$root" file exact 1 "$query"
    return
  fi
  _to_search_exact_file_with_find "$root" "$query"
}

_to_helper_scan_single_root() {
  local root="$1"
  local kind="$2"
  local mode="$3"
  local deep="${4:-0}"
  shift 4
  local -a args

  [[ -n "$TO_HELPER" && -x "$TO_HELPER" && -d "$root" ]] || return 1
  args=(scan --kind "$kind" --mode "$mode" --root "${root:A}" --max-depth "$TO_MAX_DEPTH" --reachignore "$TO_REACHIGNORE")
  (( TO_FOLLOW_SYMLINKS == 1 )) && args+=(--follow-links)
  (( TO_USE_GITIGNORE == 0 )) && args+=(--no-gitignore)
  (( deep == 1 )) && args+=(--deep-fallback)
  (( TO_SHOW_DEEP_SCAN_PROMPT == 0 )) && args+=(--no-deep-prompt)
  "$TO_HELPER" "${args[@]}" -- "$@" 2>/dev/null
}

_to_helper_scan_roots_ref() {
  local roots_ref="$1"
  local kind="$2"
  local mode="$3"
  local deep="${4:-0}"
  shift 4
  local -a roots args
  local root

  [[ -n "$TO_HELPER" && -x "$TO_HELPER" ]] || return 1
  eval "roots=(\"\${${roots_ref}[@]}\")"
  args=(scan --kind "$kind" --mode "$mode" --max-depth "$TO_MAX_DEPTH" --reachignore "$TO_REACHIGNORE")
  for root in "${roots[@]}"; do
    [[ -d "$root" ]] && args+=(--root "${root:A}")
  done
  (( ${#args[(I)--root]} > 0 )) || return 1
  (( TO_FOLLOW_SYMLINKS == 1 )) && args+=(--follow-links)
  (( TO_USE_GITIGNORE == 0 )) && args+=(--no-gitignore)
  (( deep == 1 )) && args+=(--deep-fallback)
  (( TO_SHOW_DEEP_SCAN_PROMPT == 0 )) && args+=(--no-deep-prompt)
  "$TO_HELPER" "${args[@]}" -- "$@" 2>/dev/null
}

_to_file_matches_query() {
  local file="$1"
  local query="${(L)2}"
  local name stem

  name="${(L)${file:t}}"
  stem="$(_to_file_stem "${file:t}")"
  stem="${(L)stem}"
  if _to_query_has_extension "$query"; then
    [[ "$name" == "$query" ]]
  else
    [[ "$name" == "$query" || "$stem" == "$query" ]]
  fi
}

_to_index_collect_root_tsv() {
  local root="${1:A}"
  local output_file="$2"
  local now="${3:-}"
  local dir

  [[ -d "$root" ]] || return 1
  [[ -n "$now" ]] || now="$(_to_now)" || return 1
  : > "$output_file" || return 1
  print -u2 -- "to: indexing $root"
  if command -v fd >/dev/null 2>&1; then
    local -a exclude_args follow_args
    exclude_args=("${(@f)$(_to_exclude_args_fd)}")
    (( TO_FOLLOW_SYMLINKS == 1 )) && follow_args=(--follow)
    while IFS= read -r dir; do
      dir="${dir%/}"
      [[ -n "$dir" ]] || continue
      _to_dir_index_row "$dir" "$now" >> "$output_file"
    done < <(
      fd --type d --hidden "${follow_args[@]}" --max-depth "$TO_MAX_DEPTH" \
        "${exclude_args[@]}" . "$root" 2>/dev/null
    )
  else
    local -a prune_expr
    prune_expr=("${(@f)$(_to_prune_expr_find)}")
    if (( ${#prune_expr} > 0 )); then
      while IFS= read -r dir; do
        _to_dir_index_row "$dir" "$now" >> "$output_file"
      done < <(
        find "$root" -maxdepth "$TO_MAX_DEPTH" \( "${prune_expr[@]}" \) -prune -o -type d -print 2>/dev/null
      )
    else
      while IFS= read -r dir; do
        _to_dir_index_row "$dir" "$now" >> "$output_file"
      done < <(
        find "$root" -maxdepth "$TO_MAX_DEPTH" -type d -print 2>/dev/null
      )
    fi
  fi
}

_to_index_collect_tsv() {
  local output_file="$1"
  local -a roots
  local root root_tmp tmpfile now

  _to_load_roots
  roots=("${TO_ROOTS[@]}")
  mkdir -p "$TO_CONFIG_HOME" || return 1
  tmpfile="$output_file.tmp.$$"
  : > "$tmpfile" || return 1
  now="$(_to_now)" || return 1

  for root in "${roots[@]}"; do
    [[ -d "$root" ]] || continue
    root_tmp="$tmpfile.root.$$"
    _to_index_collect_root_tsv "$root" "$root_tmp" "$now" || continue
    cat "$root_tmp" >> "$tmpfile"
    rm -f "$root_tmp"
  done

  sort -u "$tmpfile" > "$output_file" 2>/dev/null || mv "$tmpfile" "$output_file"
  rm -f "$tmpfile"
}

_to_index_rebuild_sqlite() {
  local tmp="$TO_CONFIG_HOME/index.tsv.tmp.$$"
  local tokens_tmp="$TO_CONFIG_HOME/tokens.tsv.tmp.$$"

  mkdir -p "$TO_CONFIG_HOME" || return 1
  _to_index_collect_tsv "$tmp" || return 1
  _to_index_collect_tokens_tsv "$tmp" "$tokens_tmp" || return 1
  sqlite3 "$TO_INDEX_FILE" >/dev/null <<SQL || return 1
pragma journal_mode=off;
pragma synchronous=0;
pragma cache_size=20000;
drop table if exists tokens;
drop table if exists dirs;
create table if not exists roots(
  path text primary key,
  mtime integer not null default 0,
  config_key text not null default '',
  last_indexed integer not null default 0
);
create table if not exists aliases(
  name text primary key,
  path text not null
);
create table if not exists workspaces(
  name text primary key,
  path text not null
);
create table if not exists recent(
  path text primary key,
  last_used integer not null
);
create table if not exists history(
  path text primary key,
  visits integer not null default 0,
  last_used integer not null default 0
);
create table if not exists stats(
  key text primary key,
  value text not null default ''
);
create table if not exists files(
  path text primary key,
  name text not null,
  lower_name text not null,
  stem text not null,
  lower_stem text not null,
  parent text not null,
  depth integer not null default 0,
  last_seen integer not null default 0
);
create table dirs(
  id integer primary key,
  path text unique not null,
  name text not null,
  lower_name text not null,
  parent text not null,
  depth integer not null,
  is_git integer not null,
  repo integer not null,
  repo_name text not null,
  last_seen integer not null,
  last_used integer not null default 0,
  hit_count integer not null default 0
);
create table tokens(
  token text not null,
  dir_id integer not null,
  primary key(token, dir_id)
);
create table __to_import_dirs(
  path text primary key,
  name text not null,
  lower_name text not null,
  parent text not null,
  depth integer not null,
  is_git integer not null,
  repo integer not null,
  repo_name text not null,
  last_seen integer not null,
  last_used integer not null default 0,
  hit_count integer not null default 0
);
create table __to_import_tokens(
  token text not null,
  path text not null,
  primary key(token, path)
);
begin transaction;
.mode tabs
.import ${tmp} __to_import_dirs
.import ${tokens_tmp} __to_import_tokens
insert into dirs(path, name, lower_name, parent, depth, is_git, repo, repo_name, last_seen, last_used, hit_count)
select path, name, lower_name, parent, depth, is_git, repo, repo_name, last_seen, last_used, hit_count
from __to_import_dirs;
insert or ignore into tokens(token, dir_id)
select t.token, d.id
from __to_import_tokens t
join dirs d on d.path = t.path;
commit;
drop table __to_import_dirs;
drop table __to_import_tokens;
create index idx_dirs_lower_name on dirs(lower_name);
create index idx_dirs_is_git on dirs(is_git);
create index idx_dirs_repo on dirs(repo);
create index idx_dirs_repo_name on dirs(repo_name);
create index idx_dirs_depth on dirs(depth);
create index idx_dirs_last_used on dirs(last_used);
create index idx_dirs_path on dirs(path);
create index idx_tokens_token on tokens(token);
create index idx_tokens_dir_id on tokens(dir_id);
create index idx_files_lower_name on files(lower_name);
create index idx_files_lower_stem on files(lower_stem);
create index idx_files_parent on files(parent);
create index idx_history_last_used on history(last_used);
create index idx_history_path on history(path);
create index idx_stats_key on stats(key);
pragma journal_mode=delete;
SQL
  _TO_SQLITE_SCHEMA_READY_FILE="$TO_INDEX_FILE"
  rm -f "$tmp" "$tokens_tmp"
}

_to_index_root_needs_refresh_sqlite() {
  local root="${1:A}"
  local root_mtime="$2"
  local config_key="$3"
  local stored

  _to_index_ensure_sqlite_schema || return 0
  stored="$(sqlite3 "$TO_INDEX_FILE" "select mtime || char(9) || config_key from roots where path = $(_to_sql_quote "$root");" 2>/dev/null)"
  [[ "$stored" == "${root_mtime}	${config_key}" ]] && return 1
  return 0
}

_to_index_refresh_root_sqlite() {
  local root="${1:A}"
  local root_mtime="$2"
  local now="$3"
  local config_key="$4"
  local tmp="$TO_CONFIG_HOME/index.${$}.dirs.tsv"
  local tokens_tmp="$TO_CONFIG_HOME/index.${$}.tokens.tsv"
  local root_like

  mkdir -p "$TO_CONFIG_HOME" || return 1
  _to_index_collect_root_tsv "$root" "$tmp" "$now" || return 1
  _to_index_collect_tokens_tsv "$tmp" "$tokens_tmp" || return 1
  root_like="${root}/%"

  sqlite3 "$TO_INDEX_FILE" >/dev/null <<SQL || return 1
pragma journal_mode=off;
pragma synchronous=0;
pragma cache_size=20000;
drop table if exists __to_import_dirs;
drop table if exists __to_import_tokens;
create table __to_import_dirs(
  path text primary key,
  name text not null,
  lower_name text not null,
  parent text not null,
  depth integer not null,
  is_git integer not null,
  repo integer not null,
  repo_name text not null,
  last_seen integer not null,
  last_used integer not null default 0,
  hit_count integer not null default 0
);
create table __to_import_tokens(
  token text not null,
  path text not null,
  primary key(token, path)
);
.mode tabs
.import ${tmp} __to_import_dirs
.import ${tokens_tmp} __to_import_tokens
begin transaction;
delete from files
where path = $(_to_sql_quote "$root")
   or path like $(_to_sql_quote "$root_like");
delete from tokens
where dir_id in (
  select id from dirs where path = $(_to_sql_quote "$root") or path like $(_to_sql_quote "$root_like")
);
delete from dirs
where (path = $(_to_sql_quote "$root") or path like $(_to_sql_quote "$root_like"))
  and path not in (select path from __to_import_dirs);
insert or replace into dirs(path, name, lower_name, parent, depth, is_git, repo, repo_name, last_seen, last_used, hit_count)
select
  i.path,
  i.name,
  i.lower_name,
  i.parent,
  i.depth,
  i.is_git,
  i.repo,
  i.repo_name,
  i.last_seen,
  coalesce((select d.last_used from dirs d where d.path = i.path), 0),
  coalesce((select d.hit_count from dirs d where d.path = i.path), 0)
from __to_import_dirs i;
insert or ignore into tokens(token, dir_id)
select t.token, d.id
from __to_import_tokens t
join dirs d on d.path = t.path;
insert or replace into roots(path, mtime, config_key, last_indexed)
values($(_to_sql_quote "$root"), $root_mtime, $(_to_sql_quote "$config_key"), $now);
commit;
drop table if exists __to_import_dirs;
drop table if exists __to_import_tokens;
pragma journal_mode=delete;
SQL
  rm -f "$tmp" "$tokens_tmp"
}

_to_index_prune_removed_roots_sqlite() {
  local -a active_roots quoted_roots
  local root active_list

  _to_load_roots
  active_roots=("${TO_ROOTS[@]}")
  for root in "${active_roots[@]}"; do
    quoted_roots+=("$(_to_sql_quote "${root:A}")")
  done
  active_list="${(j:,:)quoted_roots}"
  [[ -n "$active_list" ]] || active_list="''"

  sqlite3 "$TO_INDEX_FILE" >/dev/null 2>/dev/null <<SQL
delete from tokens
where dir_id in (
  select d.id
  from dirs d
  join roots r on d.path = r.path or d.path like r.path || '/%'
  where r.path not in ($active_list)
);
delete from files
where path in (
  select f.path
  from files f
  join roots r on f.path = r.path or f.path like r.path || '/%'
  where r.path not in ($active_list)
);
delete from dirs
where path in (
  select d.path
  from dirs d
  join roots r on d.path = r.path or d.path like r.path || '/%'
  where r.path not in ($active_list)
);
delete from history
where path in (
  select h.path
  from history h
  join roots r on h.path = r.path or h.path like r.path || '/%'
  where r.path not in ($active_list)
);
delete from roots where path not in ($active_list);
SQL
}

_to_index_reindex_incremental_sqlite() {
  local -a roots
  local root root_mtime now config_key changed=0 skipped=0

  mkdir -p "$TO_CONFIG_HOME" || return 1
  _to_index_ensure_sqlite_schema || return 1
  _to_load_roots
  roots=("${TO_ROOTS[@]}")
  now="$(_to_now)" || {
    print -r -- "unknown"
    return
  }
  config_key="$(_to_index_config_key)"

  for root in "${roots[@]}"; do
    [[ -d "$root" ]] || continue
    root="${root:A}"
    root_mtime="$(_to_root_mtime "$root")"
    if _to_index_root_needs_refresh_sqlite "$root" "$root_mtime" "$config_key"; then
      _to_index_refresh_root_sqlite "$root" "$root_mtime" "$now" "$config_key" || return 1
      (( ++changed ))
    else
      print -u2 -- "to: index fresh $root"
      (( ++skipped ))
    fi
  done

  _to_index_prune_removed_roots_sqlite
  _to_stat_set last_reindex "$now"
  print -r -- "to: indexed $changed root(s), skipped $skipped fresh root(s) into $TO_INDEX_FILE"
}

_to_index_rebuild_tsv() {
  _to_index_collect_tsv "$TO_INDEX_TSV_FILE"
}

_to_reindex() {
  if [[ -n "$TO_HELPER" && -x "$TO_HELPER" ]]; then
    local -a roots args
    local root now root_mtime config_key fresh changed=0 skipped=0

    mkdir -p "$TO_CONFIG_HOME" || return 1
    _to_load_roots
    roots=("${TO_ROOTS[@]}")
    now="$(_to_now)" || return 1
    config_key="$(_to_index_config_key)"
    for root in "${roots[@]}"; do
      [[ -d "$root" ]] || continue
      root="${root:A}"
      root_mtime="$(_to_root_mtime "$root")"
      fresh="$("$TO_HELPER" root-fresh --db "$TO_INDEX_FILE" --root "$root" --mtime "$root_mtime" --config-key "$config_key" 2>/dev/null)"
      if [[ "$fresh" == 1 ]]; then
        print -u2 -- "to: index fresh $root"
        (( ++skipped ))
        continue
      fi
      args=(index-root --db "$TO_INDEX_FILE" --root "$root" --now "$now" --mtime "$root_mtime" --config-key "$config_key" --max-depth "$TO_MAX_DEPTH" --reachignore "$TO_REACHIGNORE")
      (( TO_FOLLOW_SYMLINKS == 1 )) && args+=(--follow-links)
      (( TO_USE_GITIGNORE == 0 )) && args+=(--no-gitignore)
      "$TO_HELPER" "${args[@]}" || return 1
      (( ++changed ))
    done
    _to_stat_set last_reindex "$now"
    print -r -- "to: indexed $changed root(s), skipped $skipped fresh root(s) into $TO_INDEX_FILE"
    return
  fi

  if command -v sqlite3 >/dev/null 2>&1; then
    _to_index_reindex_incremental_sqlite || return 1
  else
    _to_index_rebuild_tsv || return 1
    print -r -- "to: sqlite3 not found; indexed roots into $TO_INDEX_TSV_FILE"
  fi
}

_to_index_query_sqlite() {
  local mode="$1"
  shift
  local -a queries clauses token_values
  local query first sql where token_list

  [[ -r "$TO_INDEX_FILE" ]] || return 1
  _to_index_ensure_sqlite_schema || return 1

  queries=("${(@L)@}")
  query="${(j: :)queries}"
  first="${queries[1]:-}"
  for query in "${queries[@]}"; do
    clauses+=("lower(path) like $(_to_sql_quote "%$query%")")
    token_values+=("$(_to_sql_quote "$query")")
  done
  where="${(j: and :)clauses}"
  token_list="${(j:,:)token_values}"

  case "$mode" in
    exact)
      [[ ${#queries} == 1 ]] || return 1
      sql="select path from dirs where lower_name = $(_to_sql_quote "$first") order by last_used desc, hit_count desc, depth asc, length(path), path limit 50;"
      ;;
    token)
      [[ -n "$token_list" ]] || return 1
      sql="select d.path from dirs d join tokens t on t.dir_id = d.id where t.token in ($token_list) group by d.path having count(distinct t.token) = ${#queries} order by case when d.lower_name = $(_to_sql_quote "$first") then 0 else 1 end, d.last_used desc, d.hit_count desc, d.depth asc, length(d.path), d.path limit 50;"
      ;;
    path)
      [[ -n "$where" ]] || return 1
      sql="select path from dirs where $where order by case when lower_name = $(_to_sql_quote "$first") then 0 else 1 end, last_used desc, hit_count desc, depth asc, length(path), path limit 50;"
      ;;
    git)
      [[ -n "$token_list" ]] || return 1
      sql="select d.path from dirs d join tokens t on t.dir_id = d.id where d.repo = 1 and t.token in ($token_list) group by d.path having count(distinct t.token) = ${#queries} order by case when d.repo_name = $(_to_sql_quote "$first") then 0 else 1 end, d.last_used desc, d.hit_count desc, d.depth asc, length(d.path), d.path limit 50;"
      ;;
    *)
      return 1
      ;;
  esac

  sqlite3 -noheader "$TO_INDEX_FILE" "$sql" 2>/dev/null
}

_to_index_query_tsv() {
  local mode="$1"
  shift
  local -a queries
  local query line row_path name lower_name parent depth is_git repo repo_name last_seen last_used hit_count
  local path_l ok part

  [[ -r "$TO_INDEX_TSV_FILE" ]] || return 1
  queries=("${(@L)@}")
  query="${(j: :)queries}"

  while IFS=$'\t' read -r row_path name lower_name parent depth is_git repo repo_name last_seen last_used hit_count; do
    [[ -d "$row_path" ]] || continue
    if [[ -z "$last_used" && -z "$hit_count" ]]; then
      hit_count="$last_seen"
      last_used="$repo_name"
      last_seen="$repo"
      repo="$is_git"
      repo_name=""
      [[ "$repo" == 1 ]] && repo_name="$lower_name"
    fi
    if [[ -z "$repo" ]]; then
      is_git="$parent"
      parent="${row_path:h}"
      depth="$(_to_dir_depth "$row_path")"
      repo="$is_git"
      repo_name="$lower_name"
    fi
    path_l="${(L)row_path}"
    case "$mode" in
      exact)
        [[ "$lower_name" == "$query" ]] && print -r -- "$row_path"
        ;;
      token)
        ok=1
        for part in "${queries[@]}"; do
          if ! _to_dir_has_token "$row_path" "$part"; then
            ok=0
            break
          fi
        done
        (( ok == 1 )) && print -r -- "$row_path"
        ;;
      path)
        ok=1
        for part in "${queries[@]}"; do
          [[ "$path_l" == *"$part"* ]] || {
            ok=0
            break
          }
        done
        (( ok == 1 )) && print -r -- "$row_path"
        ;;
      git)
        ok=1
        for part in "${queries[@]}"; do
          if ! _to_dir_has_token "$row_path" "$part"; then
            ok=0
            break
          fi
        done
        [[ "${repo:-$is_git}" == 1 && "$ok" == 1 ]] && print -r -- "$row_path"
        ;;
    esac
  done < "$TO_INDEX_TSV_FILE"
}

_to_index_delete_path() {
  local target_path="${1:A}"
  local tmp line item

  if [[ -r "$TO_INDEX_FILE" ]] && { [[ -n "$TO_HELPER" && -x "$TO_HELPER" ]] || command -v sqlite3 >/dev/null 2>&1; }; then
    _to_index_ensure_sqlite_schema || return 0
    if [[ -n "$TO_HELPER" && -x "$TO_HELPER" ]]; then
      "$TO_HELPER" delete-path --db "$TO_INDEX_FILE" --path "$target_path" >/dev/null 2>/dev/null
    else
      sqlite3 "$TO_INDEX_FILE" "delete from tokens where dir_id in (select id from dirs where path = $(_to_sql_quote "$target_path")); delete from dirs where path = $(_to_sql_quote "$target_path");" >/dev/null 2>/dev/null
    fi
    return 0
  fi

  [[ -r "$TO_INDEX_TSV_FILE" ]] || return 0
  tmp="$TO_INDEX_TSV_FILE.tmp.$$"
  : > "$tmp" || return 0
  while IFS= read -r line; do
    item="${line%%	*}"
    [[ "${item:A}" == "$target_path" ]] && continue
    print -r -- "$line" >> "$tmp"
  done < "$TO_INDEX_TSV_FILE"
  mv "$tmp" "$TO_INDEX_TSV_FILE"
}

_to_index_delete_file_path() {
  local target_path="${1:A}"

  if [[ -r "$TO_INDEX_FILE" ]] && { [[ -n "$TO_HELPER" && -x "$TO_HELPER" ]] || command -v sqlite3 >/dev/null 2>&1; }; then
    _to_index_ensure_sqlite_schema || return 0
    if [[ -n "$TO_HELPER" && -x "$TO_HELPER" ]]; then
      "$TO_HELPER" delete-file --db "$TO_INDEX_FILE" --path "$target_path" >/dev/null 2>/dev/null
    else
      sqlite3 "$TO_INDEX_FILE" "delete from files where path = $(_to_sql_quote "$target_path");" >/dev/null 2>/dev/null
    fi
  fi
}

_to_index_filter_existing() {
  local candidate_path

  for candidate_path in "$@"; do
    [[ -n "$candidate_path" ]] || continue
    if [[ -d "$candidate_path" ]]; then
      print -r -- "${candidate_path:A}"
    else
      _to_index_delete_path "$candidate_path"
    fi
  done
}

_to_index_filter_existing_files_to_parents() {
  local file_path parent
  local -a parents seen

  for file_path in "$@"; do
    [[ -n "$file_path" ]] || continue
    if [[ -f "$file_path" ]]; then
      parent="${file_path:A:h}"
      [[ -d "$parent" ]] || continue
      if (( ${seen[(Ie)$parent]} == 0 )); then
        seen+=("$parent")
        parents+=("$parent")
      fi
    else
      _to_index_delete_file_path "$file_path"
    fi
  done

  (( ${#parents} > 0 )) || return 1
  printf '%s\n' "${parents[@]}"
}

_to_index_query_files_sqlite() {
  local query="${(L)1}"
  local sql
  local -a matches

  [[ -r "$TO_INDEX_FILE" ]] || return 1
  _to_index_ensure_sqlite_schema || return 1

  if [[ -n "$TO_HELPER" && -x "$TO_HELPER" ]]; then
    matches=("${(@f)$("$TO_HELPER" query-file --db "$TO_INDEX_FILE" -- "$query" 2>/dev/null)}")
    _to_index_filter_existing_files_to_parents "${matches[@]}"
    return
  fi

  if _to_query_has_extension "$query"; then
    sql="select path from files where lower_name = $(_to_sql_quote "$query") order by depth asc, length(parent), parent, path limit 100;"
  else
    sql="select path from files where lower_name = $(_to_sql_quote "$query") or lower_stem = $(_to_sql_quote "$query") order by case when lower_name = $(_to_sql_quote "$query") then 0 else 1 end, depth asc, length(parent), parent, path limit 100;"
  fi

  matches=("${(@f)$(sqlite3 -noheader "$TO_INDEX_FILE" "$sql" 2>/dev/null)}")
  _to_index_filter_existing_files_to_parents "${matches[@]}"
}

_to_index_upsert_file_sqlite() {
  local file="${1:A}"
  local now
  local name stem parent depth

  [[ -f "$file" ]] || return 0
  _to_index_ensure_sqlite_schema || return 0
  now="$(_to_now)" || return 0
  if [[ -n "$TO_HELPER" && -x "$TO_HELPER" ]]; then
    "$TO_HELPER" upsert-file --db "$TO_INDEX_FILE" --path "$file" --now "$now" >/dev/null 2>/dev/null
    return 0
  fi
  name="${file:t}"
  stem="$(_to_file_stem "$name")"
  parent="${file:h}"
  depth="$(_to_dir_depth "$parent")"

  sqlite3 "$TO_INDEX_FILE" >/dev/null 2>/dev/null <<SQL
insert or replace into files(path, name, lower_name, stem, lower_stem, parent, depth, last_seen)
values(
  $(_to_sql_quote "$file"),
  $(_to_sql_quote "$name"),
  $(_to_sql_quote "${(L)name}"),
  $(_to_sql_quote "$stem"),
  $(_to_sql_quote "${(L)stem}"),
  $(_to_sql_quote "$parent"),
  $depth,
  $now
);
SQL
}

_to_index_upsert_file() {
  local file="${1:A}"

  [[ -f "$file" ]] || return 0
  _to_index_upsert_file_sqlite "$file"
}

_to_helper_query() {
  local mode="$1"
  shift

  [[ -n "$TO_HELPER" && -x "$TO_HELPER" && -r "$TO_INDEX_FILE" ]] || return 1
  _to_index_ensure_sqlite_schema || return 1
  "$TO_HELPER" query --db "$TO_INDEX_FILE" --mode "$mode" -- "$@" 2>/dev/null
}

_to_index_query() {
  local mode="$1"
  shift
  local -a matches

  if [[ -n "$TO_HELPER" && -x "$TO_HELPER" && -r "$TO_INDEX_FILE" ]]; then
    matches=("${(@f)$(_to_helper_query "$mode" "$@")}")
    matches=("${(@)matches:#}")
    if (( ${#matches} > 0 )); then
      _to_index_filter_existing "${matches[@]}"
      return
    fi
  fi

  if command -v sqlite3 >/dev/null 2>&1 && [[ -r "$TO_INDEX_FILE" ]]; then
    matches=("${(@f)$(_to_index_query_sqlite "$mode" "$@")}")
    _to_index_filter_existing "${matches[@]}"
  elif [[ -r "$TO_INDEX_TSV_FILE" ]]; then
    matches=("${(@f)$(_to_index_query_tsv "$mode" "$@")}")
    _to_index_filter_existing "${matches[@]}"
  else
    return 1
  fi
}

_to_index_upsert_dir_sqlite() {
  local dir="${1:A}"
  local now
  local name parent depth is_git repo repo_name
  local -a tokens token_values
  local token values_sql

  [[ -d "$dir" ]] || return 0
  _to_index_ensure_sqlite_schema || return 0
  now="$(_to_now)" || return 0
  name="${dir:t}"
  parent="${dir:h}"
  depth="$(_to_dir_depth "$dir")"
  is_git=0
  repo=0
  repo_name=""
  if [[ -d "$dir/.git" || -f "$dir/.git" ]]; then
    is_git=1
    repo=1
    repo_name="${(L)name}"
  fi
  tokens=("${(@f)$(_to_dir_tokens "$dir")}")
  for token in "${tokens[@]}"; do
    [[ -n "$token" ]] || continue
    token_values+=("($(_to_sql_quote "$token"), (select id from dirs where path = $(_to_sql_quote "$dir")))")
  done
  values_sql="${(j:,:)token_values}"

  sqlite3 "$TO_INDEX_FILE" >/dev/null 2>/dev/null <<SQL
insert into dirs(path, name, lower_name, parent, depth, is_git, repo, repo_name, last_seen, last_used, hit_count)
values(
  $(_to_sql_quote "$dir"),
  $(_to_sql_quote "$name"),
  $(_to_sql_quote "${(L)name}"),
  $(_to_sql_quote "$parent"),
  $depth,
  $is_git,
  $repo,
  $(_to_sql_quote "$repo_name"),
  $now,
  $now,
  coalesce((select hit_count from dirs where path = $(_to_sql_quote "$dir")), 0) + 1
)
on conflict(path) do update set
  name = excluded.name,
  lower_name = excluded.lower_name,
  parent = excluded.parent,
  depth = excluded.depth,
  is_git = excluded.is_git,
  repo = excluded.repo,
  repo_name = excluded.repo_name,
  last_seen = excluded.last_seen,
  last_used = excluded.last_used,
  hit_count = dirs.hit_count + 1;
delete from tokens where dir_id in (select id from dirs where path = $(_to_sql_quote "$dir"));
SQL
  if [[ -n "$values_sql" ]]; then
    sqlite3 "$TO_INDEX_FILE" "insert or ignore into tokens(token, dir_id) values $values_sql;" >/dev/null 2>/dev/null
  fi
}

_to_index_upsert_dir_tsv() {
  local dir="${1:A}"
  local tmp line item

  [[ -d "$dir" ]] || return 0
  mkdir -p "$TO_CONFIG_HOME" || return 0
  tmp="$TO_INDEX_TSV_FILE.tmp.$$"
  : > "$tmp" || return 0
  if [[ -r "$TO_INDEX_TSV_FILE" ]]; then
    while IFS= read -r line; do
      item="${line%%	*}"
      [[ "${item:A}" == "$dir" ]] && continue
      print -r -- "$line" >> "$tmp"
    done < "$TO_INDEX_TSV_FILE"
  fi
  _to_dir_index_row "$dir" >> "$tmp"
  mv "$tmp" "$TO_INDEX_TSV_FILE"
}

_to_index_upsert_dir() {
  local dir="${1:A}"
  local now

  [[ -d "$dir" ]] || return 0
  if [[ -n "$TO_HELPER" && -x "$TO_HELPER" ]]; then
    _to_index_ensure_sqlite_schema >/dev/null 2>&1 || return 0
    now="$(_to_now)" || return 0
    "$TO_HELPER" upsert-dir --db "$TO_INDEX_FILE" --path "$dir" --now "$now" >/dev/null 2>/dev/null
    return 0
  fi
  now="$(_to_now)" || return 0
  if command -v sqlite3 >/dev/null 2>&1; then
    _to_index_upsert_dir_sqlite "$dir"
  else
    _to_index_upsert_dir_tsv "$dir"
  fi
}

_to_dir_is_under_configured_root() {
  local dir="${1:A}"
  local root

  _to_load_roots
  for root in "${TO_ROOTS[@]}"; do
    root="${root:A}"
    [[ "$dir" == "$root" || "$dir" == "$root"/* ]] && return 0
  done

  return 1
}

_to_add_root_silent() {
  local dir="${1:A}"

  [[ -d "$dir" ]] || return 1
  _to_load_roots
  TO_ROOTS=("${(@f)$(_to_unique_existing_dirs "$dir" "${TO_ROOTS[@]}")}")
  _to_save_roots
}

_to_maybe_add_external_root() {
  local dir="${1:A}"
  local parent reply

  [[ -d "$dir" ]] || return 0
  _to_dir_is_under_configured_root "$dir" && return 0

  parent="${dir:h}"
  [[ -d "$parent" ]] || return 0
  _to_root_is_safe_to_add "$parent" || {
    print -u2 -- "to: found $dir outside your roots; not adding broad system root $parent"
    print -u2 -- "to: add a safer, narrower root with: to use <dir>"
    return 0
  }
  if (( TO_AUTO_ADD_ROOTS == 1 )); then
    _to_add_root_silent "$parent" && print -u2 -- "to: added search root $parent"
    return 0
  fi

  [[ -t 0 && -t 2 ]] || {
    print -u2 -- "to: found $dir outside your roots; add it with: to use ${(q)parent}"
    return 0
  }

  printf 'to: found %s outside your roots. Add %s as a search root? [y/N] ' "$dir" "$parent" >&2
  read -r reply
  case "${(L)reply}" in
    y|yes)
      _to_add_root_silent "$parent" && print -u2 -- "to: added search root $parent"
      ;;
    *)
      print -u2 -- "to: leaving roots unchanged"
      ;;
  esac
}

_to_after_cd() {
  local dir="${1:A}"

  [[ -d "$dir" ]] || return 0
  _to_record_recent "$dir"
  _to_record_frecency "$dir"
  _to_index_upsert_dir "$dir"
}

_to_first_exact_match() {
  local roots_ref="$1"
  local query="$2"
  local -a search_roots matches
  local root match best

  [[ "$query" != */* ]] || return 1

  eval "search_roots=(\"\${${roots_ref}[@]}\")"

  matches=("${(@f)$(_to_index_query exact "$query")}")
  matches=("${(@)matches:#}")
  if (( ${#matches} > 0 )); then
    _to_record_search_outcome "SQLite Hit"
    print -r -- "${matches[1]:A}"
    return
  fi

  for root in "${search_roots[@]}"; do
    [[ -d "$root" ]] || continue
    matches=("${(@f)$(_to_search_exact_name "$root" "$query")}")
    matches=("${(@)matches:#}")
    if (( ${#matches} > 0 )); then
      best="${matches[1]:A}"
      for match in "${matches[@]}"; do
        match="${match:A}"
        (( ${#match} < ${#best} )) && best="$match"
      done
      print -r -- "$best"
      _to_record_search_outcome "Filesystem Fallback"
      return
    fi
  done

  return 1
}

_to_dir_matches_query() {
  local dir="$1"
  shift
  local query part haystack name

  haystack="${(L)dir}"
  name="${(L)dir:t}"

  if (( $# == 1 )); then
    query="${(L)1}"
    [[ "$name" == "$query" || "$haystack" == *"$query"* ]]
    return
  fi

  for part in "$@"; do
    part="${(L)part}"
    [[ "$haystack" == *"$part"* ]] || return 1
  done
}

_to_dir_matches_exact_name() {
  local dir="$1"
  shift
  local query_l name_l

  (( $# == 1 )) || return 1
  query_l="${(L)1}"
  name_l="${(L)dir:t}"
  [[ "$name_l" == "$query_l" ]]
}

_to_dir_matches_path_fragment() {
  local dir="$1"
  shift
  local query_l haystack

  (( $# == 1 )) || return 1
  query_l="${(L)1}"
  haystack="${(L)dir}"
  [[ "$query_l" == */* && "$haystack" == *"$query_l"* ]]
}

_to_match_mode_allows() {
  local mode="$1"
  shift
  local dir="$1"
  shift

  case "$mode" in
    exact)
      _to_dir_matches_exact_name "$dir" "$@"
      ;;
    path)
      _to_dir_matches_path_fragment "$dir" "$@"
      ;;
    broad)
      _to_dir_matches_query "$dir" "$@"
      ;;
    *)
      return 1
      ;;
  esac
}

_to_prune_descendant_matches() {
  local -a kept next
  local dir existing
  local skip

  for dir in "$@"; do
    skip=0
    next=()

    for existing in "${kept[@]}"; do
      if [[ "$dir" == "$existing"/* ]]; then
        skip=1
        next+=("$existing")
      elif [[ "$existing" == "$dir"/* ]]; then
        continue
      else
        next+=("$existing")
      fi
    done

    kept=("${next[@]}")
    (( skip == 0 )) && kept+=("$dir")
  done

  printf '%s\n' "${kept[@]}"
}

_to_rank_matches() {
  local -a exact fragment other candidates ai_ranked seen
  local dir query_l name_l ai_input

  query_l="${(L)${(j: :)@}}"
  while IFS= read -r dir; do
    [[ -d "$dir" ]] || continue
    name_l="${(L)dir:t}"
    if [[ "$name_l" == "$query_l" ]]; then
      exact+=("$dir")
    elif [[ "${(L)dir}" == *"$query_l"* ]]; then
      fragment+=("$dir")
    else
      other+=("$dir")
    fi
  done

  candidates=("${exact[@]}" "${fragment[@]}" "${other[@]}")
  if [[ -n "$TO_AI_RANK_COMMAND" && ${#candidates} -gt 1 ]]; then
    ai_input="${TMPDIR:-/tmp}/to-ai-rank.${$}"
    printf '%s\n' "${candidates[@]}" > "$ai_input" || ai_input=""
    if [[ -n "$ai_input" ]]; then
      ai_ranked=("${(@f)$(eval "$TO_AI_RANK_COMMAND ${(q)query_l}" < "$ai_input" 2>/dev/null)}")
      rm -f "$ai_input"
    fi
    for dir in "${ai_ranked[@]}"; do
      [[ -d "$dir" ]] || continue
      if (( ${candidates[(Ie)$dir]} > 0 && ${seen[(Ie)$dir]} == 0 )); then
        seen+=("$dir")
        print -r -- "$dir"
      fi
    done
    for dir in "${candidates[@]}"; do
      if (( ${seen[(Ie)$dir]} == 0 )); then
        seen+=("$dir")
        print -r -- "$dir"
      fi
    done
    return
  fi

  printf '%s\n' "${candidates[@]}"
}

_to_dir_usage_fields() {
  local dir="${1:A}"
  local fields recent_line recent_time

  if command -v sqlite3 >/dev/null 2>&1 && [[ -r "$TO_INDEX_FILE" ]]; then
    _to_index_ensure_sqlite_schema >/dev/null 2>&1
    fields="$(sqlite3 -noheader "$TO_INDEX_FILE" "select last_used || char(9) || hit_count from dirs where path = $(_to_sql_quote "$dir");" 2>/dev/null)"
    if [[ -n "$fields" ]]; then
      print -r -- "$fields"
      return
    fi
  fi

  recent_time=0
  if [[ -r "$TO_RECENT_FILE" ]]; then
    recent_line="$(grep -F "	$dir" "$TO_RECENT_FILE" 2>/dev/null | head -n 1)"
    [[ -n "$recent_line" ]] && recent_time="${recent_line%%	*}"
  fi
  print -r -- "${recent_time:-0}	0"
}

_to_dir_rank_depth() {
  local dir="${1:A}"
  local depth

  if command -v sqlite3 >/dev/null 2>&1 && [[ -r "$TO_INDEX_FILE" ]]; then
    _to_index_ensure_sqlite_schema >/dev/null 2>&1
    depth="$(sqlite3 -noheader "$TO_INDEX_FILE" "select depth from dirs where path = $(_to_sql_quote "$dir");" 2>/dev/null)"
    [[ "$depth" == <-> ]] && {
      print -r -- "$depth"
      return
    }
  fi

  _to_dir_depth "$dir"
}

_to_dir_is_better_rank() {
  local candidate="$1"
  local incumbent="$2"
  local candidate_last candidate_hits incumbent_last incumbent_hits
  local candidate_score incumbent_score candidate_frecency incumbent_frecency
  local candidate_depth incumbent_depth
  local candidate_fields incumbent_fields

  [[ -n "$incumbent" ]] || return 0
  candidate_frecency="$(_to_frecency_fields "$candidate")"
  incumbent_frecency="$(_to_frecency_fields "$incumbent")"
  candidate_score="${candidate_frecency%%	*}"
  incumbent_score="${incumbent_frecency%%	*}"
  (( ${candidate_score:-0} > ${incumbent_score:-0} )) && return 0
  (( ${candidate_score:-0} < ${incumbent_score:-0} )) && return 1

  candidate_fields="$(_to_dir_usage_fields "$candidate")"
  incumbent_fields="$(_to_dir_usage_fields "$incumbent")"
  candidate_last="${candidate_fields%%	*}"
  candidate_hits="${candidate_fields#*	}"
  incumbent_last="${incumbent_fields%%	*}"
  incumbent_hits="${incumbent_fields#*	}"

  (( ${candidate_last:-0} > ${incumbent_last:-0} )) && return 0
  (( ${candidate_last:-0} < ${incumbent_last:-0} )) && return 1
  (( ${candidate_hits:-0} > ${incumbent_hits:-0} )) && return 0
  (( ${candidate_hits:-0} < ${incumbent_hits:-0} )) && return 1
  candidate_depth="$(_to_dir_rank_depth "$candidate")"
  incumbent_depth="$(_to_dir_rank_depth "$incumbent")"
  (( ${candidate_depth:-0} < ${incumbent_depth:-0} )) && return 0
  (( ${candidate_depth:-0} > ${incumbent_depth:-0} )) && return 1
  (( ${#candidate} < ${#incumbent} ))
}

_to_rank_dirs_by_usage() {
  local -a remaining ranked next
  local dir best

  remaining=("$@")
  while (( ${#remaining} > 0 )); do
    best=""
    for dir in "${remaining[@]}"; do
      if _to_dir_is_better_rank "$dir" "$best"; then
        best="$dir"
      fi
    done
    [[ -n "$best" ]] || break
    ranked+=("$best")
    next=()
    for dir in "${remaining[@]}"; do
      [[ "$dir" == "$best" ]] || next+=("$dir")
    done
    remaining=("${next[@]}")
  done

  printf '%s\n' "${ranked[@]}"
}

_to_collect_file_parent_matches() {
  local roots_ref="$1"
  local query="$2"
  local -a search_roots parents ranked seen files cached
  local root file parent key

  [[ "$query" != */* ]] || return 1
  eval "search_roots=(\"\${${roots_ref}[@]}\")"

  cached=("${(@f)$(_to_index_query_files_sqlite "$query")}")
  cached=("${(@)cached:#}")
  if (( ${#cached} > 0 )); then
    _to_record_search_outcome "File Cache"
    ranked=("${(@f)$(_to_rank_dirs_by_usage "${cached[@]}")}")
    printf '%s\n' "${ranked[@]}"
    return
  fi

  for root in "${search_roots[@]}"; do
    [[ -d "$root" ]] || continue
    files=("${(@f)$(_to_search_exact_file "$root" "$query")}")
    for file in "${files[@]}"; do
      [[ -f "$file" ]] || continue
      _to_file_matches_query "$file" "$query" || continue
      parent="${file:A:h}"
      [[ -d "$parent" ]] || continue
      key="${parent:A}"
      if (( ${seen[(Ie)$key]} == 0 )); then
        seen+=("$key")
        parents+=("$key")
      fi
      _to_index_upsert_dir "$parent"
      _to_index_upsert_file "$file"
    done
  done

  (( ${#parents} > 0 )) || return 1
  _to_record_search_outcome "Filesystem Fallback"
  ranked=("${(@f)$(_to_rank_dirs_by_usage "${parents[@]}")}")
  printf '%s\n' "${ranked[@]}"
}

_to_search_marker_file() {
  local root="$1"
  local marker="$2"
  local -a exclude_args follow_args prune_expr

  if command -v fd >/dev/null 2>&1; then
    exclude_args=("${(@f)$(_to_exclude_args_fd)}")
    (( TO_FOLLOW_SYMLINKS == 1 )) && follow_args=(--follow)
    fd --type f --hidden "${follow_args[@]}" --max-depth "$TO_MAX_DEPTH" \
      --glob --ignore-case "${exclude_args[@]}" "$marker" "$root" 2>/dev/null
    return
  fi

  prune_expr=("${(@f)$(_to_prune_expr_find)}")
  if (( ${#prune_expr} > 0 )); then
    find "$root" -maxdepth "$TO_MAX_DEPTH" \( "${prune_expr[@]}" \) -prune -o -type f -iname "$marker" -print 2>/dev/null
  else
    find "$root" -maxdepth "$TO_MAX_DEPTH" -type f -iname "$marker" -print 2>/dev/null
  fi
}

_to_file_contains_all_terms() {
  local file="$1"
  shift
  local term

  [[ -f "$file" ]] || return 1
  (( $# > 0 )) || return 0
  for term in "$@"; do
    command grep -I -i -F -q -- "$term" "$file" 2>/dev/null || return 1
  done
}

_to_parent_matches_terms() {
  local parent="$1"
  shift
  local haystack="${(L)parent}"
  local term

  for term in "$@"; do
    term="${(L)term}"
    [[ "$haystack" == *"$term"* ]] || return 1
  done
}

_to_marker_parent_matches() {
  local kind="$1"
  shift
  local -a roots markers parents ranked seen
  local root marker file parent key

  _to_load_roots
  roots=("${TO_ROOTS[@]}")
  case "$kind" in
    cargo)
      markers=(Cargo.toml)
      ;;
    npm)
      markers=(package.json)
      ;;
    py)
      markers=(pyproject.toml setup.py setup.cfg requirements.txt)
      ;;
    docker)
      markers=(Dockerfile docker-compose.yml docker-compose.yaml compose.yml compose.yaml)
      ;;
    *)
      return 1
      ;;
  esac

  for root in "${roots[@]}"; do
    [[ -d "$root" ]] || continue
    for marker in "${markers[@]}"; do
      while IFS= read -r file; do
        [[ -f "$file" ]] || continue
        parent="${file:A:h}"
        if (( $# > 0 )); then
          _to_file_contains_all_terms "$file" "$@" || _to_parent_matches_terms "$parent" "$@" || continue
        fi
        key="${parent:A}"
        (( ${seen[(Ie)$key]} > 0 )) && continue
        seen+=("$key")
        parents+=("$key")
        _to_index_upsert_dir "$key"
      done < <(_to_search_marker_file "$root" "$marker")
    done
  done

  (( ${#parents} > 0 )) || return 1
  _to_record_search_outcome "Object Filesystem Fallback"
  ranked=("${(@f)$(_to_rank_dirs_by_usage "${parents[@]}")}")
  printf '%s\n' "${ranked[@]}"
}

_to_code_parent_matches() {
  local -a roots parents ranked seen exclude_args follow_args prune_expr find_matches
  local root file parent key term

  (( $# > 0 )) || return 1
  _to_load_roots
  roots=("${TO_ROOTS[@]}")

  for root in "${roots[@]}"; do
    [[ -d "$root" ]] || continue
    if command -v rg >/dev/null 2>&1; then
      local -a rg_excludes
      for term in "${TO_EXCLUDES[@]}"; do
        rg_excludes+=(--glob "!$term/**")
      done
      for term in "$@"; do
        while IFS= read -r file; do
          [[ -f "$file" ]] || continue
          _to_file_contains_all_terms "$file" "$@" || continue
          parent="${file:A:h}"
          key="${parent:A}"
          (( ${seen[(Ie)$key]} > 0 )) && continue
          seen+=("$key")
          parents+=("$key")
          _to_index_upsert_dir "$key"
        done < <(rg --files-with-matches --ignore-case --fixed-strings --hidden --max-depth "$TO_MAX_DEPTH" "${rg_excludes[@]}" -- "$term" "$root" 2>/dev/null)
        break
      done
    elif command -v fd >/dev/null 2>&1; then
      exclude_args=("${(@f)$(_to_exclude_args_fd)}")
      (( TO_FOLLOW_SYMLINKS == 1 )) && follow_args=(--follow)
      while IFS= read -r file; do
        [[ -f "$file" ]] || continue
        _to_file_contains_all_terms "$file" "$@" || continue
        parent="${file:A:h}"
        key="${parent:A}"
        (( ${seen[(Ie)$key]} > 0 )) && continue
        seen+=("$key")
        parents+=("$key")
        _to_index_upsert_dir "$key"
      done < <(fd --type f --hidden "${follow_args[@]}" --max-depth "$TO_MAX_DEPTH" "${exclude_args[@]}" . "$root" 2>/dev/null)
    else
      prune_expr=("${(@f)$(_to_prune_expr_find)}")
      if (( ${#prune_expr} > 0 )); then
        find_matches=("${(@f)$(find "$root" -maxdepth "$TO_MAX_DEPTH" \( "${prune_expr[@]}" \) -prune -o -type f -print 2>/dev/null)}")
      else
        find_matches=("${(@f)$(find "$root" -maxdepth "$TO_MAX_DEPTH" -type f -print 2>/dev/null)}")
      fi
      for file in "${find_matches[@]}"; do
        [[ -f "$file" ]] || continue
        _to_file_contains_all_terms "$file" "$@" || continue
        parent="${file:A:h}"
        key="${parent:A}"
        (( ${seen[(Ie)$key]} > 0 )) && continue
        seen+=("$key")
        parents+=("$key")
        _to_index_upsert_dir "$key"
      done
    fi
  done

  (( ${#parents} > 0 )) || return 1
  _to_record_search_outcome "Code Filesystem Fallback"
  ranked=("${(@f)$(_to_rank_dirs_by_usage "${parents[@]}")}")
  printf '%s\n' "${ranked[@]}"
}

_to_workspace_matches() {
  local query="${(L)1}"
  local line key value
  local -a matches ranked seen

  [[ -n "$query" ]] || return 1
  value="$(_to_workspace "$query")"
  if [[ -n "$value" ]]; then
    print -r -- "$value"
    return
  fi

  if [[ -n "workspaces" ]] && command -v sqlite3 >/dev/null 2>&1 && [[ -r "$TO_INDEX_FILE" ]]; then
    _to_index_ensure_sqlite_schema >/dev/null 2>&1
    _to_import_map_file_to_sqlite "$TO_WORKSPACES_FILE" workspaces
    matches=("${(@f)$(sqlite3 -noheader "$TO_INDEX_FILE" "select path from workspaces where name like $(_to_sql_quote "%$query%") or lower(path) like $(_to_sql_quote "%$query%") order by name, path limit 50;" 2>/dev/null)}")
  fi

  if [[ -r "$TO_WORKSPACES_FILE" ]]; then
    while IFS= read -r line; do
      key="${line%%	*}"
      value="${line#*	}"
      [[ "$value" == "$line" || ! -d "$value" ]] && continue
      [[ "${(L)key}" == *"$query"* || "${(L)value}" == *"$query"* ]] || continue
      matches+=("${value:A}")
    done < "$TO_WORKSPACES_FILE"
  fi

  for value in "${matches[@]}"; do
    [[ -d "$value" ]] || continue
    key="${value:A}"
    (( ${seen[(Ie)$key]} > 0 )) && continue
    seen+=("$key")
    ranked+=("$key")
  done
  (( ${#ranked} > 0 )) || return 1
  _to_rank_dirs_by_usage "${ranked[@]}"
}

_to_object_matches() {
  local kind="$1"
  shift
  local -a roots matches

  (( $# > 0 )) || return 2
  case "$kind" in
    file)
      _to_load_roots
      roots=("${TO_ROOTS[@]}")
      matches=("${(@f)$(_to_collect_file_parent_matches roots "$*")}")
      matches=("${(@)matches:#}")
      (( ${#matches} > 0 )) || return 1
      printf '%s\n' "${matches[@]}"
      ;;
    dir)
      _to_load_roots
      roots=("${TO_ROOTS[@]}")
      matches=("${(@f)$(_to_collect_matches roots "$@")}")
      matches=("${(@)matches:#}")
      (( ${#matches} > 0 )) || return 1
      printf '%s\n' "${matches[@]}"
      ;;
    ws)
      _to_workspace_matches "$*"
      ;;
    cargo|npm|py|docker)
      _to_marker_parent_matches "$kind" "$@"
      ;;
    code)
      _to_code_parent_matches "$@"
      ;;
    *)
      return 2
      ;;
  esac
}

_to_jump_to_object() {
  local kind="$1"
  shift
  local label target choose_status

  [[ $# -gt 0 ]] || {
    print -u2 -- "to: usage: to $kind <query...>"
    return 2
  }
  label="$kind"
  target="$(_to_choose_match 0 "${(@f)$(_to_object_matches "$kind" "$@")}")"
  choose_status=$?
  if (( choose_status == 2 )); then
    print -u2 -- "to: usage: to $kind <query...>"
    return 2
  fi
  if [[ $choose_status -ne 0 || -z "$target" ]]; then
    _to_record_search_outcome "Miss"
    _to_print_no_match_advice "$label" "$@"
    return 1
  fi
  cd "$target" && _to_after_cd "$PWD"
}

_to_collect_matches_for_mode() {
  local -a search_roots queries unique ranked
  local root dir key roots_ref mode
  local -a seen

  roots_ref="$1"
  mode="$2"
  eval "search_roots=(\"\${${roots_ref}[@]}\")"
  shift 2
  queries=("$@")

  if [[ -n "$TO_HELPER" && -x "$TO_HELPER" ]]; then
    local helper_mode="$mode"
    [[ "$helper_mode" == broad ]] && helper_mode=broad
    unique=("${(@f)$(_to_helper_scan_roots_ref "$roots_ref" dir "$helper_mode" 1 "${queries[@]}")}")
    unique=("${(@)unique:#}")
    if (( ${#unique} > 0 )); then
      unique=("${(@f)$(_to_prune_descendant_matches "${unique[@]}")}")
      ranked=("${(@f)$(printf '%s\n' "${unique[@]}" | _to_rank_matches "${queries[@]}")}")
      printf '%s\n' "${ranked[@]}"
      return
    fi
  fi

  for root in "${search_roots[@]}"; do
    [[ -d "$root" ]] || continue
    if [[ "$mode" == exact && ${#queries} == 1 && "$queries[1]" != */* ]]; then
      local -a exact_matches
      exact_matches=("${(@f)$(_to_search_exact_name "$root" "$queries[1]")}")
      for dir in "${exact_matches[@]}"; do
        [[ -d "$dir" ]] || continue
        _to_match_mode_allows "$mode" "$dir" "${queries[@]}" || continue
        key="${dir:A}"
        if (( ${seen[(Ie)$key]} == 0 )); then
          seen+=("$key")
          unique+=("$key")
        fi
      done
    elif command -v fd >/dev/null 2>&1; then
      local -a exclude_args follow_args
      exclude_args=("${(@f)$(_to_exclude_args_fd)}")
      (( TO_FOLLOW_SYMLINKS == 1 )) && follow_args=(--follow)
      while IFS= read -r dir; do
        dir="${dir%/}"
        [[ -n "$dir" ]] || continue
        _to_match_mode_allows "$mode" "$dir" "${queries[@]}" || continue
        key="$dir"
        if (( ${seen[(Ie)$key]} == 0 )); then
          seen+=("$key")
          unique+=("$key")
        fi
      done < <(
        fd --type d --hidden "${follow_args[@]}" --max-depth "$TO_MAX_DEPTH" \
          "${exclude_args[@]}" . "$root" 2>/dev/null
      )
    else
      local -a prune_expr find_matches
      prune_expr=("${(@f)$(_to_prune_expr_find)}")
      if (( ${#prune_expr} > 0 )); then
        find_matches=("${(@f)$(find "$root" -maxdepth "$TO_MAX_DEPTH" \( "${prune_expr[@]}" \) -prune -o -type d -print 2>/dev/null)}")
      else
        find_matches=("${(@f)$(find "$root" -maxdepth "$TO_MAX_DEPTH" -type d -print 2>/dev/null)}")
      fi
      for dir in "${find_matches[@]}"; do
        [[ -d "$dir" ]] || continue
        _to_match_mode_allows "$mode" "$dir" "${queries[@]}" || continue
        key="$dir"
        if (( ${seen[(Ie)$key]} == 0 )); then
          seen+=("$key")
          unique+=("$key")
        fi
      done
    fi
  done

  unique=("${(@f)$(_to_prune_descendant_matches "${unique[@]}")}")
  ranked=("${(@f)$(printf '%s\n' "${unique[@]}" | _to_rank_matches "${queries[@]}")}")
  printf '%s\n' "${ranked[@]}"
}

_to_collect_matches() {
  local roots_ref="$1"
  shift
  local -a queries matches

  queries=("$@")

  matches=("${(@f)$(_to_frecency_query_sqlite "$roots_ref" "${queries[@]}")}")
  matches=("${(@)matches:#}")
  if (( ${#matches} > 0 )); then
    _to_record_search_outcome "Frecency Hit"
    printf '%s\n' "${matches[@]}"
    return
  fi

  if (( ${#queries} == 1 )); then
    matches=("${(@f)$(_to_index_query exact "${queries[@]}")}")
    matches=("${(@)matches:#}")
    if (( ${#matches} > 0 )); then
      _to_record_search_outcome "SQLite Hit"
      printf '%s\n' "${matches[@]}"
      return
    fi
  fi

  if (( ${#queries} == 1 )) && [[ "$queries[1]" != */* ]]; then
    matches=("${(@f)$(_to_collect_matches_for_mode "$roots_ref" exact "${queries[@]}")}")
    matches=("${(@)matches:#}")
    if (( ${#matches} > 0 )); then
      _to_record_search_outcome "Filesystem Fallback"
      printf '%s\n' "${matches[@]}"
      return
    fi

    matches=("${(@f)$(_to_collect_file_parent_matches "$roots_ref" "$queries[1]")}")
    matches=("${(@)matches:#}")
    if (( ${#matches} > 0 )); then
      printf '%s\n' "${matches[@]}"
      return
    fi
  fi

  if (( ${#queries} == 1 )) && [[ "$queries[1]" == */* ]]; then
    matches=("${(@f)$(_to_index_query path "${queries[@]}")}")
    matches=("${(@)matches:#}")
    if (( ${#matches} > 0 )); then
      _to_record_search_outcome "SQLite Hit"
      printf '%s\n' "${(@f)$(_to_prune_descendant_matches "${matches[@]}")}"
      return
    fi

    matches=("${(@f)$(_to_collect_matches_for_mode "$roots_ref" path "${queries[@]}")}")
    matches=("${(@)matches:#}")
    if (( ${#matches} > 0 )); then
      _to_record_search_outcome "Filesystem Fallback"
      printf '%s\n' "${matches[@]}"
      return
    fi
  fi

  if (( TO_SEARCH_PATH_FRAGMENTS == 1 || ${#queries} > 1 )); then
    if (( ${#queries} > 1 )); then
      matches=("${(@f)$(_to_index_query token "${queries[@]}")}")
    else
      matches=("${(@f)$(_to_index_query path "${queries[@]}")}")
    fi
    matches=("${(@)matches:#}")
    if (( ${#matches} > 0 )); then
      _to_record_search_outcome "SQLite Hit"
      printf '%s\n' "${(@f)$(_to_prune_descendant_matches "${matches[@]}")}"
      return
    fi

    matches=("${(@f)$(_to_collect_matches_for_mode "$roots_ref" broad "${queries[@]}")}")
    matches=("${(@)matches:#}")
    if (( ${#matches} > 0 )); then
      _to_record_search_outcome "Filesystem Fallback"
      printf '%s\n' "${matches[@]}"
    fi
  fi
}

_to_choose_numbered() {
  local -a matches
  local reply choice
  local i

  matches=("$@")
  for i in {1..${#matches}}; do
    printf '%d) %s\n' "$i" "${matches[$i]}" >&2
  done

  printf 'to> ' >&2
  read -r reply
  [[ "$reply" == <-> ]] || return 1
  choice="$reply"
  (( choice >= 1 && choice <= ${#matches} )) || return 1
  print -r -- "${matches[$choice]}"
}

_to_choose_match() {
  local force_interactive="$1"
  shift
  local -a matches

  matches=("$@")
  (( ${#matches} > 0 )) || return 1

  if (( ${#matches} == 1 )) && [[ "$force_interactive" != 1 ]]; then
    print -r -- "$matches[1]"
    return
  fi

  if command -v fzf >/dev/null 2>&1; then
    printf '%s\n' "${matches[@]}" | fzf --height=40% --reverse --prompt='to> '
    return
  fi

  if [[ "$force_interactive" != 1 ]]; then
    print -r -- "$matches[1]"
    return
  fi

  _to_choose_numbered "${matches[@]}"
}

_to_resolve() {
  local force_interactive=0
  local -a roots queries matches
  local alias_target exact_target

  _to_load_roots
  roots=("${TO_ROOTS[@]}")

  while (( $# > 0 )); do
    case "$1" in
      -i)
        force_interactive=1
        shift
        ;;
      -r|--from)
        shift
        [[ -n "$1" ]] || return 2
        roots=("$(_to_expand_path "$1")")
        shift
        ;;
      --)
        shift
        break
        ;;
      -*)
        print -u2 -- "to: unknown option: $1"
        return 2
        ;;
      *)
        break
        ;;
    esac
  done

  queries=("$@")
  (( ${#queries} > 0 )) || return 2

  if (( ${#queries} == 1 )); then
    alias_target="$(_to_builtin_alias "$queries[1]")"
    if [[ -n "$alias_target" && "$force_interactive" != 1 ]]; then
      print -r -- "$alias_target"
      return
    fi

    if [[ "$force_interactive" != 1 && "$queries[1]" != */* ]]; then
      exact_target="$(_to_frecency_query_sqlite roots "$queries[1]" | head -n 1)"
      if [[ -n "$exact_target" ]]; then
        _to_record_search_outcome "Frecency Hit"
        print -r -- "$exact_target"
        return
      fi
      exact_target="$(_to_first_exact_match roots "$queries[1]")"
      if [[ -n "$exact_target" ]]; then
        print -r -- "$exact_target"
        return
      fi
      exact_target="$(_to_collect_file_parent_matches roots "$queries[1]" | head -n 1)"
      if [[ -n "$exact_target" ]]; then
        print -r -- "$exact_target"
        return
      fi
      (( TO_SEARCH_PATH_FRAGMENTS == 1 )) || return 1
    fi
  fi

  matches=("${(@f)$(_to_collect_matches roots "${queries[@]}")}")
  _to_choose_match "$force_interactive" "${matches[@]}"
}

_to_use_root() {
  local dir="$(_to_expand_path "${1:-.}")"

  [[ -d "$dir" ]] || {
    print -u2 -- "to: not a directory: ${1:-.}"
    return 1
  }
  _to_root_is_safe_to_add "$dir" || {
    print -u2 -- "to: refusing broad system root: $dir"
    print -u2 -- "to: add a narrower directory that contains the places you actually jump to"
    return 1
  }

  _to_load_roots
  TO_ROOTS=("${(@f)$(_to_unique_existing_dirs "$dir" "${TO_ROOTS[@]}")}")
  _to_save_roots
  print -r -- "to: using $dir"
}

_to_unuse_root() {
  local dir="$(_to_expand_path "${1:-.}")"
  local -a kept
  local root

  _to_load_roots
  for root in "${TO_ROOTS[@]}"; do
    [[ "${root:A}" != "${dir:A}" ]] && kept+=("$root")
  done

  TO_ROOTS=("${kept[@]}")
  _to_save_roots
  print -r -- "to: removed $dir"
}

_to_print_roots() {
  _to_load_roots
  printf '%s\n' "${TO_ROOTS[@]}"
}

_to_watch_backend() {
  [[ -n "$TO_HELPER" && -x "$TO_HELPER" ]] || return 1
  print -r -- notify
}

_to_watch_reindex_after_event() {
  (( TO_WATCH_DEBOUNCE > 0 )) && sleep "$TO_WATCH_DEBOUNCE"
  _to_reindex
}

_to_watch_with_notify() {
  local -a roots
  local -a args
  local root

  roots=("$@")
  print -u2 -- "to: watching roots with reach-helper notify; press Ctrl-C to stop"
  args=(watch-once)
  for root in "${roots[@]}"; do
    args+=(--root "$root")
  done
  [[ -n "${TO_WATCH_TIMEOUT_MS:-}" ]] && args+=(--timeout-ms "$TO_WATCH_TIMEOUT_MS")
  while "$TO_HELPER" "${args[@]}" >/dev/null 2>&1; do
    _to_watch_reindex_after_event || return 1
    [[ "${TO_WATCH_ONCE:-0}" == 1 ]] && return 0
  done
}

_to_watch() {
  local -a roots
  local backend

  _to_load_roots
  roots=("${TO_ROOTS[@]}")
  (( ${#roots} > 0 )) || {
    print -u2 -- "to: no roots to watch"
    return 1
  }

  backend="$(_to_watch_backend)" || {
    print -u2 -- "to: watcher requires reach-helper"
    return 1
  }

  case "$backend" in
    notify)
      _to_watch_with_notify "${roots[@]}"
      ;;
  esac
}

_to_pid_is_running() {
  local pid="$1"

  [[ "$pid" == <-> ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

_to_autowatch_start() {
  local existing_pid

  setopt local_options no_bg_nice

  (( TO_AUTOWATCH == 1 )) || return 0
  [[ -n "${_TO_AUTOWATCH_PID:-}" ]] && kill -0 "$_TO_AUTOWATCH_PID" 2>/dev/null && return 0
  _to_watch_backend >/dev/null 2>&1 || return 0
  mkdir -p "$TO_CONFIG_HOME" || return 0
  if [[ -r "$_TO_AUTOWATCH_PID_FILE" ]]; then
    existing_pid="$(<"$_TO_AUTOWATCH_PID_FILE")"
    _to_pid_is_running "$existing_pid" && return 0
  fi

  ( _to_watch >/dev/null 2>&1; rm -f "$_TO_AUTOWATCH_PID_FILE" ) &
  _TO_AUTOWATCH_PID=$!
  print -r -- "$_TO_AUTOWATCH_PID" > "$_TO_AUTOWATCH_PID_FILE" 2>/dev/null || true
}

_to_on_off() {
  [[ "${1:-0}" == 1 ]] && print -r -- "on" || print -r -- "off"
}

_to_command_enabled() {
  command -v "${1:-}" >/dev/null 2>&1 && print -r -- "enabled" || print -r -- "disabled"
}

_to_sqlite_count() {
  local table="${1:-}"

  [[ -n "$table" ]] || {
    print -r -- 0
    return
  }
  command -v sqlite3 >/dev/null 2>&1 || {
    print -r -- 0
    return
  }
  [[ -r "$TO_INDEX_FILE" ]] || {
    print -r -- 0
    return
  }
  _to_index_ensure_sqlite_schema >/dev/null 2>&1 || {
    print -r -- 0
    return
  }
  sqlite3 -noheader "$TO_INDEX_FILE" "select count(*) from $table;" 2>/dev/null || print -r -- 0
}

_to_time_ago() {
  local then="${1:-0}"
  local now delta

  [[ "$then" == <-> && "$then" -gt 0 ]] || {
    print -r -- "never"
    return
  }
  now="$(_to_now)" || return 1
  delta=$(( now - then ))
  (( delta < 60 )) && {
    print -r -- "${delta}s ago"
    return
  }
  (( delta < 3600 )) && {
    print -r -- "$(( delta / 60 ))m ago"
    return
  }
  (( delta < 86400 )) && {
    print -r -- "$(( delta / 3600 ))h ago"
    return
  }
  print -r -- "$(( delta / 86400 ))d ago"
}

_to_hit_rate() {
  local total="$(_to_stat_get search_total 0)"
  local hits="$(_to_stat_get search_hit 0)"

  (( total > 0 )) || {
    print -r -- "n/a"
    return
  }
  print -r -- "$(( hits * 100 / total ))%"
}

_to_sqlite_total_entries() {
  local dirs="$(_to_sqlite_count dirs)"
  local files="$(_to_sqlite_count files)"
  local history="$(_to_sqlite_count history)"

  print -r -- "$(( ${dirs:-0} + ${files:-0} + ${history:-0} ))"
}

_to_most_used_root() {
  local root best_root count best_count=0

  _to_load_roots
  for root in "${TO_ROOTS[@]}"; do
    count=0
    if command -v sqlite3 >/dev/null 2>&1 && [[ -r "$TO_INDEX_FILE" ]]; then
      count="$(sqlite3 -noheader "$TO_INDEX_FILE" "select coalesce(sum(visits), 0) from history where path = $(_to_sql_quote "${root:A}") or path like $(_to_sql_quote "${root:A}/%");" 2>/dev/null)"
    fi
    if (( ${count:-0} > best_count )); then
      best_count="$count"
      best_root="${root:A}"
    fi
  done

  [[ -n "$best_root" ]] && print -r -- "$best_root" || print -r -- "n/a"
}

_to_doctor() {
  local verbose=0
  local sqlite_status watcher_status roots_count last_reindex

  [[ "${1:-}" == "--verbose" || "${1:-}" == "-v" ]] && verbose=1
  _to_load_roots
  roots_count="${#TO_ROOTS}"
  [[ -n "$TO_HELPER" && -x "$TO_HELPER" ]] && sqlite_status="helper/bundled" || sqlite_status="legacy fallback"
  _to_watch_backend >/dev/null 2>&1 && watcher_status="available ($(_to_watch_backend))" || watcher_status="unavailable"
  last_reindex="$(_to_stat_get last_reindex 0)"

  print -r -- "to config: $TO_CONFIG_FILE"
  print -r -- "to roots:  $TO_ROOTS_FILE"
  print -r -- "to index:  $TO_INDEX_FILE"
  print -r -- ""
  print -r -- "Search"
  print -r -- "  sqlite: $sqlite_status"
  print -r -- "  frecency: $(_to_on_off "$TO_FRECENCY")"
  print -r -- "  frecency threshold: $TO_FRECENCY_THRESHOLD"
  print -r -- ""
  print -r -- "Discovery"
  print -r -- "  mode: $(_to_discovery_mode_label)"
  print -r -- "  roots: $roots_count"
  print -r -- "  watcher: $watcher_status"
  print -r -- "  autowatch: $(_to_on_off "$TO_AUTOWATCH")"
  print -r -- "  auto add roots: $(_to_on_off "$TO_AUTO_ADD_ROOTS")"
  print -r -- ""
  print -r -- "Performance"
  print -r -- "  max depth: $TO_MAX_DEPTH"
  print -r -- "  path fragment search: $(_to_on_off "$TO_SEARCH_PATH_FRAGMENTS")"
  print -r -- "  follow symlinks: $(_to_on_off "$TO_FOLLOW_SYMLINKS")"
  print -r -- "  watch debounce: ${TO_WATCH_DEBOUNCE}s"
  print -r -- ""
  print -r -- "Statistics"
  print -r -- "  sqlite entries: $(_to_sqlite_total_entries)"
  print -r -- "  sqlite dirs: $(_to_sqlite_count dirs)"
  print -r -- "  directory history: $(_to_sqlite_count history)"
  print -r -- "  file cache: $(_to_sqlite_count files)"
  print -r -- "  last reindex: $(_to_time_ago "$last_reindex")"
  print -r -- "  most used root: $(_to_most_used_root)"
  print -r -- "  cache hit rate: $(_to_hit_rate)"
  print -r -- "  last search: $(_to_stat_get last_search unknown)"

  (( verbose == 1 )) || return 0
  print -r -- ""
  print -r -- "Verbose"
  command -v fzf >/dev/null 2>&1 && print -r -- "  fzf path: $(command -v fzf)" || print -r -- "  fzf path: no"
  command -v sqlite3 >/dev/null 2>&1 && print -r -- "  sqlite3 path: $(command -v sqlite3)" || print -r -- "  sqlite3 path: no"
  [[ -n "$TO_HELPER" && -x "$TO_HELPER" ]] && print -r -- "  helper: $TO_HELPER" || print -r -- "  helper: no"
  [[ -n "$TO_AI_COMMAND" ]] && print -r -- "  ai command: $TO_AI_COMMAND" || print -r -- "  ai command: no"
  [[ -n "$TO_AI_RANK_COMMAND" ]] && print -r -- "  ai rank command: $TO_AI_RANK_COMMAND" || print -r -- "  ai rank command: no"
  [[ -n "$TO_OPEN_COMMAND" ]] && print -r -- "  open command: $TO_OPEN_COMMAND" || print -r -- "  open command: auto"
  [[ -n "$TO_VSCODE_COMMAND" ]] && print -r -- "  vscode command: $TO_VSCODE_COMMAND" || print -r -- "  vscode command: auto"
  [[ -n "$TO_FIG_COMMAND" ]] && print -r -- "  fig command: $TO_FIG_COMMAND" || print -r -- "  fig command: auto"
}

_to_add_alias() {
  local name="$1"
  local dir="$2"

  [[ -n "$name" && -n "$dir" ]] || {
    print -u2 -- "to: usage: to add <name> <dir>"
    return 2
  }
  dir="$(_to_expand_path "$dir")"
  [[ -d "$dir" ]] || {
    print -u2 -- "to: not a directory: $dir"
    return 1
  }
  _to_write_map_value "$TO_ALIASES_FILE" "$name" "$dir" aliases
  print -r -- "to: alias $name -> ${dir:A}"
}

_to_remove_alias() {
  [[ -n "$1" ]] || {
    print -u2 -- "to: usage: to remove <name>"
    return 2
  }
  _to_remove_map_value "$TO_ALIASES_FILE" "$1" aliases
  print -r -- "to: removed alias $1"
}

_to_add_workspace() {
  local name="$1"
  local dir="$2"

  [[ -n "$name" && -n "$dir" ]] || {
    print -u2 -- "to: usage: to workspace <name> <dir>"
    return 2
  }
  dir="$(_to_expand_path "$dir")"
  [[ -d "$dir" ]] || {
    print -u2 -- "to: not a directory: $dir"
    return 1
  }
  _to_write_map_value "$TO_WORKSPACES_FILE" "$name" "$dir" workspaces
  print -r -- "to: workspace $name -> ${dir:A}"
}

_to_remove_workspace() {
  [[ -n "$1" ]] || {
    print -u2 -- "to: usage: to unwork <name>"
    return 2
  }
  _to_remove_map_value "$TO_WORKSPACES_FILE" "$1" workspaces
  print -r -- "to: removed workspace $1"
}

_to_repo_score_sql() {
  local now="$1"

  print -r -- "case when h.visits is null then 0 when $now - h.last_used <= 3600 then h.visits * 4.0 when $now - h.last_used <= 86400 then h.visits * 2.0 when $now - h.last_used <= 604800 then h.visits * 0.5 else h.visits * 0.25 end"
}

_to_repo_query_sqlite() {
  local -a queries clauses compact_parts
  local -a matches
  local query first compact phrase now score_sql where sql

  command -v sqlite3 >/dev/null 2>&1 || return 1
  [[ -r "$TO_INDEX_FILE" ]] || return 1
  _to_index_ensure_sqlite_schema || return 1
  queries=("${(@L)@}")
  (( ${#queries} > 0 )) || return 1
  first="${queries[1]}"

  for query in "${queries[@]}"; do
    clauses+=("(d.repo_name like $(_to_sql_quote "%$query%") or lower(d.path) like $(_to_sql_quote "%$query%"))")
    compact_parts+=("$query")
  done
  compact="${(j:-:)compact_parts}"
  phrase="${(j: :)queries}"
  where="${(j: and :)clauses}"
  now="$(_to_now)" || return 1
  score_sql="$(_to_repo_score_sql "$now")"

  sql="select d.path from dirs d left join history h on h.path = d.path where d.repo = 1 and $where order by ($score_sql) desc, case when d.repo_name = $(_to_sql_quote "$compact") then 0 when replace(d.repo_name, '-', ' ') = $(_to_sql_quote "$phrase") then 1 when d.repo_name like $(_to_sql_quote "$first%") then 2 else 3 end, d.depth asc, length(d.path), d.path limit 50;"
  matches=("${(@f)$(sqlite3 -noheader "$TO_INDEX_FILE" "$sql" 2>/dev/null)}")
  _to_index_filter_existing "${matches[@]}"
}

_to_repo_list_sqlite() {
  local -a matches
  local now score_sql sql

  command -v sqlite3 >/dev/null 2>&1 || return 1
  [[ -r "$TO_INDEX_FILE" ]] || return 1
  _to_index_ensure_sqlite_schema || return 1
  now="$(_to_now)"
  score_sql="$(_to_repo_score_sql "$now")"
  sql="select d.path from dirs d left join history h on h.path = d.path where d.repo = 1 order by ($score_sql) desc, coalesce(h.last_used, d.last_used) desc, d.repo_name, d.path limit 50;"
  matches=("${(@f)$(sqlite3 -noheader "$TO_INDEX_FILE" "$sql" 2>/dev/null)}")
  _to_index_filter_existing "${matches[@]}"
}

_to_repo_matches_query() {
  local repo="$1"
  shift
  local haystack="${(L)repo}"
  local name="${(L)repo:t}"
  local query

  (( $# > 0 )) || return 0
  for query in "$@"; do
    query="${(L)query}"
    [[ "$name" == *"$query"* || "$haystack" == *"$query"* ]] || return 1
  done
}

_to_live_repo_matches() {
  local -a roots candidates seen ranked
  local root dir repo key

  _to_load_roots
  roots=("${TO_ROOTS[@]}")
  for root in "${roots[@]}"; do
    [[ -d "$root" ]] || continue
    if command -v fd >/dev/null 2>&1; then
      local -a follow_args
      (( TO_FOLLOW_SYMLINKS == 1 )) && follow_args=(--follow)
      candidates=("${(@f)$(fd --hidden "${follow_args[@]}" --max-depth "$TO_MAX_DEPTH" --type d --glob .git "$root" 2>/dev/null)}")
    else
      candidates=("${(@f)$(find "$root" -maxdepth "$TO_MAX_DEPTH" -type d -name .git -print 2>/dev/null)}")
    fi
    for dir in "${candidates[@]}"; do
      repo="${dir:h}"
      [[ -d "$repo" ]] || continue
      _to_repo_matches_query "$repo" "$@" || continue
      key="${repo:A}"
      (( ${seen[(Ie)$key]} > 0 )) && continue
      seen+=("$key")
      _to_index_upsert_dir "$key"
      print -r -- "$key"
    done
  done
}

_to_git_repo_matches() {
  local -a matches

  if (( $# == 0 )); then
    _to_repo_list_sqlite
    return
  fi

  matches=("${(@f)$(_to_repo_query_sqlite "$@")}")
  matches=("${(@)matches:#}")
  if (( ${#matches} > 0 )); then
    _to_record_search_outcome "Repo Index"
    printf '%s\n' "${matches[@]}"
    return
  fi

  matches=("${(@f)$(_to_live_repo_matches "$@")}")
  matches=("${(@)matches:#}")
  if (( ${#matches} > 0 )); then
    _to_record_search_outcome "Repo Filesystem Fallback"
    printf '%s\n' "${(@f)$(_to_rank_dirs_by_usage "${matches[@]}")}"
  fi
}

_to_nearest_git_root() {
  local dir="${PWD:A}"

  while [[ -n "$dir" && "$dir" != "/" ]]; do
    if [[ -d "$dir/.git" || -f "$dir/.git" ]]; then
      print -r -- "$dir"
      return 0
    fi
    dir="${dir:h}"
  done

  return 1
}

_to_git_remote_url() {
  local repo="$1"
  local remote

  [[ -d "$repo" ]] || return 1
  command git -C "$repo" remote get-url origin 2>/dev/null || return 1
}

_to_github_url_from_remote() {
  local remote="$1"
  local path

  case "$remote" in
    git@github.com:*)
      path="${remote#git@github.com:}"
      ;;
    ssh://git@github.com/*)
      path="${remote#ssh://git@github.com/}"
      ;;
    ssh://git@ssh.github.com:443/*)
      path="${remote#ssh://git@ssh.github.com:443/}"
      ;;
    https://github.com/*)
      path="${remote#https://github.com/}"
      ;;
    http://github.com/*)
      path="${remote#http://github.com/}"
      ;;
    *)
      return 1
      ;;
  esac
  path="${path%.git}"
  [[ "$path" == */* ]] || return 1
  print -r -- "https://github.com/$path"
}

_to_system_open_command() {
  if [[ -n "$TO_OPEN_COMMAND" ]]; then
    print -r -- "$TO_OPEN_COMMAND"
  elif command -v open >/dev/null 2>&1; then
    print -r -- open
  elif command -v xdg-open >/dev/null 2>&1; then
    print -r -- xdg-open
  elif command -v wslview >/dev/null 2>&1; then
    print -r -- wslview
  elif command -v explorer.exe >/dev/null 2>&1; then
    print -r -- explorer.exe
  else
    return 1
  fi
}

_to_open_url() {
  local url="$1"
  local opener

  opener="$(_to_system_open_command)" || {
    print -u2 -- "to: no browser opener found; open manually: $url"
    return 1
  }
  eval "$opener ${(q)url}" >/dev/null 2>&1
}

_to_repo_for_gh() {
  if (( $# > 0 )); then
    _to_git_repo_matches "$@" | head -n 1
    return
  fi

  _to_nearest_git_root
}

_to_open_github() {
  local target remote url query

  if (( $# > 0 )) && [[ "$1" == */* && "$1" != */*/* ]]; then
    url="https://github.com/${1%.git}"
    _to_open_url "$url"
    return
  fi

  target="$(_to_repo_for_gh "$@")" || true
  if [[ -n "$target" ]]; then
    remote="$(_to_git_remote_url "$target")" || {
      print -u2 -- "to: no origin remote for Git repository: $target"
      return 1
    }
    url="$(_to_github_url_from_remote "$remote")" || {
      print -u2 -- "to: origin is not a GitHub remote: $remote"
      return 1
    }
    _to_open_url "$url"
    return
  fi

  query="${(j:-:)@}"
  [[ -n "$query" ]] || {
    print -u2 -- "to: usage: to gh <repo> or run inside a GitHub repository"
    return 2
  }
  print -u2 -- "to: no matching GitHub repository: ${(j: :)@}"
  return 1
}

_to_issue_pr_clone_matches() {
  local kind="$1"
  local id="$2"
  local -a roots matches ranked seen dirs
  local root dir name key

  [[ "$id" == <-> ]] || return 1
  _to_load_roots
  roots=("${TO_ROOTS[@]}")
  for root in "${roots[@]}"; do
    [[ -d "$root" ]] || continue
    if command -v fd >/dev/null 2>&1; then
      dirs=("${(@f)$(_to_search_dirs_with_fd "$root")}")
    else
      dirs=("${(@f)$(_to_search_dirs_with_find "$root")}")
    fi
    for dir in "${dirs[@]}"; do
      [[ -d "$dir" ]] || continue
      name="${(L)dir:t}"
      case "$kind" in
        issue)
          [[ "$name" == *issue*"$id"* || "$name" == "#$id" || "$name" == "$id" ]] || continue
          ;;
        pr)
          [[ "$name" == *pr*"$id"* || "$name" == *pull*"$id"* || "$name" == "#$id" || "$name" == "$id" ]] || continue
          ;;
        *)
          continue
          ;;
      esac
      key="${dir:A}"
      (( ${seen[(Ie)$key]} > 0 )) && continue
      seen+=("$key")
      matches+=("$key")
      _to_index_upsert_dir "$key"
    done
  done

  (( ${#matches} > 0 )) || return 1
  _to_record_search_outcome "Shortcut Filesystem Fallback"
  ranked=("${(@f)$(_to_rank_dirs_by_usage "${matches[@]}")}")
  printf '%s\n' "${ranked[@]}"
}

_to_jump_issue_pr_clone() {
  local kind="$1"
  local id="$2"
  local target

  [[ -n "$id" ]] || {
    print -u2 -- "to: usage: to $kind <id>"
    return 2
  }
  target="$(_to_choose_match 0 "${(@f)$(_to_issue_pr_clone_matches "$kind" "$id")}")"
  if [[ $? -ne 0 || -z "$target" ]]; then
    _to_record_search_outcome "Miss"
    print -u2 -- "to: no local $kind clone matching $id"
    print -u2 -- "to: searched $(_to_discovery_mode_label) roots: $(_to_roots_summary)"
    return 1
  fi
  cd "$target" && _to_after_cd "$PWD"
}

_to_resolve_for_external_tool() {
  local -a matches roots

  if (( $# == 0 )); then
    print -r -- "${PWD:A}"
    return
  fi

  _to_load_roots
  roots=("${TO_ROOTS[@]}")
  matches=("${(@f)$(_to_collect_matches roots "$@")}")
  matches=("${(@)matches:#}")
  (( ${#matches} > 0 )) || return 1
  _to_choose_match 0 "${matches[@]}"
}

_to_run_external_dir_command() {
  local label="$1"
  local command_value="$2"
  shift 2
  local dir

  [[ -n "$command_value" ]] || {
    print -u2 -- "to: $label command is not configured or installed"
    return 1
  }
  dir="$(_to_resolve_for_external_tool "$@")" || {
    _to_record_search_outcome "Miss"
    _to_print_no_match_advice "$label target" "$@"
    return 1
  }
  eval "$command_value ${(q)dir}" >/dev/null 2>&1
}

_to_vscode_command() {
  [[ -n "$TO_VSCODE_COMMAND" ]] && {
    print -r -- "$TO_VSCODE_COMMAND"
    return
  }
  command -v code >/dev/null 2>&1 && print -r -- code
}

_to_fig_command() {
  [[ -n "$TO_FIG_COMMAND" ]] && {
    print -r -- "$TO_FIG_COMMAND"
    return
  }
  command -v fig >/dev/null 2>&1 && print -r -- fig
}

_to_ai_matches() {
  local query="${(j: :)@}"
  local -a roots
  local old_search="$TO_SEARCH_PATH_FRAGMENTS"

  if [[ -n "$TO_AI_COMMAND" ]]; then
    eval "$TO_AI_COMMAND ${(q)query}"
    return
  fi

  _to_load_roots
  roots=("${TO_ROOTS[@]}")
  TO_SEARCH_PATH_FRAGMENTS=1
  _to_collect_matches roots "$query"
  TO_SEARCH_PATH_FRAGMENTS="$old_search"
}

_to_help() {
  cat <<'EOF'
Usage:
  to <query...>             Jump to a matching directory
  to -i <query...>          Force interactive selection
  to -r <root> <query...>   Search from a temporary root
  to --from <root> <query>  Search from a temporary root
  to use [dir]              Add a search root
  to unuse [dir]            Remove a search root
  to roots                  List search roots
  to add <name> <dir>       Add a user alias
  to remove <name>          Remove a user alias
  to aliases                List user aliases
  to repo [query...]        List repos, or jump to a matching Git repository
  to git                    Jump to the nearest parent Git repository
  to file <name>            Jump to a directory containing a matching file
  to dir <query...>         Jump to a matching directory
  to ws <query...>          Jump to a matching workspace
  to cargo <query...>       Jump to a Rust project by Cargo.toml content
  to npm <query...>         Jump to a Node project by package.json content
  to py <query...>          Jump to a Python project by package metadata
  to docker <query...>      Jump to a Docker project by Docker metadata
  to code <query...>        Jump to a directory containing matching code text
  to issue <id>             Jump to a local issue clone directory
  to pr <id>                Jump to a local pull-request clone directory
  to gh [repo]              Open a GitHub repository in the browser
  to vscode [query...]      Open a matching directory in VS Code
  to fig [query...]         Run fig for a matching directory
  to recent                 Choose from recent jumps
  to workspace <name> <dir> Add a workspace alias
  to work <name>            Jump to a workspace
  to unwork <name>          Remove a workspace
  to workspaces             List workspaces
  to ai <query...>          Use TO_AI_COMMAND, or broad fallback search
  to --doctor               Show grouped diagnostics and runtime statistics
  to --doctor --verbose     Include low-level tool paths and optional hooks
  to --reindex              Rebuild the directory index
  to --watch                Watch roots and reindex after filesystem changes
  to --version              Show version

Config:
  TO_SEARCH_PATH_FRAGMENTS=0  Prefer exact directory names by default
  TO_SEARCH_PATH_FRAGMENTS=1  Also match any path containing the query
  TO_FOLLOW_SYMLINKS=0         Do not follow symlinks while searching
  TO_FOLLOW_SYMLINKS=1         Follow symlinks while searching
  TO_ROOT_MODE=home            Search HOME plus configured roots
  TO_ROOT_MODE=explicit        Search only configured roots
  TO_WATCH_DEBOUNCE=2          Seconds to wait before watcher reindex
  TO_AUTOWATCH=1               Start a background watcher when loaded
  TO_AUTO_ADD_ROOTS=1          Add temporary-search parent roots automatically
  TO_FRECENCY=1                Prefer frequently and recently used dirs
  TO_FRECENCY_THRESHOLD=1      Minimum frecency score before fallback search
  TO_AI_COMMAND               External command that prints candidate dirs
  TO_AI_RANK_COMMAND          External command that ranks candidate dirs from stdin
  TO_OPEN_COMMAND             External URL opener for to gh
  TO_VSCODE_COMMAND           External command for to vscode
  TO_FIG_COMMAND              External command for to fig
  TO_HELPER                   Optional reach-helper binary path
EOF
}

_reach_dispatch() {
  local target alias_target workspace_target resolve_status

  case "$1" in
    use)
      shift
      _to_use_root "${1:-.}"
      ;;
    unuse)
      shift
      _to_unuse_root "${1:-.}"
      ;;
    roots)
      _to_print_roots
      ;;
    add|alias)
      shift
      _to_add_alias "$1" "$2"
      ;;
    remove|unalias)
      shift
      _to_remove_alias "$1"
      ;;
    aliases)
      _to_print_map "$TO_ALIASES_FILE" aliases
      ;;
    repo)
      shift
      if (( $# == 0 )); then
        _to_git_repo_matches
        return
      fi
      target="$(_to_choose_match 0 "${(@f)$(_to_git_repo_matches "$@")}")"
      if [[ $? -ne 0 || -z "$target" ]]; then
        _to_record_search_outcome "Miss"
        _to_print_no_match_advice "Git repository" "$@"
        return 1
      fi
      cd "$target" && _to_after_cd "$PWD"
      ;;
    git)
      target="$(_to_nearest_git_root)" || {
        print -u2 -- "to: no parent Git repository from $PWD"
        return 1
      }
      cd "$target" && _to_after_cd "$PWD"
      ;;
    file|dir|ws|cargo|npm|py|docker|code)
      local object_kind="$1"
      shift
      _to_jump_to_object "$object_kind" "$@"
      ;;
    issue|pr)
      local shortcut_kind="$1"
      shift
      _to_jump_issue_pr_clone "$shortcut_kind" "$1"
      ;;
    gh)
      shift
      _to_open_github "$@"
      ;;
    vscode)
      shift
      _to_run_external_dir_command "vscode" "$(_to_vscode_command)" "$@"
      ;;
    fig)
      shift
      _to_run_external_dir_command "fig" "$(_to_fig_command)" "$@"
      ;;
    recent)
      target="$(_to_choose_match 0 "${(@f)$(_to_recent_dirs)}")"
      if [[ $? -ne 0 || -z "$target" ]]; then
        print -u2 -- "to: no recent directories"
        return 1
      fi
      cd "$target" && _to_after_cd "$PWD"
      ;;
    workspace)
      shift
      _to_add_workspace "$1" "$2"
      ;;
    work)
      shift
      workspace_target="$(_to_workspace "$1")" || {
        print -u2 -- "to: unknown workspace: $1"
        return 1
      }
      cd "$workspace_target" && _to_after_cd "$PWD"
      ;;
    unwork)
      shift
      _to_remove_workspace "$1"
      ;;
    workspaces)
      _to_print_map "$TO_WORKSPACES_FILE" workspaces
      ;;
    ai)
      shift
      [[ $# -gt 0 ]] || {
        print -u2 -- "to: usage: to ai <query...>"
        return 2
      }
      target="$(_to_choose_match 0 "${(@f)$(_to_ai_matches "$@")}")"
      if [[ $? -ne 0 || -z "$target" ]]; then
        _to_record_search_outcome "Miss"
        print -u2 -- "to: no AI/fallback matches: ${(j: :)@}"
        return 1
      fi
      cd "$target" && _to_after_cd "$PWD"
      ;;
    --doctor)
      shift
      _to_doctor "${1:-}"
      ;;
    --reindex)
      _to_reindex
      ;;
    --watch)
      _to_watch
      ;;
    --version|-V)
      print -r -- "reach $_TO_VERSION"
      ;;
    -h|--help|"")
      _to_help
      ;;
    *)
      if (( $# == 1 )); then
        alias_target="$(_to_user_alias "$1")"
        if [[ -n "$alias_target" ]]; then
          cd "$alias_target" && _to_after_cd "$PWD"
          return
        fi
        workspace_target="$(_to_workspace "$1")"
        if [[ -n "$workspace_target" ]]; then
          cd "$workspace_target" && _to_after_cd "$PWD"
          return
        fi
      fi
      target="$(_to_resolve "$@")"
      resolve_status=$?
      if (( resolve_status == 2 )); then
        return 2
      fi
      if [[ $resolve_status -ne 0 || -z "$target" ]]; then
        _to_record_search_outcome "Miss"
        _to_print_no_match_advice "directory" "$@"
        return 1
      fi
      cd "$target" && _to_maybe_add_external_root "$PWD" && _to_after_cd "$PWD"
      ;;
  esac
}

gt() {
  _reach_dispatch "$@"
}

to() {
  _reach_dispatch "$@"
}

if (( $+functions[compdef] )); then
  compdef _to gt 2>/dev/null
  compdef _to to 2>/dev/null
fi

_to_autowatch_start
