# to: exploratory directory jumper for zsh.

: ${TO_WATCH_DEBOUNCE:=2}

typeset -ga TO_ROOTS
typeset -ga TO_EXCLUDES
typeset -gi TO_MAX_DEPTH
typeset -gi TO_INTERACTIVE_THRESHOLD
typeset -gi TO_SEARCH_PATH_FRAGMENTS
typeset -gi TO_FOLLOW_SYMLINKS
typeset -gi TO_WATCH_DEBOUNCE
typeset -g _TO_SQLITE_SCHEMA_READY_FILE

: ${TO_CONFIG_HOME:="${XDG_CONFIG_HOME:-$HOME/.config}/to"}
: ${TO_CONFIG_FILE:="$TO_CONFIG_HOME/config.zsh"}
: ${TO_ROOTS_FILE:="$TO_CONFIG_HOME/roots"}
: ${TO_INDEX_FILE:="$TO_CONFIG_HOME/index.sqlite3"}
: ${TO_INDEX_TSV_FILE:="$TO_CONFIG_HOME/index.tsv"}
: ${TO_ALIASES_FILE:="$TO_CONFIG_HOME/aliases"}
: ${TO_WORKSPACES_FILE:="$TO_CONFIG_HOME/workspaces"}
: ${TO_RECENT_FILE:="$TO_CONFIG_HOME/recent"}
: ${TO_AI_COMMAND:=""}
: ${TO_AI_RANK_COMMAND:=""}
: ${TO_HELPER:=""}
(( TO_MAX_DEPTH > 0 )) || TO_MAX_DEPTH=8
(( TO_INTERACTIVE_THRESHOLD > 0 )) || TO_INTERACTIVE_THRESHOLD=3
(( TO_SEARCH_PATH_FRAGMENTS == 0 || TO_SEARCH_PATH_FRAGMENTS == 1 )) || TO_SEARCH_PATH_FRAGMENTS=0
(( TO_FOLLOW_SYMLINKS == 0 || TO_FOLLOW_SYMLINKS == 1 )) || TO_FOLLOW_SYMLINKS=0
(( TO_WATCH_DEBOUNCE >= 0 )) || TO_WATCH_DEBOUNCE=2

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

if [[ -z "$TO_HELPER" ]] && command -v to-helper >/dev/null 2>&1; then
  TO_HELPER="$(command -v to-helper)"
fi

_to_expand_path() {
  print -r -- "${~1:A}"
}

_to_unique_existing_dirs() {
  local -a seen out
  local dir key

  for dir in "$@"; do
    [[ -n "$dir" ]] || continue
    dir="$(_to_expand_path "$dir")"
    [[ -d "$dir" ]] || continue
    key="${dir:A}"
    if (( ${seen[(Ie)$key]} == 0 )); then
      seen+=("$key")
      out+=("$key")
    fi
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

  default_roots=("$HOME/Projects" "$HOME/Code" "$HOME/Documents" "$HOME/Downloads" "$HOME/Desktop")
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
    project|projects) target="$HOME/Projects" ;;
    code) target="$HOME/Code" ;;
  esac

  [[ -n "$target" && -d "$target" ]] && print -r -- "$target"
}

_to_sql_quote() {
  local value="$1"
  value="${value//\'/\'\'}"
  print -r -- "'$value'"
}

_to_now() {
  date +%s 2>/dev/null || print -r -- 0
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
  local name parent depth is_git

  [[ -d "$dir" ]] || return 1
  name="${dir:t}"
  parent="${dir:h}"
  depth="$(_to_dir_depth "$dir")"
  is_git=0
  [[ -d "$dir/.git" ]] && is_git=1
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$dir" "$name" "${(L)name}" "$parent" "$depth" "$is_git" "$now" 0 0
}

_to_root_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || print -r -- 0
}

