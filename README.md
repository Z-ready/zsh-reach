# reach

[![CI](https://github.com/Z-ready/zsh-to/actions/workflows/ci.yml/badge.svg)](https://github.com/Z-ready/zsh-to/actions/workflows/ci.yml)

`reach` is a fast zsh directory and object jumper. Its default command is
`gt`, chosen to avoid common collisions while staying short enough to type all
day.

`zoxide` takes you where you have been; `reach` takes you anywhere under your
roots without opening a `broot`-style interactive browser first.

```zsh
gt backend
gt src/components
gt app backend
gt repo nginx
gt cargo tokio
gt package.json
gt gh Z-ready/zsh-to
```

| Tool | Needs visit history | Requires interactive UI | Cross-shell scope | Runtime dependencies |
| --- | --- | --- | --- | --- |
| `reach` | No | No | zsh now; bash/fish planned | `zsh`; `fzf` optional |
| `zoxide` | Yes | No | broad | shell integration |
| `broot` | No | Yes | broad | `broot` binary |
| hand-rolled `fd+fzf` | No | Usually yes | shell snippet specific | `fd`, `fzf`, custom glue |

[Installation](#installation) | [Usage](#usage) | [Configuration](#configuration) |
[Architecture](docs/ARCHITECTURE.md) | [Changelog](CHANGELOG.md)

## Installation

Homebrew users can install from the formula once the release tag is published:

```zsh
brew install ./Formula/reach.rb
```

Release installer:

```zsh
curl -fsSL https://github.com/Z-ready/zsh-to/releases/latest/download/install.sh | sh
```

Then add this to `~/.zshrc`:

```zsh
eval "$(reach init zsh)"
```

Reload your shell and jump:

```zsh
source ~/.zshrc
gt backend
```

For source builds:

```zsh
git clone https://github.com/Z-ready/zsh-to.git
cd zsh-to
cargo build --release

install -d ~/.local/bin ~/.local/share/reach ~/.local/share/zsh/site-functions
install -m 755 bin/reach ~/.local/bin/reach
install -m 755 target/release/reach-helper ~/.local/bin/reach-helper
install -m 644 to.plugin.zsh ~/.local/share/reach/to.plugin.zsh
install -m 644 completions/_gt ~/.local/share/zsh/site-functions/_gt
```

Runtime dependencies are intentionally small:

| Dependency | Required | Purpose |
| --- | --- | --- |
| `zsh` | yes | shell integration and `cd` |
| `reach-helper` | recommended | bundled SQLite, traversal, and watcher backend |
| `fzf` | optional | interactive selection when there are many matches |
| `fd`, `sqlite3`, `fswatch`, `inotifywait` | no | legacy compatibility paths only |

## Usage

`gt` searches your home directory by default. Add focused roots when your work
lives elsewhere:

```zsh
gt use ~/Projects
gt roots
gt --reindex
```

Common jumps:

```zsh
gt backend                # exact directory name
gt src/components         # path fragment
gt app backend            # multiple keywords
gt README.md              # directory containing a file
gt repo ai template       # Git repository metadata
gt recent                 # recent destinations
gt -i backend             # force fzf selection
gt -r /mnt/data backend   # temporary root
```

Object commands narrow the same engine:

```zsh
gt file README.md
gt dir backend
gt ws work
gt cargo tokio
gt npm react
gt py fastapi
gt docker nginx
gt code authenticate_user
gt issue 123
gt pr 456
gt gh Z-ready/zsh-to
gt vscode backend
gt fig backend
```

The old `to` function remains as a compatibility alias during the `1.x`
migration window. New docs and examples use `gt`. The planned removal point for
the legacy `to` command is `v2.0.0`; migrate shell snippets to `gt` before then.

## How Matching Works

Resolution order:

1. Built-in aliases.
2. User aliases.
3. Workspaces.
4. Frecency history.
5. SQLite directory, file, and repository indexes.
6. Bounded live traversal under configured roots.
7. Deep traversal fallback when the bounded scan misses.
8. Optional interactive selection.

`reach-helper` owns the hot path through Rust and bundled SQLite:

```sql
PRAGMA journal_mode = WAL;
PRAGMA busy_timeout = 5000;
PRAGMA synchronous = NORMAL;
```

The helper also performs ignored-aware traversal, symlink-loop protection, and
native filesystem watching through the Rust `notify` crate. The zsh `sqlite3`
fallback is retained only for older installs without `reach-helper`.

## Configuration

Configuration is loaded from:

```zsh
~/.config/reach/config.zsh
```

Common options:

```zsh
TO_ROOT_MODE=home
TO_ROOTS=("$HOME/src")
TO_MAX_DEPTH=8
TO_INTERACTIVE_THRESHOLD=3
TO_SEARCH_PATH_FRAGMENTS=0
TO_FOLLOW_SYMLINKS=0
TO_FRECENCY=1
TO_FRECENCY_THRESHOLD=1
TO_USE_GITIGNORE=1
TO_REACHIGNORE="$HOME/.reachignore"
TO_HOOK_TIMEOUT=5
TO_AI_COMMAND=""
TO_AI_RANK_COMMAND=""
TO_OPEN_COMMAND=""
TO_VSCODE_COMMAND=""
TO_FIG_COMMAND=""
```

User-configured hooks are explicit escape hatches. `TO_AI_COMMAND`,
`TO_AI_RANK_COMMAND`, `TO_OPEN_COMMAND`, `TO_VSCODE_COMMAND`, and
`TO_FIG_COMMAND` run with `TO_HOOK_TIMEOUT` protection; on timeout, `gt` reports
which hook and config key stalled.

Persistent state lives under `~/.config/reach` by default:

```text
roots          configured search roots
index.sqlite3  dirs, tokens, files, history, aliases, workspaces, stats
aliases        text fallback for aliases
workspaces     text fallback for workspaces
recent         text fallback for recent jumps
```

Set `TO_CONFIG_HOME` before loading the plugin to use another directory:

```zsh
TO_CONFIG_HOME="$HOME/.local/state/reach"
eval "$(reach init zsh)"
```

## Ignore Rules

Built-in ignores cover large generated directories such as `.git/`,
`node_modules/`, `target/`, virtualenvs, `__pycache__/`, `dist/`, and `build/`.
Add project-specific rules to:

```zsh
$HOME/.reachignore
```

Project `.gitignore` files are read by default and stack with `.reachignore`.
Set `TO_USE_GITIGNORE=0` to use only built-in and reach-specific rules.

## Troubleshooting

```zsh
gt --doctor
gt --doctor --verbose
gt --reindex
gt --watch
reach --version
```

`gt --doctor` reports helper detection, index/cache size, roots, watcher state,
frecency status, optional hook configuration, and low-level tool paths in
verbose mode.

## Release Checklist

Before publishing:

```zsh
zsh scripts/check.zsh
scripts/benchmark.zsh
brew install --build-from-source ./Formula/reach.rb
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for module boundaries and the
three-layer lookup flow. See [CHANGELOG.md](CHANGELOG.md) for release notes.
