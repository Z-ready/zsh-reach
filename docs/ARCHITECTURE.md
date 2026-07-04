# Architecture

`reach` has three runtime pieces:

- `bin/reach`: a zsh wrapper used before shell integration. It prints the init
  script and can run non-jump commands such as `--doctor`, `--reindex`,
  `roots`, and `--version`.
- `to.plugin.zsh`: the shell integration. The file name is retained for
  compatibility, but it defines the default `gt` command and the legacy `to`
  function.
- `reach-helper`: the Rust backend for SQLite, traversal, indexing, and native
  filesystem watching.

## Lookup Flow

```text
query
  -> built-in aliases
  -> user aliases
  -> workspaces
  -> frecency history
  -> SQLite directory/file/repository index
  -> explicit object adapters
  -> bounded helper traversal
  -> deep helper traversal
  -> optional fzf selection
  -> cd
  -> history/index/stat bookkeeping
```

The normal path uses `reach-helper` and `rusqlite` with bound parameters.
Legacy zsh fallback paths still exist for older installs without the helper;
those paths use the `sqlite3` CLI and conservative quoting, and are not the
default supported hot path.

## Persistent State

By default, all state lives under `~/.config/reach`:

- `roots`: configured search roots.
- `index.sqlite3`: primary SQLite index.
- `aliases`: text fallback for user aliases.
- `workspaces`: text fallback for workspaces.
- `recent`: text fallback for recent destinations.

The SQLite database owns:

- `dirs(path, name, parent, depth, repo, repo_name, last_seen, last_used, hit_count)`.
- `tokens(token, dir_id)`.
- `files(path, name, stem, parent, depth, last_seen)`.
- `history(path, visits, last_used)`.
- `stats(key, value)`.
- `roots(path, mtime, config_key, last_indexed)`.
- `aliases(name, path)`.
- `workspaces(name, path)`.
- `recent(path, last_used)`.

## Module Boundaries

Rust modules:

- `src/main.rs`: CLI parsing and command dispatch.
- `src/store.rs`: SQLite schema, WAL/busy timeout setup, and store queries.
- `src/traverse.rs`: ignored-aware traversal, cancellation, and symlink guards.
- `src/ignore_rules.rs`: built-in ignores plus `.reachignore` and `.gitignore`.
- `src/watcher.rs`: native watcher wrapper through `notify`.

The zsh plugin intentionally remains a single shipped file so
`eval "$(reach init zsh)"` and Homebrew installs stay simple. The public names
are:

- `gt`: default user command.
- `to`: legacy compatibility command retained through the `1.x` line.
- `reach`: wrapper command for init and non-jump operations.

If the plugin is split later, keep `to.plugin.zsh` as a compatibility entrypoint
and continue testing through the public `gt`/`to` functions.