_to_index_config_key() {
  print -r -- "depth=$TO_MAX_DEPTH;follow=$TO_FOLLOW_SYMLINKS;excludes=${(j:,:)TO_EXCLUDES}"
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
  local has_id has_parent has_depth has_last_seen has_last_used has_hit_count has_token_dir_id has_token_path has_config_key

  command -v sqlite3 >/dev/null 2>&1 || return 1
  if [[ "$_TO_SQLITE_SCHEMA_READY_FILE" == "$TO_INDEX_FILE" && -r "$TO_INDEX_FILE" ]]; then
    return 0
  fi

  mkdir -p "$TO_CONFIG_HOME" || return 1
  sqlite3 "$TO_INDEX_FILE" >/dev/null <<SQL || return 1
create table if not exists dirs(
  id integer primary key,
  path text unique not null,
  name text not null,
  lower_name text not null,
  parent text not null default '',
  depth integer not null default 0,
  is_git integer not null default 0,
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
SQL
  has_id="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from pragma_table_info('dirs') where name = 'id';" 2>/dev/null)"
  has_parent="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from pragma_table_info('dirs') where name = 'parent';" 2>/dev/null)"
  has_depth="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from pragma_table_info('dirs') where name = 'depth';" 2>/dev/null)"
  has_last_seen="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from pragma_table_info('dirs') where name = 'last_seen';" 2>/dev/null)"
  has_last_used="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from pragma_table_info('dirs') where name = 'last_used';" 2>/dev/null)"
  has_hit_count="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from pragma_table_info('dirs') where name = 'hit_count';" 2>/dev/null)"
  has_token_dir_id="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from pragma_table_info('tokens') where name = 'dir_id';" 2>/dev/null)"
  has_token_path="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from pragma_table_info('tokens') where name = 'path';" 2>/dev/null)"
  has_config_key="$(sqlite3 "$TO_INDEX_FILE" "select count(*) from pragma_table_info('roots') where name = 'config_key';" 2>/dev/null)"

  if [[ "$has_id" != 1 ]]; then
    [[ "$has_parent" == 1 ]] || sqlite3 "$TO_INDEX_FILE" "alter table dirs add column parent text not null default '';" >/dev/null 2>/dev/null
    [[ "$has_depth" == 1 ]] || sqlite3 "$TO_INDEX_FILE" "alter table dirs add column depth integer not null default 0;" >/dev/null 2>/dev/null
    [[ "$has_last_seen" == 1 ]] || sqlite3 "$TO_INDEX_FILE" "alter table dirs add column last_seen integer not null default 0;" >/dev/null 2>/dev/null
    [[ "$has_last_used" == 1 ]] || sqlite3 "$TO_INDEX_FILE" "alter table dirs add column last_used integer not null default 0;" >/dev/null 2>/dev/null
    [[ "$has_hit_count" == 1 ]] || sqlite3 "$TO_INDEX_FILE" "alter table dirs add column hit_count integer not null default 0;" >/dev/null 2>/dev/null
    sqlite3 "$TO_INDEX_FILE" >/dev/null <<SQL || return 1
alter table dirs rename to dirs_legacy;
create table dirs(
  id integer primary key,
  path text unique not null,
  name text not null,
  lower_name text not null,
  parent text not null default '',
  depth integer not null default 0,
  is_git integer not null default 0,
  last_seen integer not null default 0,
  last_used integer not null default 0,
  hit_count integer not null default 0
);
insert into dirs(path, name, lower_name, parent, depth, is_git, last_seen, last_used, hit_count)
select
  path,
  name,
  lower_name,
  coalesce(parent, rtrim(substr(path, 1, length(path) - length(name)), '/')),
  coalesce(depth, length(path) - length(replace(path, '/', ''))),
  coalesce(is_git, 0),
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
  [[ "$has_config_key" == 1 ]] || sqlite3 "$TO_INDEX_FILE" "alter table roots add column config_key text not null default '';" >/dev/null 2>/dev/null

  if [[ "$has_token_dir_id" != 1 ]]; then
    if [[ "$has_token_path" == 1 ]]; then
      sqlite3 "$TO_INDEX_FILE" >/dev/null <<SQL || return 1
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

  sqlite3 "$TO_INDEX_FILE" >/dev/null <<SQL || return 1
