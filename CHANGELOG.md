# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses semantic versioning.

## [1.6.0] - 2026-07-04

### Added

- Added the `reach` package surface and `gt` as the default user command.
- Added the Rust `reach-helper` backend for SQLite storage, live traversal,
  ignored-aware indexing, and native filesystem watching.
- Added three-layer lookup: frecency/index first, bounded traversal second, and
  deep traversal fallback when needed.
- Added `.reachignore` support stacked with project `.gitignore` files.
- Added CI coverage for macOS and Linux, Homebrew formula checks, and zsh tests.

### Changed

- Moved the hot SQLite path to bundled `rusqlite`, enabling WAL mode and
  `busy_timeout` without requiring the `sqlite3` CLI.
- Removed hard runtime dependencies on `fd`, `fswatch`, `inotifywait`, and the
  `sqlite3` CLI from helper-backed installs.
- Updated Homebrew packaging to install `reach`, `reach-helper`, and `_gt`.
- Updated documentation and examples to use `gt`.

### Fixed

- Fixed timestamp failure handling so failed time reads do not write epoch `0`
  into frecency history.
- Fixed concurrent SQLite writes by enabling WAL and busy timeout at connection
  initialization.
- Added traversal cancellation and symlink loop protection regressions.
- Added hook timeout protection for user-configured AI, ranking, opener, VS
  Code, and fig commands.
- Added special-character path coverage for single quotes and backslashes.

### Deprecated

- The legacy `to` command remains available as a compatibility function in the
  `1.x` line. New scripts should use `gt`; `to` is planned for removal in
  `v2.0.0`.
