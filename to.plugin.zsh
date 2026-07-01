# to: exploratory directory jumper for zsh.

typeset -ga TO_ROOTS
typeset -ga TO_EXCLUDES
typeset -gi TO_MAX_DEPTH
typeset -gi TO_INTERACTIVE_THRESHOLD
typeset -gi TO_SEARCH_PATH_FRAGMENTS
typeset -gi TO_FOLLOW_SYMLINKS

: ${TO_CONFIG_HOME:="${XDG_CONFIG_HOME:-$HOME/.config}/to"}
: ${TO_CONFIG_FILE:="$TO_CONFIG_HOME/config.zsh"}
: ${TO_ROOTS_FILE:="$TO_CONFIG_HOME/roots"}
: ${TO_INDEX_FILE:="$TO_CONFIG_HOME/index.sqlite3"}
: ${TO_INDEX_TSV_FILE:="$TO_CONFIG_HOME/index.tsv"}
: ${TO_ALIASES_FILE:="$TO_CONFIG_HOME/aliases"}
: ${TO_WORKSPACES_FILE:="$TO_CONFIG_HOME/workspaces"}
: ${TO_RECENT_FILE:="$TO_CONFIG_HOME/recent"}
: ${TO_AI_COMMAND:=""}
: ${TO_HELPER:=""}
(( TO_MAX_DEPTH > 0 )) || TO_MAX_DEPTH=8
(( TO_INTERACTIVE_THRESHOLD > 0 )) || TO_INTERACTIVE_THRESHOLD=3
(( TO_SEARCH_PATH_FRAGMENTS == 0 || TO_SEARCH_PATH_FRAGMENTS == 1 )) || TO_SEARCH_PATH_FRAGMENTS=0
(( TO_FOLLOW_SYMLINKS == 0 || TO_FOLLOW_SYMLINKS == 1 )) || TO_FOLLOW_SYMLINKS=0

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