update dirs set parent = rtrim(substr(path, 1, length(path) - length(name)), '/') where parent = '';
update dirs set depth = length(path) - length(replace(path, '/', '')) where depth = 0;
create index if not exists idx_dirs_lower_name on dirs(lower_name);
create index if not exists idx_dirs_is_git on dirs(is_git);
create index if not exists idx_dirs_depth on dirs(depth);
create index if not exists idx_dirs_last_used on dirs(last_used);
create index if not exists idx_dirs_path on dirs(path);
create index if not exists idx_tokens_token on tokens(token);
create index if not exists idx_tokens_dir_id on tokens(dir_id);
create index if not exists idx_roots_last_indexed on roots(last_indexed);
create index if not exists idx_recent_last_used on recent(last_used);
SQL
  _TO_SQLITE_SCHEMA_READY_FILE="$TO_INDEX_FILE"
}

_to_read_map_value() {
  local file="$1"
  local key="${(L)2}"
  local table="$3"
  local line item value

  if [[ -n "$table" ]] && command -v sqlite3 >/dev/null 2>&1; then
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
  now="$(date +%s 2>/dev/null || print -r -- 0)"

  if command -v sqlite3 >/dev/null 2>&1; then
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

  printf '%s\t%s\n' "$now" "$dir" > "$tmp" || return 0

  if [[ -r "$TO_RECENT_FILE" ]]; then
    while IFS= read -r line; do
      item="${line#*	}"
      [[ "$item" == "$line" || "${item:A}" == "$dir" ]] && continue
      print -r -- "$line" >> "$tmp"
      (( ++count >= 49 )) && break
    done < "$TO_RECENT_FILE"
  fi

  mv "$tmp" "$TO_RECENT_FILE"
}

_to_recent_dirs() {
  local line dir
  local -a sqlite_recent

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

  if command -v fd >/dev/null 2>&1; then
    _to_search_exact_name_with_fd "$root" "$query" "$limit"
  else
    _to_search_exact_name_with_find "$root" "$query" "$limit"
  fi
}

