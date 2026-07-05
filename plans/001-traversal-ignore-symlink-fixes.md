# Plan 001: Reuse Ignore Rules During Traversal and Skip File Symlinks

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report; do not improvise. When done, update the status row for this plan in `plans/README.md` unless a reviewer dispatched you and told you they maintain the index.
>
> **Drift check (run first)**: `git diff --stat 49c7fc1..HEAD -- src/traverse.rs src/ignore_rules.rs`
> If either in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding. On a meaningful mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: correctness / performance
- **Planned at**: commit `49c7fc1`, 2026-07-05

## Why this matters

Live traversal currently rebuilds the complete ignore matcher on every recursive directory visit. Because `IgnoreRules::new` recursively discovers `.gitignore` files below the directory it is given, a tree with many nested directories can repeatedly rescan overlapping subtrees and turn a normal search into O(n^2) filesystem work. The same traversal also treats every symlink as a directory when `--follow-links` is enabled, so a symlink to a regular file can make a scan fail while trying to `read_dir` that file.

This plan fixes both issues at the traversal boundary: build ignore rules once per root, pass the matcher through recursion, and recurse through symlinks only when they resolve to directories.

## Current state

Relevant files:

- `src/traverse.rs` - live search traversal, serial indexing walk, cancellation, depth limits, and symlink loop guard.
- `src/ignore_rules.rs` - default ignores plus `.reachignore` and `.gitignore` matcher construction.

Current live traversal rebuilds ignore rules inside every recursive call:

```rust
// src/traverse.rs:109
fn visit_dir(
    dir: &Path,
    depth: usize,
    config: &TraverseConfig,
    max_depth: Option<usize>,
    state: &VisitState,
) -> Result<(), CliError> {
    // ...
    let rules = IgnoreRules::new(dir, config.reachignore.as_deref(), config.use_gitignore)?;
    let mut entries = std::fs::read_dir(dir)?.collect::<Result<Vec<_>, std::io::Error>>()?;
```

Current symlink recursion does not distinguish symlink targets:

```rust
// src/traverse.rs:141
let path = entry.path();
let file_type = entry.file_type()?;
let is_dir = file_type.is_dir();
// ...
if is_dir || (config.follow_links && file_type.is_symlink()) {
    visit_dir(&path, depth + 1, config, max_depth, state)?;
}
```

Current ignore construction recursively scans all descendants under its `root` argument:

```rust
// src/ignore_rules.rs:56
fn add_gitignores(root: &Path, builder: &mut GitignoreBuilder) -> Result<(), CliError> {
    let mut stack = vec![PathBuf::from(root)];
    while let Some(dir) = stack.pop() {
        let gitignore = dir.join(".gitignore");
        if gitignore.is_file() {
            builder.add(&gitignore);
        }
        for entry in std::fs::read_dir(&dir)? {
            let entry = entry?;
            let path = entry.path();
            if path.is_dir() {
                stack.push(path);
            }
        }
    }
    Ok(())
}
```

Existing test conventions:

- Rust unit tests live in `#[cfg(test)] mod tests` blocks in the same module as the code under test.
- `src/traverse.rs` already uses `temp_root(name)` for filesystem traversal tests.
- `src/traverse.rs` already has symlink coverage in `symlink_loop_does_not_hang_when_following_links`.
- `src/ignore_rules.rs` has direct matcher coverage in `ignores_reachignore_and_gitignore_when_both_match`.

Architecture constraints:

- `docs/ARCHITECTURE.md` defines `src/traverse.rs` as "ignored-aware traversal, cancellation, and symlink guards" and `src/ignore_rules.rs` as "built-in ignores plus `.reachignore` and `.gitignore`".
- `README.md` says project `.gitignore` files are read by default and stack with `.reachignore`; preserve that behavior.

## Commands you will need

| Purpose | Command | Expected on success |
| --- | --- | --- |
| Drift check | `git diff --stat 49c7fc1..HEAD -- src/traverse.rs src/ignore_rules.rs` | no output, or only changes you have reviewed against this plan |
| Focused traversal tests | `cargo test traverse::tests:: --quiet` | exit 0; all traversal tests pass |
| Focused ignore tests | `cargo test ignore_rules::tests:: --quiet` | exit 0; all ignore rule tests pass |
| Rust formatting | `cargo fmt -- --check` | exit 0 |
| Rust lint | `cargo clippy --all-targets -- -D warnings` | exit 0; no warnings |
| Full repo gate | `zsh scripts/check.zsh` | exit 0 |

