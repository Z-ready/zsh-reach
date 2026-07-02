# to

`to` is an **exploratory directory jumper for zsh**.

It helps you jump to local folders by name, path fragment, keyword, workspace,
alias, recent destination, or Git repository.

```zsh
to backend
to src/components
to app backend
to repo nginx
```

zoxide optimizes history: it gets better after you visit directories.
`to` optimizes discovery: it indexes configured roots and finds matching
folders even if you have never visited them before.

[Getting started](#getting-started) • [Installation](#installation) •
[Usage](#usage) • [Configuration](#configuration) •
[Performance](#performance) • [Troubleshooting](#troubleshooting)

## Getting Started

Install `to`:

```zsh
brew tap Z-ready/zsh-to https://github.com/Z-ready/zsh-to
brew trust --formula z-ready/zsh-to/to
brew install to
```

Add this to the end of `~/.zshrc`:

```zsh
eval "$(to init zsh)"
```

Reload zsh:

```zsh
source ~/.zshrc
```

Add a focused search root:

```zsh
to use ~/Projects
```

Build the initial index:

```zsh
to --reindex
```

Jump:

```zsh
to backend
```

Check the installed version:

```zsh
to --version
```

## Installation

`to` can be installed with Homebrew.

### 1. Install `to`

```zsh
brew tap Z-ready/zsh-to https://github.com/Z-ready/zsh-to
brew trust --formula z-ready/zsh-to/to
brew install to
```

Homebrew installs the full runtime environment:

| Dependency | Why it is installed |
| --- | --- |
| `fd` | Fast filesystem discovery |
| `fzf` | Interactive result selection |
| `sqlite` | Index, aliases, workspaces, recent entries, ranking data |
| `fswatch` | Optional filesystem watching on macOS |
| `inotify-tools` | Optional filesystem watching on Linux |
| `rust` | Build-time only, used to compile `to-helper` |

### 2. Set up zsh

Add this to `~/.zshrc`:

```zsh
eval "$(to init zsh)"
```

This loads the zsh function that performs the final `cd`.

If you prefer direct sourcing:

```zsh
source "$(brew --prefix to)/share/to/to.plugin.zsh"
```

### 3. Optional: rebuild zsh completions

Homebrew installs zsh completions. If completions do not appear:

```zsh
rm -f ~/.zcompdump*
autoload -Uz compinit
compinit
```

### 4. Source install

Homebrew is the recommended install path. For a manual source install:

Install build and runtime dependencies first:

```zsh
# macOS
brew install rust fd fzf sqlite zsh fswatch
```

```sh
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y git zsh cargo fd-find fzf sqlite3 inotify-tools
sudo ln -sf "$(command -v fdfind)" /usr/local/bin/fd
```

`git`, `zsh`, and Rust/Cargo are required to build and load `to`. `fd`, `fzf`,
`sqlite3`, and a watcher (`fswatch` on macOS, `inotifywait` from
`inotify-tools` on Linux) provide the full runtime experience.

```zsh
git clone https://github.com/Z-ready/zsh-to.git
cd zsh-to
cargo build --release

install -d ~/.local/bin ~/.local/share/to ~/.local/share/zsh/site-functions
install -m 755 bin/to ~/.local/bin/to
install -m 755 target/release/to-helper ~/.local/bin/to-helper
install -m 644 to.plugin.zsh ~/.local/share/to/to.plugin.zsh
install -m 644 completions/_to ~/.local/share/zsh/site-functions/_to
```

Then make sure `~/.local/bin` is on `PATH` and add the normal zsh setup:

```zsh
eval "$(to init zsh)"
```

Manual installs can also source the plugin directly:

```zsh
source ~/.local/share/to/to.plugin.zsh
```

If you want completions from a manual install, make sure the completion
directory is in `fpath` before `compinit`:

```zsh
fpath=("$HOME/.local/share/zsh/site-functions" $fpath)
autoload -Uz compinit
compinit
```

### 5. Configure roots

`to` searches configured roots. On first load, it automatically uses common
directories that exist on your machine:

```text
~/Projects
~/Code
~/Developer
~/dev
~/src
~/workspace
~/workspaces
~/repos
~/git
~/i
~/Documents
~/Pictures
~/Downloads
~/Desktop
```

Add your own roots when your code lives somewhere else:

```zsh
to use ~/Projects
to use ~/Downloads
to roots
```

Avoid using your whole home directory as the only root unless you really want
that broader scan:

```zsh
to use ~
```

## Usage

### Basic jumps

Jump to a directory by exact name:

```zsh
to backend
```

Jump by path fragment:

```zsh
to src/components
```

Jump by multiple keywords:

```zsh
to app backend
```

Force interactive selection:

```zsh
to -i backend
```

Temporarily search from one root:

```zsh
to -r ~/Projects backend
to --from ~/Projects backend
```

### Built-in aliases

These aliases work when the target directories exist:

```text
download / downloads -> ~/Downloads
desktop              -> ~/Desktop
document/documents   -> ~/Documents
project/projects     -> ~/Projects
code                 -> ~/Code
```

Example:

```zsh
to download
```

### User aliases

Add an alias:

```zsh
to add blog ~/Documents/obsidian/blog
```

Use it:

```zsh
to blog
```

List aliases:

```zsh
to aliases
```

Remove an alias:

```zsh
to remove blog
```

### Search roots

`to` automatically includes common existing development directories such as
`~/Projects`, `~/Code`, `~/Developer`, `~/dev`, `~/src`, `~/workspace`,
`~/repos`, `~/git`, and `~/i`. It also includes common user-content
directories such as `~/Documents`, `~/Pictures`, `~/Downloads`, and
`~/Desktop` when they exist.

Add the current directory:

```zsh
to use .
```

Add a specific directory:

```zsh
to use ~/Projects
```

List roots:

```zsh
to roots
```

Remove a root:

```zsh
to unuse ~/Projects
```

Search nearly everything under your home directory:

```zsh
to use ~
to --reindex
```

This makes discovery broader, but it also increases indexing time and energy
use. For most developer machines, adding focused roots is the better default.

### Workspaces

Workspaces are named destinations:

```zsh
to workspace work ~/Documents/work
to work work
```

List workspaces:

```zsh
to workspaces
```

Remove a workspace:

```zsh
to unwork work
```

### Git repositories

Jump to an indexed Git repository:

```zsh
to repo nginx
```

`to` detects `.git` directories during indexing and stores that metadata in
SQLite, so `to repo <query>` does not need to inspect every candidate live.

### Recent destinations

Jump from recent successful destinations:

```zsh
to recent
```

### AI hooks

`to` does not bundle a hosted AI model. It provides hooks for users who want
to connect their own local or remote ranker.

Use broad AI-style fallback search:

```zsh
to ai docker
```

Set `TO_AI_COMMAND` to provide candidates for `to ai <query...>`.
Set `TO_AI_RANK_COMMAND` to reorder normal fallback candidates from stdin.
These hooks execute commands you configure yourself. Treat them like shell
aliases: only point them at scripts you trust.

## Command Reference

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

to workspace work ~/Work  # add a workspace
to work work              # jump to a workspace
to unwork work            # remove a workspace
to workspaces             # list workspaces

to repo nginx             # jump to a matching Git repository
to recent                 # jump from recent destinations
to ai docker              # use TO_AI_COMMAND, or broad fallback search

to init zsh               # print zsh integration script
to --reindex              # refresh the SQLite/TSV directory index
to --watch                # watch roots and reindex after filesystem changes
to --doctor               # check dependencies and config
to --version              # show version
```

`to init zsh`, `to --doctor`, `to --reindex`, `to --watch`, `to --version`,
and state-management commands such as `to roots` can run from the installed
`bin/to` wrapper. Directory jumps require shell integration because only a zsh
function can change the current shell's working directory.

When multiple matches are found, `to` opens `fzf`. If `fzf` is unavailable, it
prints a numbered list.

## Matching

Resolution order:

1. Built-in aliases.
2. User aliases.
3. Workspaces.
4. SQLite exact-name matches.
5. SQLite Git repo matches.
6. SQLite token matches for multi-word queries.
7. SQLite path-fragment matches.
8. `fd` discovery, with `find` fallback.

Exact directory names win for plain single-word queries:

```zsh
to assignment
```

If `~/Downloads/Assignment` exists, `to assignment` jumps there instead of
listing every child directory below it.

Path fragments work when the query contains a slash:

```zsh
to src/components
```

Multi-word queries require every token to appear somewhere in the path:

```zsh
to app backend
```

Plain single-word path-fragment matching is disabled by default. Enable it
only if you want broader results:

```zsh
TO_SEARCH_PATH_FRAGMENTS=1
```

## Configuration

Configuration is loaded from:

```zsh
~/.config/to/config.zsh
```

Example:

```zsh
TO_ROOTS=(
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
TO_WATCH_DEBOUNCE=2
TO_AI_COMMAND=""
TO_AI_RANK_COMMAND=""
TO_HELPER=""
```

Options:

| Option | Default | Meaning |
| --- | --- | --- |
| `TO_MAX_DEPTH` | `8` | Maximum scan depth per root |
| `TO_INTERACTIVE_THRESHOLD` | `3` | Result count where selection becomes useful |
| `TO_SEARCH_PATH_FRAGMENTS` | `0` | Let plain words match anywhere in paths |
| `TO_FOLLOW_SYMLINKS` | `0` | Search through symlinked directory trees |
| `TO_WATCH_DEBOUNCE` | `2` | Seconds to wait before watcher reindex |
| `TO_AI_COMMAND` | empty | External command for `to ai <query...>` |
| `TO_AI_RANK_COMMAND` | empty | External command that ranks candidates from stdin |
| `TO_HELPER` | auto | Explicit path to `to-helper` |

Persistent state lives under `~/.config/to` by default:

```text
roots         configured search roots
index.sqlite3 SQLite dirs, tokens, aliases, workspaces, recent, root metadata
aliases       text fallback for aliases
workspaces    text fallback for workspaces
recent        text fallback for recent jumps
index.tsv     fallback directory index when sqlite3 is unavailable
```

Set `TO_CONFIG_HOME` before loading the plugin to use another config
directory:

```zsh
TO_CONFIG_HOME="$HOME/.local/state/to"
eval "$(to init zsh)"
```

Invalid numeric or boolean config values fall back to safe defaults instead of
breaking shell startup.

## Safety

`to` changes only shell state and files under `TO_CONFIG_HOME`. It does not
delete user directories. When cached paths become stale, `to` prunes those rows
from its own SQLite/TSV index and falls back to live filesystem search.

Path handling is quoted and tested with spaces and unicode. SQL queries quote
user input before passing it to SQLite.

`TO_AI_COMMAND` and `TO_AI_RANK_COMMAND` are explicit escape hatches for users
who want custom ranking. They are not sandboxed; configure them only with
commands you would be comfortable running directly in your shell.

## Performance

`to` does not run a background daemon. Idle cost is effectively zero.

Normal jumps are index-first:

```text
query -> SQLite -> validate path -> cd
                  -> fallback to fd/find on miss or stale path
                  -> write fresh result back to SQLite
```

The SQLite index stores:

```sql
dirs(id, path, name, parent, depth, is_git, last_seen, last_used, hit_count)
tokens(token, dir_id)
roots(path, mtime, config_key, last_indexed)
aliases(name, path)
workspaces(name, path)
recent(path, last_used)
```

Successful jumps update `hit_count` and `last_used`, so ranking improves with
use. Results are ordered roughly as:

```text
exact name > recent/frequent > shallower depth > shorter path
```

`to --reindex` is incremental for SQLite. It records root mtime and
index-affecting config, skips unchanged roots, refreshes changed roots, adds
new directories, and prunes stale directories under refreshed roots.

Broader modes cost more:

- `to src/components` searches a path fragment.
- `to -i backend` collects all matches for selection.
- `TO_SEARCH_PATH_FRAGMENTS=1` lets single words match anywhere in a path.
- `to --watch` runs a foreground watcher and reindexes after filesystem events.

For lower energy use on large machines, prefer:

```zsh
TO_MAX_DEPTH=5
TO_SEARCH_PATH_FRAGMENTS=0
TO_FOLLOW_SYMLINKS=0
```

## Troubleshooting

Check the environment:

```zsh
to --doctor
```

Refresh the index:

```zsh
to --reindex
```

Confirm zsh integration:

```zsh
to init zsh
```

Force selection if the automatic choice is not what you want:

```zsh
to -i backend
```

Search one tree without changing saved roots:

```zsh
to -r ~/Projects backend
```

If `to` finds too many matches, keep broad path search disabled:

```zsh
TO_SEARCH_PATH_FRAGMENTS=0
```

If `to` does not find a repository, check whether its parent directory is in
your roots:

```zsh
to roots
to use ~/path-that-contains-your-repos
to --reindex
```

If `to` is slow, check roots and reduce depth:

```zsh
to roots
TO_MAX_DEPTH=5
```

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full local verification gate and
[RELEASE.md](RELEASE.md) for the release checklist.

Run the zsh test suite:

```zsh
zsh tests/run.zsh
```

Run the full local verification gate:

```zsh
zsh scripts/check.zsh
```

For local formula development:

```zsh
brew tap-new local/to
cp Formula/to.rb "$(brew --repository local/to)/Formula/to.rb"
brew install local/to/to
```
