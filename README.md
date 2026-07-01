# to

`to` is an exploratory zsh directory jumper. Instead of learning only the
directories you have visited, it searches configured directory trees and jumps
to folders that match a name, path fragment, or set of keywords.

```zsh
to download
to backend
to src/components
to app backend
```

Because changing the current shell directory must happen in the parent shell,
`to` is implemented as a zsh function.

## Install

### Manual

Source the plugin from your zsh config:

```zsh
source /path/to/zsh-to/to.plugin.zsh
```

Plugin managers can load `to.plugin.zsh` directly.

### Homebrew

Install from the project tap:

```zsh
brew tap Z-ready/zsh-to https://github.com/Z-ready/zsh-to
brew install to
```

Then add this to `~/.zshrc`:

```zsh
source "$(brew --prefix to)/share/to/to.plugin.zsh"
```

Reload zsh:

```zsh
source ~/.zshrc
```

Then start using it:

```zsh
to use ~/Projects
to backend
```

For local formula development, create a local tap and copy the formula into it:

```zsh
brew tap-new local/to
cp /Users/z-ready/i/zsh-to/Formula/to.rb "$(brew --repository local/to)/Formula/to.rb"
brew install local/to/to
```

## Commands

```zsh
to <query...>             # search and cd to a matching directory
to -i <query...>          # force interactive selection
to -r <root> <query...>   # temporarily search from one root
to --from <root> <query>  # same as -r
to use .                  # add the current directory as a search root
to use ~/Projects         # add a specific search root
to unuse ~/Projects       # remove a search root
to roots                  # list search roots
to add blog ~/Notes/blog  # add a user alias
to remove blog            # remove a user alias
to aliases                # list user aliases
to repo nginx             # jump to a matching Git repository
to recent                 # jump from recent destinations
to workspace work ~/Work  # add a workspace
to work work              # jump to a workspace
to unwork work            # remove a workspace
to workspaces             # list workspaces
to ai docker              # run configured AI search or broad fallback
to --reindex              # rebuild the SQLite/TSV directory index
to --doctor               # check dependency and config state
```

When multiple matches are found, `to` uses `fzf` if available. Without `fzf`, it
prints a numbered list and reads a selection.

## Matching

`to` checks built-in aliases first:

```text
download / downloads -> ~/Downloads
desktop              -> ~/Desktop
document/documents   -> ~/Documents
project/projects     -> ~/Projects
code                 -> ~/Code
```

For directory discovery, it searches roots with `fd` when available and falls
back to `find`. A single plain query prefers an exact directory name,
case-insensitively:

```zsh
to assignment
```

If `~/Downloads/Assignment` exists, `to` jumps there directly instead of listing
every child path below it.

Queries that contain a slash still work as path fragments:

```zsh
to src/components
```

Multiple query words must all appear somewhere in the path:

```zsh
to app backend
```

Plain path-fragment search can be enabled in config when you want broader
exploration for single words:

```zsh
TO_SEARCH_PATH_FRAGMENTS=1
```

User aliases are checked before discovery:

```zsh
to add blog ~/Documents/obsidian/blog
to blog
```

Workspaces are named roots you jump to directly:

```zsh
to workspace work ~/Documents/work
to work work
```

Git-aware search finds directories that contain `.git`:

```zsh
to repo nginx
```

Recent destinations are recorded after successful jumps:

```zsh
to recent
```

## Configuration

Configuration is loaded from:

```zsh
~/.config/to/config.zsh
```

Example:

```zsh
TO_ROOTS=(
  "$HOME"
  "$HOME/Projects"
  "$HOME/Documents"
)

TO_EXCLUDES=(
  ".git"
  "node_modules"
  "target"
  ".venv"
  "Library"
)

TO_MAX_DEPTH=8
TO_INTERACTIVE_THRESHOLD=3
TO_SEARCH_PATH_FRAGMENTS=0
TO_FOLLOW_SYMLINKS=0
TO_AI_COMMAND=""
TO_HELPER=""
```

`TO_SEARCH_PATH_FRAGMENTS=0` is the default. In that mode, `to assignment`
means “jump to a folder named Assignment.” Set it to `1` if you also want
`to sign` to match paths like `~/Downloads/Assignment`.

`TO_FOLLOW_SYMLINKS=0` is the default. Keep it off unless you intentionally
want `to` to search through symlinked directory trees.

Persistent roots managed by `to use` and `to unuse` are stored in:

```zsh
~/.config/to/roots
```

Other state files live in the same config directory:

```text
aliases       user aliases from `to add`
workspaces    workspace aliases from `to workspace`
recent        recent successful jumps
index.sqlite3 SQLite directory index when sqlite3 is available
index.tsv     fallback index when sqlite3 is unavailable
```

`TO_AI_COMMAND` is an extension point. When set, `to ai <query>` runs that
command with the query and expects it to print candidate directories. Without
it, `to ai` uses the broad built-in search fallback.

`TO_HELPER` is reserved for an optional future Rust helper binary. The zsh
plugin reports it in `to --doctor` but does not require it.

Set `TO_CONFIG_HOME` before sourcing the plugin to use a different config
directory, which is useful for tests or isolated setups.

## Performance

`to` does not run a background service. Idle cost is effectively zero.

The default path is optimized for the common programmer workflow:

```zsh
to backend
to api
to components
```

For a single plain query, `to` asks `fd`/`find` to search for a matching
directory name directly. In normal non-interactive mode it uses the first root
that has exact matches and jumps to the shortest matching path, so it avoids
materializing every directory under every root in zsh.

Broader modes cost more:

- `to src/components` searches for a path fragment.
- `to app backend` checks paths that contain all query words.
- `TO_SEARCH_PATH_FRAGMENTS=1` allows single words to match anywhere in a path.
- `to -i name` collects all exact matches so you can choose one.

Cost is proportional to the number of directories under your configured roots,
up to `TO_MAX_DEPTH`. By default, `to` uses common focused roots such as
`~/Projects`, `~/Code`, `~/Documents`, `~/Downloads`, and `~/Desktop` when they
exist. It does not default to scanning your whole home directory. Prefer adding
focused roots:

```zsh
to use ~/Projects
to use ~/Downloads
```

Avoid making your whole home directory the only root unless you really want
that behavior:

```zsh
to use ~
```

For lower energy use on large machines, keep:

```zsh
TO_MAX_DEPTH=5
TO_SEARCH_PATH_FRAGMENTS=0
TO_FOLLOW_SYMLINKS=0
```

For faster repeated searches, build the cache:

```zsh
to --reindex
```

If `sqlite3` is installed, the cache is stored in SQLite. Otherwise `to` writes
a TSV fallback index. Normal search still works without an index.

## Current Scope

Implemented MVP:

- zsh plugin entrypoint
- `to <query>` jump behavior
- `fd` search with `find` fallback
- `fzf` multi-result selection with numbered fallback
- built-in common directory aliases
- `to use`, `to unuse`, and `to roots`
- common directory excludes
- `to --doctor`
- exact-name-first matching with optional broad path-fragment search
- exact-name fast path with early stop for normal jumps
- `to --reindex` with SQLite and TSV fallback
- user alias system
- Git repository search
- recent destinations
- workspaces
- zsh completion
- AI search command hook
- Rust helper hook

Reserved for later:

- built-in AI model integration
- compiled Rust helper implementation
- frequency scoring