## Scope

**In scope** - the only source files you may modify:

- `src/traverse.rs`
- `src/ignore_rules.rs`

**Out of scope** - do not touch, even if related:

- `src/main.rs` CLI parsing for `scan` or `index-root`
- `to.plugin.zsh` helper invocation, zsh fallback traversal, or config handling
- `src/store.rs`, SQLite schema, pruning, ranking, or frecency behavior
- `docs/`, `README.md`, formula files, CI files, or release metadata
- Cosmetic refactors, renames unrelated to the traversal fix, comment-only cleanup, or formatting churn outside the in-scope files

## Git workflow

- Suggested branch: `advisor/001-traversal-ignore-symlink-fixes`
- Commit style in this repo is short imperative or descriptive subject lines, for example `Add confidence-aware jump diagnostics`.
- Make one logical commit for this plan after all validations pass.
- Do not push or open a PR unless the operator explicitly asks.

## Steps

### Step 1: Add failing regression tests

Edit `src/traverse.rs` only.

Add a test that proves live traversal still honors nested `.gitignore` rules when the matcher is built once per root. Use the existing `temp_root` helper. The setup should create:

- `root/project/.gitignore` containing `ignored-dir/`
- `root/project/ignored-dir/target-dir`
- `root/project/kept-dir`

Run `search` with:

- `roots: vec![root.clone()]`
- `query_terms: vec!["target-dir".to_owned()]`
- `kind: TargetKind::Directory`
- `mode: MatchMode::Exact`
- `use_gitignore: true`
- `follow_links: false`
- `deep_fallback: false`

Assert that no match ends with `target-dir`. In the same test, or a second small test, search for `kept-dir` and assert it is found. This locks the existing README promise that project `.gitignore` stacks with other ignore rules.

Add a Unix-only regression test for file symlinks:

```rust
#[cfg(unix)]
#[test]
fn following_links_skips_symlinks_to_files() {
    // ...
}
```

The setup should create `root/real-target`, create a regular file `root/file-target.txt`, then create a symlink `root/link-to-file` pointing to that file. Run `search` with `follow_links: true`, `kind: TargetKind::Directory`, `query_terms: vec!["real-target".to_owned()]`, and assert the search succeeds and finds `real-target`. This should fail on the current implementation because traversal tries to recurse into `link-to-file`.

Keep the tests deterministic and clean up the temp root at the end, matching the existing tests.

**Verify**: `cargo test traverse::tests:: --quiet` -> the new file-symlink test fails before the implementation change; after Step 3 it must pass. If it passes before any code change, STOP and report because the current finding may already have been fixed.

### Step 2: Build ignore rules once per root for live traversal

Edit `src/traverse.rs` and, only if needed for a clean API, `src/ignore_rules.rs`.

Change live traversal so `IgnoreRules::new(root, config.reachignore.as_deref(), config.use_gitignore)` is called once for each configured root in `search_layer`, not inside `visit_dir`.

Expected shape:

- `visit_dir` takes an additional `rules: &IgnoreRules` parameter.
- `search_layer` constructs rules for each `root` before calling `visit_dir(root, 0, config, max_depth, &state, &rules)`.
- Recursive calls pass the same `rules` reference down.
- `serial_walk_for_index` may keep its existing one-time matcher construction; do not rewrite it unless the compiler forces a signature adjustment.

Preserve existing traversal behavior:

- Keep `HARD_DEPTH_LIMIT`, `max_depth`, cancellation, match sorting, and deduping unchanged.
- Keep `.reachignore`, `.gitignore`, and built-in ignore semantics unchanged.
- Keep the existing parallel root traversal approach. If per-root rule construction errors, handle errors consistently with the current root traversal error policy; do not redesign error aggregation in this plan.

**Verify**: `rg -n "IgnoreRules::new" src/traverse.rs` -> one occurrence in `search_layer` for live traversal and one existing occurrence in `serial_walk_for_index`; no occurrence inside `visit_dir`.

**Verify**: `cargo test traverse::tests:: --quiet` -> exit 0.

### Step 3: Recurse only into real directories or directory symlinks

Edit `src/traverse.rs`.

Replace the current `if is_dir || (config.follow_links && file_type.is_symlink())` recursion condition with logic that:

- Always recurses into ordinary directories.
- When `config.follow_links` is true and `file_type.is_symlink()` is true, follows the symlink only if it resolves to a directory.
- Does not return an error for symlinks to regular files.
- Preserves the existing canonical-path loop guard inside `visit_dir` for directories that are actually visited.

