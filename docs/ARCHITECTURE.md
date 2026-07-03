# Architecture

`to` has two runtime pieces:

- `bin/to`: a zsh wrapper used before shell integration. It prints the init
  script and can run non-jump commands such as `--doctor`, `--reindex`,
  `roots`, and `--version`.
- `to.plugin.zsh`: the shell integration. It defines the `to` function that can
  change the current shell's working directory.

The Rust binary, `to-helper`, is an optional accelerator for SQLite queries. The
zsh implementation remains the source of truth so the tool can fall back to
plain `sqlite3`, TSV files, `fd`, or `find`.

## Data flow

```text
query
  -> built-in aliases
  -> user aliases
  -> workspaces
  -> frecency history
  -> SQLite directory/file/repository index
  -> explicit object adapters (file/dir/ws/package/code)
  -> external shortcut adapters (issue/pr/gh/vscode/fig)
  -> TSV fallback
  -> live fd/find search
  -> interactive selection when needed
  -> cd
  -> recent/frecency/index/stat bookkeeping
```

## Persistent state

By default, all state lives under `~/.config/to`:

- `roots`: configured search roots.
- `index.sqlite3`: primary index when SQLite is available.
- `index.tsv`: fallback index when SQLite is unavailable.
- `aliases`: text fallback for user aliases.
- `workspaces`: text fallback for workspaces.
- `recent`: text fallback for recent destinations.

The SQLite database also owns frecency and runtime-diagnostic state:

- `history(path, visits, last_used)`: successful jumps update one row.
- `files(path, name, stem, parent, depth, last_seen)`: file-name cache populated
  on demand.
- `stats(key, value)`: last search outcome, hit counters, and last reindex.
- `dirs.repo` and `dirs.repo_name`: Git repository metadata populated during
  reindex and live repo fallback.

Queries use history before the directory index when `TO_FRECENCY=1`, then fall
back to index and live discovery if no history score reaches
`TO_FRECENCY_THRESHOLD`.

`TO_CONFIG_HOME` can move this state directory.

## Current module boundaries

`to.plugin.zsh` is intentionally still a single shipped file. That keeps
Homebrew installation and `eval "$(to init zsh)"` simple, but the file has clear
internal areas:

1. Config defaults and path expansion.
2. Root, alias, workspace, recent, frecency, and runtime-stat state.
3. SQLite schema and migration.
4. Index collection, refresh, pruning, and query.
5. Matching and ranking.
6. Object navigation adapters.
7. External shortcut adapters.
8. Interactive selection.
9. Watcher and doctor commands.
10. Public `to` command dispatch.

## Refactor plan

If the plugin is split later, keep the installed public surface unchanged:

- `bin/to` must still print one sourceable entrypoint.
- Homebrew should still install the plugin under `share/to`.
- Direct source installs should still work from a single documented directory.
- Tests must continue to drive the public `to` function rather than private
  helper files.

The safest split order is:

1. Move SQLite/index helpers into a sourced `index.zsh`.
2. Move state helpers into a sourced `state.zsh`.
3. Move matching/selection helpers into a sourced `match.zsh`.
4. Keep command dispatch in `to.plugin.zsh`.

Each split should preserve function names until the test suite has equivalent
coverage for the new boundary.
