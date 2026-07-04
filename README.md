# reach

`reach` is a **fast directory and object jumper for zsh**. Its default jump
command is `gt`, chosen to avoid common collisions while staying short enough
to type all day.

It helps you jump to local folders by name, path fragment, keyword, workspace,
alias, recent destination, frecency history, file name, or Git repository.

```zsh
gt backend
gt src/components
gt app backend
gt repo nginx
gt cargo tokio
gt code auth
gt gh Z-ready/reach
```

`reach` combines zoxide-style history with developer-focused discovery.
Frequently and recently used directories jump first, while the configured-root
index and live fallback still find folders, files, Git repositories, and
developer project objects you have never visited before.

[Getting started](#getting-started) • [Installation](#installation) •
[Usage](#usage) • [Configuration](#configuration) •
[Performance](#performance) • [Troubleshooting](#troubleshooting)

## Getting Started

Install `reach`:

```zsh
curl -fsSL https://github.com/Z-ready/reach/releases/latest/download/install.sh | sh
```

Add this to the end of `~/.zshrc`:

```zsh
eval "$(reach init zsh)"
```

Reload zsh:

```zsh
source ~/.zshrc
```

By default, `gt` searches your home directory. Add focused roots only when you
keep work outside your home directory or want a narrower setup:

```zsh
gt use /path/to/a/root
```

Warm the index when you want faster first searches:

```zsh
gt --reindex
```

Jump:

```zsh
gt backend
```

If you create a new directory after indexing, `gt` can still find it on the
first query through the built-in Rust traversal engine and cache it for later:

```zsh
mkdir -p ~/somewhere/new-service
gt new-service
```

You can also jump by file name. `gt` searches for the file on demand and jumps
to the directory that contains it:

```zsh
gt package.json
gt "project spec.md"
gt 音乐.mp3
```

Check the installed version:

```zsh
gt --version
```

Prefer the old command name? Add this after initialization:

```zsh
alias to=gt
```

## Installation

`reach` is distributed as a small zsh wrapper plus a precompiled
`reach-helper` binary. Users do not need Rust for normal installation.

### 1. Install `reach`

```zsh
curl -fsSL https://github.com/Z-ready/reach/releases/latest/download/install.sh | sh
```

Release assets are published for:

| Platform | Asset |
| --- | --- |
| macOS arm64 | `reach-macos-aarch64.tar.gz` |
| macOS x86_64 | `reach-macos-x86_64.tar.gz` |
| Linux x86_64 | `reach-linux-x86_64.tar.gz` |
| Linux aarch64 | `reach-linux-aarch64.tar.gz` |
| Windows | planned |

Optional companion tools:

| Tool | Behavior when present | Fallback when missing |
| --- | --- | --- |
| `fzf` | Interactive selection for multiple matches | automatically picks the best frecency-ranked match |

### 2. Set up zsh

Add this to `~/.zshrc`:

```zsh
eval "$(reach init zsh)"
```

This loads the zsh function that performs the final `cd`.

If you prefer direct sourcing:

```zsh
source "$HOME/.local/share/reach/to.plugin.zsh"
```

### 3. Optional: rebuild zsh completions

If completions do not appear:

```zsh
rm -f ~/.zcompdump*
autoload -Uz compinit
compinit
```

### 4. Source install

Release binaries are recommended. For a manual source install:

Install build and runtime dependencies first:

```zsh
# macOS
brew install rust zsh
```

```sh
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y git zsh cargo
```

`git`, `zsh`, and Rust/Cargo are required only for source builds. `fzf` is
optional for interactive selection. Directory traversal, SQLite access, and
filesystem watching are built into `reach-helper`.

```zsh
git clone https://github.com/Z-ready/reach.git
cd reach
cargo build --release

install -d ~/.local/bin ~/.local/share/reach ~/.local/share/zsh/site-functions
install -m 755 bin/reach ~/.local/bin/reach
install -m 755 target/release/reach-helper ~/.local/bin/reach-helper
install -m 644 to.plugin.zsh ~/.local/share/reach/to.plugin.zsh
install -m 644 completions/_gt ~/.local/share/zsh/site-functions/_gt
```

Then make sure `~/.local/bin` is on `PATH` and add the normal zsh setup:

```zsh
eval "$(reach init zsh)"
```

Manual installs can also source the plugin directly:

```zsh
source ~/.local/share/reach/to.plugin.zsh
```

If you want completions from a manual install, make sure the completion
directory is in `fpath` before `compinit`:

```zsh
fpath=("$HOME/.local/share/zsh/site-functions" $fpath)
autoload -Uz compinit
compinit
```

## Performance

`reach-helper` owns the hot SQLite path using the bundled SQLite library through
Rust. Database initialization enables:

```sql
PRAGMA journal_mode = WAL;
PRAGMA busy_timeout = 5000;
PRAGMA synchronous = NORMAL;
```

This keeps routine scoring and frecency updates out of `sqlite3` subprocesses
and makes concurrent reads/writes much less fragile. Live discovery uses the
same helper: layer 1 checks frecency and the SQLite index, layer 2 performs a
bounded ignored-aware traversal under configured roots, and layer 3 falls back
to a deeper scan when the bounded search misses. That is why `reach` stays fast
for common jumps while still finding directories and files you have never
visited.

Run the benchmark harness before publishing a release:

```zsh
scripts/benchmark.zsh
```

Current benchmark fields to publish from the release machine:

| Metric | Result |
| --- | --- |
| Cold reindex, ~100k directories | run `scripts/benchmark.zsh` |
| Cached query latency, 50-query proxy | run `scripts/benchmark.zsh` |
| Concurrent write success, 20 jumps | run `scripts/benchmark.zsh` |

TODO: add bash and fish wrappers after the zsh path stabilizes.

### 5. Configure roots

`gt` searches configured roots. On first load, the default root is your home
directory:

```text
~
```

Home-first discovery means any directory under your home directory can be
valid. `to` does not assume names such as `Projects`, `Code`, `workspace`, or
anything author-specific. It still avoids common heavy or noisy directories
through `TO_EXCLUDES`, limits scan depth with `TO_MAX_DEPTH`, and does not
follow symlinked directory trees unless you opt in.

Add extra roots when you keep files outside your home directory:

```zsh
to use /Volumes/Media
to use /work
to roots
```

Search outside your saved roots without changing config:

```zsh
to -r /mnt/data/projects backend
```

Remove roots you no longer want:

```zsh
to unuse /Volumes/Media
```

If your home directory is too large, switch to explicit-root mode and list only
the roots you want searched:

```zsh
TO_ROOT_MODE=explicit
TO_ROOTS=(
  "$HOME/src"
  "/Volumes/Work"
)
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

Jump to the directory containing a file:

```zsh
to Cargo.toml
to package.json
to 音乐.mp3
```

Force interactive selection:

```zsh
to -i backend
```

Temporarily search from one root:

```zsh
to -r /path/to/root backend
to --from /path/to/root backend
```

### Built-in aliases

These aliases work when the target directories exist:

```text
download / downloads -> ~/Downloads
desktop              -> ~/Desktop
document/documents   -> ~/Documents
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

`to` has two discovery modes:

- `TO_ROOT_MODE=home` (default): search `$HOME` plus configured roots.
- `TO_ROOT_MODE=explicit`: search only configured roots.

Home-first mode is intentionally layout-agnostic. You do not need to teach
`to` whether you keep code, notes, media, or work trees under any particular
folder name.

Add the current directory:

```zsh
to use .
```

Add a specific directory:

```zsh
to use /path/to/a/root
```

List roots:

```zsh
to roots
```

Remove a root:

```zsh
to unuse /path/to/a/root
```

If you want a narrower setup for a very large home directory, set
`TO_ROOT_MODE=explicit`, define `TO_ROOTS`, and lower `TO_MAX_DEPTH`.

When a temporary `to -r <root> <query>` search finds a directory outside your
saved roots, `to` tells you which parent to add. Set `TO_AUTO_ADD_ROOTS=1` if
you want those temporary-search parent roots added automatically after a
successful jump. `to` refuses broad system roots such as `/`, `/System`, and
`/usr`; add a narrower directory that contains the places you actually jump to.

### Workspaces

Workspaces are named destinations:

```zsh
to workspace work /path/to/work
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

Jump to an indexed Git repository. Multiple keywords are supported:

```zsh
to repo nginx
to repo ai template
to repo open ai
```

`to` detects `.git` directories during indexing and stores `repo=1` plus the
repository name in SQLite, so `to repo <query...>` is a fast indexed lookup.
If the index misses, `to` falls back to a confined `.git` scan under configured
roots and caches successful repositories.

List recently used repositories:

```zsh
to repo
```

Jump from anywhere inside a repository back to its root:

```zsh
to git
```

### Object navigation

Use explicit object commands when you know what kind of destination you want:

```zsh
to file README.md       # directory containing that file
to dir backend          # directory named or matching backend
to ws work              # workspace named or matching work
to cargo tokio          # Rust project with matching Cargo.toml content
to npm react            # Node project with matching package.json content
to py fastapi           # Python project metadata mentioning fastapi
to docker nginx         # Docker project metadata mentioning nginx
to code auth            # directory containing matching code text
```

These commands respect configured roots, excludes, max depth, and symlink
settings. Successful object jumps update frecency history and the directory
index, so repeated jumps become history or SQLite hits.

### Developer shortcuts

Jump to local clones for issues and pull requests:

```zsh
to issue 123
to pr 456
```

Open GitHub in your browser:

```zsh
gt gh Z-ready/reach
to gh              # from inside a GitHub-backed repository
```

Open a matching directory in an external developer tool:

```zsh
to vscode backend
to fig backend
```

`to gh` uses `open`, `xdg-open`, `wslview`, or `explorer.exe` when available.
Override it with `TO_OPEN_COMMAND`. `to vscode` uses `code` or
`TO_VSCODE_COMMAND`; `to fig` uses `fig` or `TO_FIG_COMMAND`.

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
to use /path/to/root      # add a specific search root
to unuse /path/to/root    # remove a search root
to roots                  # list search roots

to add blog ~/Notes/blog  # add a user alias
to remove blog            # remove a user alias
to aliases                # list user aliases

to workspace work /path/to/work  # add a workspace
to work work              # jump to a workspace
to unwork work            # remove a workspace
to workspaces             # list workspaces

to repo                   # list recent Git repositories
to repo nginx             # jump to a matching Git repository
to repo ai template       # multi-keyword repository search
to git                    # jump to the nearest parent Git repository
to file README.md         # jump to a directory containing README.md
to dir backend            # jump to a matching directory
to ws work                # jump to a matching workspace
to cargo tokio            # jump by Cargo.toml metadata
to npm react              # jump by package.json metadata
gt py fastapi             # jump by Python project metadata
gt docker nginx           # jump by Docker metadata
gt code auth              # jump by code text under configured roots
gt issue 123              # jump to a local issue clone
gt pr 456                 # jump to a local pull-request clone
gt gh Z-ready/reach       # open a GitHub repository
gt vscode backend         # open a matching directory in VS Code
gt fig backend            # run fig for a matching directory
gt recent                 # jump from recent destinations
gt ai docker              # use TO_AI_COMMAND, or broad fallback search

reach init zsh            # print zsh integration script
gt --reindex              # refresh the SQLite directory index
gt --watch                # watch roots and reindex after filesystem changes
gt --doctor               # grouped diagnostics and runtime statistics
gt --doctor --verbose     # include low-level tool paths and AI hooks
gt --version              # show version
```

`reach init zsh`, `reach --doctor`, `reach --reindex`, `reach --watch`,
`reach --version`, and state-management commands such as `reach roots` can run
from the installed `bin/reach` wrapper. Directory jumps require shell integration because only a zsh
function can change the current shell's working directory.

When multiple matches are found, `gt` opens `fzf` if it is installed. If `fzf`
is unavailable, `gt` automatically chooses the best ranked match.

## Matching

Resolution order:

1. Built-in aliases.
2. User aliases.
3. Workspaces.
4. Frecency history for visited directories.
5. SQLite exact-name matches.
6. SQLite Git repo matches.
7. SQLite token matches for multi-word queries.
8. SQLite path-fragment matches.
9. Live directory discovery through `reach-helper`.
10. Deep fallback discovery when the bounded live scan misses.
11. File-name discovery, jumping to the containing directory.

Explicit object commands narrow the same engine by intent. `to file` uses the
file cache and on-demand file-name scan, `to dir` uses directory matching,
`to ws` uses workspace state, package commands inspect project metadata files,
and `to code` searches file contents under configured roots.

Frecency means frequency multiplied by recency. A directory starts with one
visit, each successful jump adds another visit, and recent visits weigh more:
within an hour counts most, within a day counts strongly, and old visits fade.
If no history match reaches `TO_FRECENCY_THRESHOLD`, `to` falls back to the
normal index and live search pipeline.

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

File-name jumps run after exact directory matching:

```zsh
to pyproject.toml
to README.md
to 音乐.mp3
to "cover photo.jpg"
```

Queries with an extension search for that exact file name. Plain names prefer
directories first; if no directory matches, `gt` searches for either that exact
file name or files with the same stem:

```zsh
to README     # directory named README wins; otherwise README or README.*
to 证件照     # directory named 证件照 wins; otherwise 证件照 or 证件照.*
```

If multiple directories contain the same file name, `to` prefers the directory
with the highest frecency score, then the old ranking signals: recent use,
frequent use, shallower paths, and shorter paths. File-name hits are cached on
demand, so repeated jumps can use SQLite before falling back to live filesystem
search.

Plain single-word path-fragment matching is disabled by default. Enable it
only if you want broader results:

```zsh
TO_SEARCH_PATH_FRAGMENTS=1
```

Repository searches have their own indexed path. `to repo <query...>` matches
all query words against repository names and paths, then orders candidates by
frecency, lexical fit, and path depth. `to repo` with no query prints recent
repositories sorted by frecency.

## Configuration

Configuration is loaded from:

```zsh
~/.config/reach/config.zsh
```

Example:

```zsh
TO_ROOTS=(
  "$HOME/src"
  "/Volumes/Work"
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
TO_ROOT_MODE=home
TO_WATCH_DEBOUNCE=2
TO_AUTOWATCH=0
TO_AUTO_ADD_ROOTS=0
TO_FRECENCY=1
TO_FRECENCY_THRESHOLD=1
TO_AI_COMMAND=""
TO_AI_RANK_COMMAND=""
TO_OPEN_COMMAND=""
TO_VSCODE_COMMAND=""
TO_FIG_COMMAND=""
TO_HELPER=""
```

Options:

| Option | Default | Meaning |
| --- | --- | --- |
| `TO_MAX_DEPTH` | `8` | Maximum scan depth per root |
| `TO_INTERACTIVE_THRESHOLD` | `3` | Result count where selection becomes useful |
| `TO_SEARCH_PATH_FRAGMENTS` | `0` | Let plain words match anywhere in paths |
| `TO_FOLLOW_SYMLINKS` | `0` | Search through symlinked directory trees |
| `TO_ROOT_MODE` | `home` | `home` searches `$HOME` plus roots; `explicit` searches only configured roots |
| `TO_WATCH_DEBOUNCE` | `2` | Seconds to wait before watcher reindex |
| `TO_AUTOWATCH` | `0` | Start a background watcher when zsh integration loads |
| `TO_AUTO_ADD_ROOTS` | `0` | Add temporary-search parent roots after successful external jumps |
| `TO_FRECENCY` | `1` | Prefer frequently and recently visited directories before index fallback |
| `TO_FRECENCY_THRESHOLD` | `1` | Minimum history score required before falling back to index/live search |
| `TO_AI_COMMAND` | empty | External command for `to ai <query...>` |
| `TO_AI_RANK_COMMAND` | empty | External command that ranks candidates from stdin |
| `TO_OPEN_COMMAND` | auto | URL opener for `to gh` |
| `TO_VSCODE_COMMAND` | auto | Directory opener for `to vscode` |
| `TO_FIG_COMMAND` | auto | Directory command for `to fig` |
| `TO_HELPER` | auto | Explicit path to `reach-helper` |

Persistent state lives under `~/.config/reach` by default:

```text
roots         configured search roots
index.sqlite3 SQLite dirs, tokens, aliases, workspaces, recent, root metadata
aliases       text fallback for aliases
workspaces    text fallback for workspaces
recent        text fallback for recent jumps
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
from its own SQLite index and falls back to live filesystem search.

Path handling is quoted and tested with spaces and unicode. SQL queries quote
user input before passing it to SQLite.

`TO_AI_COMMAND`, `TO_AI_RANK_COMMAND`, `TO_OPEN_COMMAND`,
`TO_VSCODE_COMMAND`, and `TO_FIG_COMMAND` are explicit escape hatches for users
who want custom ranking or integrations. They are not sandboxed; configure
them only with commands you would be comfortable running directly in your
shell.

## Performance

`to` does not run a background daemon by default. Idle cost is effectively
zero unless you opt in to watching.

Normal jumps are history-first, then index-first:

```text
query -> frecency history -> validate path -> cd
      -> SQLite index -> validate path -> cd
      -> bounded helper scan under configured roots
      -> deep helper scan if the bounded scan misses
      -> cache result in SQLite and history
```

`TO_MAX_DEPTH` controls layer-2 traversal only: lower values make the common
fallback faster but may miss deeply nested paths. Layer 3 is deliberately not
limited by `TO_MAX_DEPTH`; it keeps symlink-loop protection and a hard internal
depth safety cap, and prints a short notice before doing the slower scan.

Fallback search starts inside the configured roots. In home-first mode, a new
directory anywhere under `$HOME` is discoverable immediately:

```zsh
mkdir -p "$HOME/somewhere/new-service"
to new-service
```

That first jump writes the directory back to the index, so later queries can
resolve from history or SQLite without a live scan.

File-name jumps use the same roots and exclusions. `to` does not eagerly index
every file during startup or reindex; it looks up cached file hits first, then
scans file names on demand and records successful hits in SQLite. This keeps
the database small and avoids turning `to` into a full content indexer.

### Ignore Rules

`reach-helper` has built-in ignores for large generated directories such as
`.git/`, `node_modules/`, `target/`, virtualenvs, `__pycache__/`, `dist/`, and
`build/`. Add your own patterns to:

```zsh
$HOME/.reachignore
```

The format is the same as `.gitignore`. Project `.gitignore` files are also
read by default and stack with `.reachignore`; set `TO_USE_GITIGNORE=0` to use
only the built-in and reach-specific rules. Set `TO_REACHIGNORE=/path/to/file`
to use a different ignore file.

SQLite remains the default store. The Rust store layer is abstracted so a
future release can evaluate a KV backend, but any such change will re-check the
maintenance status of candidates at that time.

The SQLite index stores:

```sql
dirs(id, path, name, parent, depth, is_git, last_seen, last_used, hit_count)
dirs also records repo and repo_name for Git repository navigation
tokens(token, dir_id)
files(path, name, stem, parent, depth, last_seen)
history(path, visits, last_used)
stats(key, value)
roots(path, mtime, config_key, last_indexed)
aliases(name, path)
workspaces(name, path)
recent(path, last_used)
```

Successful jumps update directory history with one lightweight row write, plus
the existing `hit_count` and `last_used` index data. Results are ordered
roughly as:

```text
exact name > frecency > recent/frequent > shallower depth > shorter path
```

Set `TO_FRECENCY=0` if you want the older pure index/live-search behavior.
`TO_FRECENCY_THRESHOLD` controls when weak old history is ignored and the
normal fallback search is used instead.

`to --reindex` is incremental for SQLite. It records root mtime and
index-affecting config, skips unchanged roots, refreshes changed roots, adds
new directories, and prunes stale directories under refreshed roots.

Broader modes cost more:

- `to src/components` searches a path fragment.
- `to -i backend` collects all matches for selection.
- `TO_SEARCH_PATH_FRAGMENTS=1` lets single words match anywhere in a path.
- `to --watch` runs a foreground watcher and reindexes after filesystem events.

### Watching for changes

Run a watcher when you want the index kept warm automatically:

```zsh
to --watch
```

The watcher monitors configured roots, waits `TO_WATCH_DEBOUNCE` seconds after
an event, then runs incremental `to --reindex`. That adds new directories under
changed roots and prunes stale indexed directories. It is implemented inside
`reach-helper` with the Rust `notify` crate, which uses the native platform
watcher where available.

To start the watcher automatically when `eval "$(to init zsh)"` loads the zsh
integration, set:

```zsh
TO_AUTOWATCH=1
```

`TO_AUTOWATCH` starts only when `reach-helper` is available.

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

`to --doctor` is grouped into Search, Discovery, Performance, and Statistics.
It shows whether SQLite and frecency are active, how many roots are configured,
index/cache sizes, time since the last reindex, the most used root, cache hit
rate, and the outcome of the last search. Use `to --doctor --verbose` to show
low-level tool paths, helper detection, and optional AI hooks.

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
to -r /path/to/root backend
```

Avoid broad system roots. Prefer the narrowest directory that contains the
places you actually jump to:

```zsh
to use /path/to/root
```

If `to` finds too many matches, keep broad path search disabled:

```zsh
TO_SEARCH_PATH_FRAGMENTS=0
```

If `to` does not find a repository, check whether its parent directory is in
your roots:

```zsh
to roots
to use /path/that/contains/repos
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