One acceptable implementation shape is a small helper in `src/traverse.rs`, for example:

```rust
fn should_recurse(path: &Path, file_type: std::fs::FileType, follow_links: bool) -> Result<bool, CliError> {
    if file_type.is_dir() {
        return Ok(true);
    }
    if follow_links && file_type.is_symlink() {
        return Ok(std::fs::metadata(path).map(|metadata| metadata.is_dir()).unwrap_or(false));
    }
    Ok(false)
}
```

If you add a helper, keep it private to `src/traverse.rs`. Do not add a new module. Do not introduce broad error handling changes; the key requirement is that a symlink to a file does not abort traversal.

**Verify**: `cargo test traverse::tests::following_links_skips_symlinks_to_files --quiet` -> exit 0 on Unix. On non-Unix platforms, the test is cfg-gated and this command may report no matching test; then run `cargo test traverse::tests:: --quiet` instead.

**Verify**: `cargo test traverse::tests::symlink_loop_does_not_hang_when_following_links --quiet` -> exit 0.

### Step 4: Keep ignore-rule construction scoped and readable

Review `src/ignore_rules.rs` after the traversal change.

Do not rewrite `add_gitignores` unless needed for correctness after Step 2. If you do touch it, keep the same public behavior:

- Built-in defaults are added first.
- Optional `.reachignore` is added when the configured path is a file.
- Project `.gitignore` files are included when `use_gitignore` is true.

Avoid cosmetic refactors. This plan is not asking for a new ignore engine, a watcher integration change, or a migration away from the `ignore` crate.

**Verify**: `cargo test ignore_rules::tests:: --quiet` -> exit 0.

## Test plan

Add Rust unit tests in `src/traverse.rs`:

- A nested `.gitignore` live traversal regression test that confirms ignored nested directories are skipped and a non-ignored sibling remains findable.
- A Unix-only symlink-to-file regression test that confirms `follow_links: true` does not abort when the tree contains a symlink to a regular file.

Existing tests to preserve:

- `src/traverse.rs::tests::symlink_loop_does_not_hang_when_following_links`
- `src/traverse.rs::tests::serial_index_walk_stacks_reachignore_and_gitignore`
- `src/ignore_rules.rs::tests::ignores_reachignore_and_gitignore_when_both_match`

Final verification:

- `cargo test traverse::tests:: --quiet` -> exit 0.
- `cargo test ignore_rules::tests:: --quiet` -> exit 0.
- `zsh scripts/check.zsh` -> exit 0.

## Done criteria

All must hold:

- [ ] `IgnoreRules::new` is no longer called from inside recursive `visit_dir`.
- [ ] Live traversal constructs ignore rules once per configured root.
- [ ] Live traversal still honors nested `.gitignore` files.
- [ ] `TO_FOLLOW_SYMLINKS=1` equivalent Rust config does not abort when a directory contains a symlink to a regular file.
- [ ] Existing symlink loop protection still passes.
- [ ] No files outside `src/traverse.rs`, `src/ignore_rules.rs`, and `plans/README.md` are modified.
- [ ] `cargo fmt -- --check` exits 0.
- [ ] `cargo clippy --all-targets -- -D warnings` exits 0.
- [ ] `zsh scripts/check.zsh` exits 0.
- [ ] `plans/README.md` status row for Plan 001 is updated.

## STOP conditions

Stop and report back without continuing if:

- The code at the "Current state" excerpts no longer matches the live code in a way that changes this plan.
- Fixing the issue appears to require changing `src/main.rs`, `to.plugin.zsh`, public CLI flags, database schema, or ranking behavior.
- The new nested `.gitignore` test cannot be made to pass while building rules once per root.
- Symlink-to-directory traversal or the existing symlink loop guard regresses.
- Any verification command fails twice after a focused fix attempt.
- `git status --short` shows unexpected pre-existing edits in `src/traverse.rs` or `src/ignore_rules.rs` that you cannot separate from this work.

## Maintenance notes

Reviewers should focus on traversal semantics, not style churn. The important invariant after this change is that the ignore matcher's root remains the configured search root, while recursive directory visits only consume that matcher.

Future changes to `.gitignore` discovery, watcher indexing, or `serial_walk_for_index` should keep live traversal and index traversal aligned: both should honor built-in ignores, `.reachignore`, and project `.gitignore` rules in the same way.