_to_read_map_value() {
  local file="$1"
  local key="${(L)2}"
  local line item value

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

_to_write_map_value() {
  local file="$1"
  local key="$2"
  local dir="$3"
  local tmp="$file.tmp.$$"
  local line item

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
  local tmp="$file.tmp.$$"
  local line item

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
  local line key value

  [[ -r "$file" ]] || return 0
  while IFS= read -r line; do
    key="${line%%	*}"
    value="${line#*	}"
    [[ "$value" == "$line" ]] && continue
    printf '%s -> %s\n' "$key" "$value"
  done < "$file"
}

_to_user_alias() {
  _to_read_map_value "$TO_ALIASES_FILE" "$1"
}

_to_workspace() {
  _to_read_map_value "$TO_WORKSPACES_FILE" "$1"
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

_to_index_collect_tsv() {
  local output_file="$1"
  local -a roots candidates
  local -a seen
  local root dir key is_git

  _to_load_roots
  roots=("${TO_ROOTS[@]}")
  mkdir -p "$TO_CONFIG_HOME" || return 1
  : > "$output_file" || return 1

  for root in "${roots[@]}"; do
    [[ -d "$root" ]] || continue
    print -u2 -- "to: indexing $root"
    if command -v fd >/dev/null 2>&1; then
      candidates=("${(@f)$(_to_search_dirs_with_fd "$root")}")
    else
      candidates=("${(@f)$(_to_search_dirs_with_find "$root")}")
    fi
    for dir in "${candidates[@]}"; do
      [[ -d "$dir" ]] || continue
      key="${dir:A}"
      (( ${seen[(Ie)$key]} > 0 )) && continue
      seen+=("$key")
      is_git=0
      [[ -d "$key/.git" ]] && is_git=1
      printf '%s\t%s\t%s\t%s\n' "$key" "${key:t}" "${(L)key:t}" "$is_git" >> "$output_file"
    done
  done
}

_to_index_rebuild_sqlite() {
  local tmp="$TO_CONFIG_HOME/index.tsv.tmp.$$"

  mkdir -p "$TO_CONFIG_HOME" || return 1
  _to_index_collect_tsv "$tmp" || return 1
  sqlite3 "$TO_INDEX_FILE" "drop table if exists dirs; create table dirs(path text primary key, name text not null, lower_name text not null, is_git integer not null);" || return 1
  sqlite3 "$TO_INDEX_FILE" ".mode tabs" ".import $tmp dirs" || return 1
  sqlite3 "$TO_INDEX_FILE" "create index idx_dirs_lower_name on dirs(lower_name); create index idx_dirs_is_git on dirs(is_git); create index idx_dirs_path on dirs(path);" || return 1
  rm -f "$tmp"
}

_to_index_rebuild_tsv() {
  _to_index_collect_tsv "$TO_INDEX_TSV_FILE"
}

_to_reindex() {
  if command -v sqlite3 >/dev/null 2>&1; then
    _to_index_rebuild_sqlite || return 1
    print -r -- "to: indexed roots into $TO_INDEX_FILE"
  else
    _to_index_rebuild_tsv || return 1
    print -r -- "to: sqlite3 not found; indexed roots into $TO_INDEX_TSV_FILE"
  fi
}

_to_index_query_sqlite() {
  local mode="$1"
  shift
  local query="${(L)${(j: :)@}}"
  local sql

  [[ -r "$TO_INDEX_FILE" ]] || return 1
  case "$mode" in
    exact)
      sql="select path from dirs where lower_name = $(_to_sql_quote "$query") order by length(path), path limit 50;"
      ;;
    path)
      sql="select path from dirs where lower(path) like $(_to_sql_quote "%$query%") order by length(path), path limit 50;"
      ;;
    git)
      sql="select path from dirs where is_git = 1 and (lower_name = $(_to_sql_quote "$query") or lower(path) like $(_to_sql_quote "%$query%")) order by length(path), path limit 50;"
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
  local query="${(L)${(j: :)@}}"
  local line path name lower_name is_git

  [[ -r "$TO_INDEX_TSV_FILE" ]] || return 1
  while IFS=$'\t' read -r path name lower_name is_git; do
    [[ -d "$path" ]] || continue
    case "$mode" in
      exact)
        [[ "$lower_name" == "$query" ]] && print -r -- "$path"
        ;;
      path)
        [[ "${(L)path}" == *"$query"* ]] && print -r -- "$path"
        ;;
      git)
        [[ "$is_git" == 1 && ( "$lower_name" == "$query" || "${(L)path}" == *"$query"* ) ]] && print -r -- "$path"
        ;;
    esac
  done < "$TO_INDEX_TSV_FILE"
}

_to_index_query() {
  local mode="$1"
  shift

  if command -v sqlite3 >/dev/null 2>&1 && [[ -r "$TO_INDEX_FILE" ]]; then
    _to_index_query_sqlite "$mode" "$@"
  elif [[ -r "$TO_INDEX_TSV_FILE" ]]; then
    _to_index_query_tsv "$mode" "$@"
  else
    return 1
  fi
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
  local -a exact fragment other
  local dir query_l name_l

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

  printf '%s\n' "${exact[@]}" "${fragment[@]}" "${other[@]}"
}