_to_index_collect_root_tsv() {
  local root="${1:A}"
  local output_file="$2"
  local now="${3:-$(_to_now)}"
  local dir

  [[ -d "$root" ]] || return 1
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
  now="$(_to_now)"

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
create table dirs(
  id integer primary key,
  path text unique not null,
  name text not null,
  lower_name text not null,
  parent text not null,
  depth integer not null,
  is_git integer not null,
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
insert into dirs(path, name, lower_name, parent, depth, is_git, last_seen, last_used, hit_count)
select path, name, lower_name, parent, depth, is_git, last_seen, last_used, hit_count
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
create index idx_dirs_depth on dirs(depth);
create index idx_dirs_last_used on dirs(last_used);
create index idx_dirs_path on dirs(path);
create index idx_tokens_token on tokens(token);
create index idx_tokens_dir_id on tokens(dir_id);
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
delete from tokens
where dir_id in (
  select id from dirs where path = $(_to_sql_quote "$root") or path like $(_to_sql_quote "$root_like")
);
delete from dirs
where (path = $(_to_sql_quote "$root") or path like $(_to_sql_quote "$root_like"))
  and path not in (select path from __to_import_dirs);
insert or replace into dirs(path, name, lower_name, parent, depth, is_git, last_seen, last_used, hit_count)
select
  i.path,
  i.name,
  i.lower_name,
  i.parent,
  i.depth,
  i.is_git,
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
delete from dirs
where path in (
  select d.path
  from dirs d
  join roots r on d.path = r.path or d.path like r.path || '/%'
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
  now="$(_to_now)"
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
  print -r -- "to: indexed $changed root(s), skipped $skipped fresh root(s) into $TO_INDEX_FILE"
}

_to_index_rebuild_tsv() {
  _to_index_collect_tsv "$TO_INDEX_TSV_FILE"
}

_to_reindex() {
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
      sql="select d.path from dirs d join tokens t on t.dir_id = d.id where d.is_git = 1 and t.token in ($token_list) group by d.path having count(distinct t.token) = ${#queries} order by case when d.lower_name = $(_to_sql_quote "$first") then 0 else 1 end, d.last_used desc, d.hit_count desc, d.depth asc, length(d.path), d.path limit 50;"
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
  local query line row_path name lower_name parent depth is_git last_seen last_used hit_count
  local path_l ok part

  [[ -r "$TO_INDEX_TSV_FILE" ]] || return 1
  queries=("${(@L)@}")
  query="${(j: :)queries}"

  while IFS=$'\t' read -r row_path name lower_name parent depth is_git last_seen last_used hit_count; do
    [[ -d "$row_path" ]] || continue
    if [[ -z "$is_git" ]]; then
      is_git="$parent"
      parent="${row_path:h}"
      depth="$(_to_dir_depth "$row_path")"
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
        [[ "$is_git" == 1 && "$ok" == 1 ]] && print -r -- "$row_path"
        ;;
    esac
  done < "$TO_INDEX_TSV_FILE"
}

_to_index_delete_path() {
  local target_path="${1:A}"
  local tmp line item

  if command -v sqlite3 >/dev/null 2>&1 && [[ -r "$TO_INDEX_FILE" ]]; then
    _to_index_ensure_sqlite_schema || return 0
    sqlite3 "$TO_INDEX_FILE" "delete from tokens where dir_id in (select id from dirs where path = $(_to_sql_quote "$target_path")); delete from dirs where path = $(_to_sql_quote "$target_path");" >/dev/null 2>/dev/null
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
  local now="$(_to_now)"
  local name parent depth is_git
  local -a tokens token_values
  local token values_sql

  [[ -d "$dir" ]] || return 0
  _to_index_ensure_sqlite_schema || return 0
  name="${dir:t}"
  parent="${dir:h}"
  depth="$(_to_dir_depth "$dir")"
  is_git=0
  [[ -d "$dir/.git" ]] && is_git=1
  tokens=("${(@f)$(_to_dir_tokens "$dir")}")
  for token in "${tokens[@]}"; do
    [[ -n "$token" ]] || continue
    token_values+=("($(_to_sql_quote "$token"), (select id from dirs where path = $(_to_sql_quote "$dir")))")
  done
  values_sql="${(j:,:)token_values}"

  sqlite3 "$TO_INDEX_FILE" >/dev/null 2>/dev/null <<SQL
insert into dirs(path, name, lower_name, parent, depth, is_git, last_seen, last_used, hit_count)
values(
  $(_to_sql_quote "$dir"),
  $(_to_sql_quote "$name"),
  $(_to_sql_quote "${(L)name}"),
  $(_to_sql_quote "$parent"),
  $depth,
  $is_git,
  $now,
  coalesce((select last_used from dirs where path = $(_to_sql_quote "$dir")), 0),
  coalesce((select hit_count from dirs where path = $(_to_sql_quote "$dir")), 0)
)
on conflict(path) do update set
  name = excluded.name,
  lower_name = excluded.lower_name,
  parent = excluded.parent,
  depth = excluded.depth,
  is_git = excluded.is_git,
  last_seen = excluded.last_seen;
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

  [[ -d "$dir" ]] || return 0
  if command -v sqlite3 >/dev/null 2>&1; then
    _to_index_upsert_dir_sqlite "$dir"
  else
    _to_index_upsert_dir_tsv "$dir"
  fi
}

_to_index_touch_path() {
  local dir="${1:A}"
  local now="$(_to_now)"

  [[ -d "$dir" ]] || return 0
  if command -v sqlite3 >/dev/null 2>&1 && [[ -r "$TO_INDEX_FILE" ]]; then
    _to_index_ensure_sqlite_schema || return 0
    sqlite3 "$TO_INDEX_FILE" >/dev/null 2>/dev/null <<SQL
update dirs
set hit_count = hit_count + 1,
    last_used = $now,
    last_seen = case when last_seen > 0 then last_seen else $now end
where path = $(_to_sql_quote "$dir");
SQL
  fi
}

_to_after_cd() {
  local dir="${1:A}"

  [[ -d "$dir" ]] || return 0
  _to_record_recent "$dir"
  _to_index_upsert_dir "$dir"
  _to_index_touch_path "$dir"
}

_to_first_exact_match() {
  local roots_ref="$1"
  local query="$2"
  local -a search_roots matches
  local root match best

  [[ "$query" != */* ]] || return 1

  search_roots=("${(@P)roots_ref}")

  matches=("${(@f)$(_to_index_query exact "$query")}")
  matches=("${(@)matches:#}")
  if (( ${#matches} > 0 )); then
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

_to_collect_matches_for_mode() {
  local -a search_roots queries unique ranked
  local root dir key roots_ref mode
  local -a seen

  roots_ref="$1"
  mode="$2"
  search_roots=("${(@P)roots_ref}")
  shift 2
  queries=("$@")

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

  if (( ${#queries} == 1 )); then
    matches=("${(@f)$(_to_index_query exact "${queries[@]}")}")
    matches=("${(@)matches:#}")
    if (( ${#matches} > 0 )); then
      printf '%s\n' "${matches[@]}"
      return
    fi
  fi

  if (( ${#queries} == 1 )) && [[ "$queries[1]" != */* ]]; then
    matches=("${(@f)$(_to_collect_matches_for_mode "$roots_ref" exact "${queries[@]}")}")
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
      printf '%s\n' "${(@f)$(_to_prune_descendant_matches "${matches[@]}")}"
      return
    fi

    matches=("${(@f)$(_to_collect_matches_for_mode "$roots_ref" path "${queries[@]}")}")
    matches=("${(@)matches:#}")
    if (( ${#matches} > 0 )); then
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
      printf '%s\n' "${(@f)$(_to_prune_descendant_matches "${matches[@]}")}"
      return
    fi

    _to_collect_matches_for_mode "$roots_ref" broad "${queries[@]}"
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
      exact_target="$(_to_first_exact_match roots "$queries[1]")"
      if [[ -n "$exact_target" ]]; then
        print -r -- "$exact_target"
        return
      fi
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
  if command -v fswatch >/dev/null 2>&1; then
    print -r -- fswatch
  elif command -v inotifywait >/dev/null 2>&1; then
    print -r -- inotifywait
  else
    return 1
  fi
}

_to_watch_reindex_after_event() {
  (( TO_WATCH_DEBOUNCE > 0 )) && sleep "$TO_WATCH_DEBOUNCE"
  _to_reindex
}

_to_watch_with_fswatch() {
  local -a roots

  roots=("$@")
  print -u2 -- "to: watching roots with fswatch; press Ctrl-C to stop"
  while fswatch -1 -r "${roots[@]}" >/dev/null 2>&1; do
    _to_watch_reindex_after_event || return 1
  done
}

_to_watch_with_inotifywait() {
  local -a roots
  local event

  roots=("$@")
  print -u2 -- "to: watching roots with inotifywait; press Ctrl-C to stop"
  inotifywait -m -r -e create -e delete -e move -e attrib --format '%w%f' "${roots[@]}" 2>/dev/null |
    while IFS= read -r event; do
      [[ -n "$event" ]] || continue
      _to_watch_reindex_after_event || return 1
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
    print -u2 -- "to: watcher requires fswatch or inotifywait"
    return 1
  }

  case "$backend" in
    fswatch)
      _to_watch_with_fswatch "${roots[@]}"
      ;;
    inotifywait)
      _to_watch_with_inotifywait "${roots[@]}"
      ;;
  esac
}

_to_doctor() {
  print -r -- "to config: $TO_CONFIG_FILE"
  print -r -- "to roots:  $TO_ROOTS_FILE"
  print -r -- "to index:  $TO_INDEX_FILE"
  if command -v fd >/dev/null 2>&1; then
    print -r -- "fd: yes ($(command -v fd))"
  else
    print -r -- "fd: no, using find fallback"
  fi
  if command -v fzf >/dev/null 2>&1; then
    print -r -- "fzf: yes ($(command -v fzf))"
  else
    print -r -- "fzf: no, using numbered selection"
  fi
  if command -v sqlite3 >/dev/null 2>&1; then
    print -r -- "sqlite3: yes ($(command -v sqlite3))"
  else
    print -r -- "sqlite3: no, using TSV index fallback"
  fi
  if [[ -n "$TO_HELPER" && -x "$TO_HELPER" ]]; then
    print -r -- "helper: yes ($TO_HELPER)"
  else
    print -r -- "helper: no"
  fi
  if _to_watch_backend >/dev/null 2>&1; then
    print -r -- "watcher: yes ($(_to_watch_backend))"
  else
    print -r -- "watcher: no"
  fi
  if [[ -n "$TO_AI_COMMAND" ]]; then
    print -r -- "ai command: $TO_AI_COMMAND"
  else
    print -r -- "ai command: no"
  fi
  if [[ -n "$TO_AI_RANK_COMMAND" ]]; then
    print -r -- "ai rank command: $TO_AI_RANK_COMMAND"
  else
    print -r -- "ai rank command: no"
  fi
  print -r -- "max depth: $TO_MAX_DEPTH"
  print -r -- "path fragment search: $TO_SEARCH_PATH_FRAGMENTS"
  print -r -- "follow symlinks: $TO_FOLLOW_SYMLINKS"
  print -r -- "watch debounce: $TO_WATCH_DEBOUNCE"
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

_to_git_repo_matches() {
  local query="$1"
  local -a matches roots candidates seen
  local root dir repo key

  matches=("${(@f)$(_to_index_query git "$query")}")
  matches=("${(@)matches:#}")
  if (( ${#matches} > 0 )); then
    printf '%s\n' "${matches[@]}"
    return
  fi

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
      [[ "${(L)repo:t}" == *"${(L)query}"* || "${(L)repo}" == *"${(L)query}"* ]] || continue
      key="${repo:A}"
      (( ${seen[(Ie)$key]} > 0 )) && continue
      seen+=("$key")
      print -r -- "$key"
    done
  done
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
  to repo <query>           Jump to a matching Git repository
  to recent                 Choose from recent jumps
  to workspace <name> <dir> Add a workspace alias
  to work <name>            Jump to a workspace
  to unwork <name>          Remove a workspace
  to workspaces             List workspaces
  to ai <query...>          Use TO_AI_COMMAND, or broad fallback search
  to --doctor               Check dependencies and config
  to --reindex              Rebuild the directory index
  to --watch                Watch roots and reindex after filesystem changes

Config:
  TO_SEARCH_PATH_FRAGMENTS=0  Prefer exact directory names by default
  TO_SEARCH_PATH_FRAGMENTS=1  Also match any path containing the query
  TO_FOLLOW_SYMLINKS=0         Do not follow symlinks while searching
  TO_FOLLOW_SYMLINKS=1         Follow symlinks while searching
  TO_WATCH_DEBOUNCE=2          Seconds to wait before watcher reindex
  TO_AI_COMMAND               External command that prints candidate dirs
  TO_AI_RANK_COMMAND          External command that ranks candidate dirs from stdin
  TO_HELPER                   Optional to-helper binary path
EOF
}

to() {
  local target alias_target workspace_target

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
      [[ -n "$1" ]] || {
        print -u2 -- "to: usage: to repo <query>"
        return 2
      }
      target="$(_to_choose_match 0 "${(@f)$(_to_git_repo_matches "$1")}")"
      if [[ $? -ne 0 || -z "$target" ]]; then
        print -u2 -- "to: no matching Git repository: $1"
        print -u2 -- "to: add the parent directory with: to use <dir>"
        return 1
      fi
      cd "$target" && _to_after_cd "$PWD"
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
        print -u2 -- "to: no AI/fallback matches: ${(j: :)@}"
        return 1
      fi
      cd "$target" && _to_after_cd "$PWD"
      ;;
    --doctor)
      _to_doctor
      ;;
    --reindex)
      _to_reindex
      ;;
    --watch)
      _to_watch
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
      if [[ $? -ne 0 || -z "$target" ]]; then
        print -u2 -- "to: no matching directory: ${(j: :)@}"
        print -u2 -- "to: add a search root with: to use <dir>"
        return 1
      fi
      cd "$target" && _to_after_cd "$PWD"
      ;;
  esac
}

if (( $+functions[compdef] )); then
  compdef _to to 2>/dev/null
fi