_to_collect_matches_for_mode() {
  local -a search_roots queries candidates unique ranked
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
      candidates=("${(@f)$(_to_search_exact_name "$root" "$queries[1]")}")
    elif command -v fd >/dev/null 2>&1; then
      candidates=("${(@f)$(_to_search_dirs_with_fd "$root")}")
    else
      candidates=("${(@f)$(_to_search_dirs_with_find "$root")}")
    fi

    for dir in "${candidates[@]}"; do
      [[ -d "$dir" ]] || continue
      _to_match_mode_allows "$mode" "$dir" "${queries[@]}" || continue
      key="${dir:A}"
      if (( ${seen[(Ie)$key]} == 0 )); then
        seen+=("$key")
        unique+=("$key")
      fi
    done
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

  matches=("${(@f)$(_to_collect_matches_for_mode "$roots_ref" exact "${queries[@]}")}")
  matches=("${(@)matches:#}")
  if (( ${#matches} > 0 )); then
    printf '%s\n' "${matches[@]}"
    return
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
    matches=("${(@f)$(_to_index_query path "${queries[@]}")}")
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
  if [[ -n "$TO_AI_COMMAND" ]]; then
    print -r -- "ai command: $TO_AI_COMMAND"
  else
    print -r -- "ai command: no"
  fi
  print -r -- "max depth: $TO_MAX_DEPTH"
  print -r -- "path fragment search: $TO_SEARCH_PATH_FRAGMENTS"
  print -r -- "follow symlinks: $TO_FOLLOW_SYMLINKS"
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
  _to_write_map_value "$TO_ALIASES_FILE" "$name" "$dir"
  print -r -- "to: alias $name -> ${dir:A}"
}

_to_remove_alias() {
  [[ -n "$1" ]] || {
    print -u2 -- "to: usage: to remove <name>"
    return 2
  }
  _to_remove_map_value "$TO_ALIASES_FILE" "$1"
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
  _to_write_map_value "$TO_WORKSPACES_FILE" "$name" "$dir"
  print -r -- "to: workspace $name -> ${dir:A}"
}

_to_remove_workspace() {
  [[ -n "$1" ]] || {
    print -u2 -- "to: usage: to unwork <name>"
    return 2
  }
  _to_remove_map_value "$TO_WORKSPACES_FILE" "$1"
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

Config:
  TO_SEARCH_PATH_FRAGMENTS=0  Prefer exact directory names by default
  TO_SEARCH_PATH_FRAGMENTS=1  Also match any path containing the query
  TO_FOLLOW_SYMLINKS=0         Do not follow symlinks while searching
  TO_FOLLOW_SYMLINKS=1         Follow symlinks while searching
  TO_AI_COMMAND               External command that prints candidate dirs
  TO_HELPER                   Optional future Rust/helper binary path
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
      _to_print_map "$TO_ALIASES_FILE"
      ;;
    repo)
      shift
      [[ -n "$1" ]] || {
        print -u2 -- "to: usage: to repo <query>"
        return 2
      }
      target="$(_to_choose_match 0 "${(@f)$(_to_git_repo_matches "$1")}")" || return
      cd "$target" && _to_record_recent "$PWD"
      ;;
    recent)
      target="$(_to_choose_match 0 "${(@f)$(_to_recent_dirs)}")" || return
      cd "$target" && _to_record_recent "$PWD"
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
      cd "$workspace_target" && _to_record_recent "$PWD"
      ;;
    unwork)
      shift
      _to_remove_workspace "$1"
      ;;
    workspaces)
      _to_print_map "$TO_WORKSPACES_FILE"
      ;;
    ai)
      shift
      [[ $# -gt 0 ]] || {
        print -u2 -- "to: usage: to ai <query...>"
        return 2
      }
      target="$(_to_choose_match 0 "${(@f)$(_to_ai_matches "$@")}")" || return
      cd "$target" && _to_record_recent "$PWD"
      ;;
    --doctor)
      _to_doctor
      ;;
    --reindex)
      _to_reindex
      ;;
    -h|--help|"")
      _to_help
      ;;
    *)
      if (( $# == 1 )); then
        alias_target="$(_to_user_alias "$1")"
        if [[ -n "$alias_target" ]]; then
          cd "$alias_target" && _to_record_recent "$PWD"
          return
        fi
        workspace_target="$(_to_workspace "$1")"
        if [[ -n "$workspace_target" ]]; then
          cd "$workspace_target" && _to_record_recent "$PWD"
          return
        fi
      fi
      target="$(_to_resolve "$@")" || return
      [[ -n "$target" ]] || return 1
      cd "$target" && _to_record_recent "$PWD"
      ;;
  esac
}

if (( $+functions[compdef] )); then
  compdef _to to 2>/dev/null
fi
