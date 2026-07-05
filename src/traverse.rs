use crate::ignore_rules::IgnoreRules;
use crate::CliError;
use rayon::prelude::*;
use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use walkdir::WalkDir;

const HARD_DEPTH_LIMIT: usize = 64;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TargetKind {
    Directory,
    File,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MatchMode {
    Exact,
    Path,
    Broad,
}

#[derive(Debug, Clone)]
pub struct TraverseConfig {
    pub roots: Vec<PathBuf>,
    pub query_terms: Vec<String>,
    pub kind: TargetKind,
    pub mode: MatchMode,
    pub max_depth: Option<usize>,
    pub follow_links: bool,
    pub reachignore: Option<PathBuf>,
    pub use_gitignore: bool,
    pub deep_fallback: bool,
    pub deep_prompt: bool,
}

#[derive(Debug)]
pub struct TraverseOutcome {
    pub matches: Vec<PathBuf>,
    pub layer: u8,
    pub visited: usize,
}

pub fn search(config: &TraverseConfig) -> Result<TraverseOutcome, CliError> {
    let shallow = search_layer(config, config.max_depth, 2)?;
    if !shallow.matches.is_empty() || !config.deep_fallback {
        return Ok(shallow);
    }
    if config.deep_prompt {
        eprintln!("reach: running deep scan; this may take longer");
    }
    // max_depth only limits layer 2. Layer 3 deliberately removes that limit,
    // while the hard safety cap and symlink loop guard remain active.
    search_layer(config, None, 3)
}

fn search_layer(
    config: &TraverseConfig,
    max_depth: Option<usize>,
    layer: u8,
) -> Result<TraverseOutcome, CliError> {
    let state = Arc::new(VisitState {
        cancel: AtomicBool::new(false),
        matches: Mutex::new(Vec::new()),
        visited_links: Mutex::new(HashSet::new()),
        visited_count: AtomicUsize::new(0),
    });
    let result = rayon::ThreadPoolBuilder::new().build();
    if let Ok(pool) = result {
        pool.install(|| {
            config.roots.par_iter().for_each(|root| {
                let rules = match IgnoreRules::new(
                    root,
                    config.reachignore.as_deref(),
                    config.use_gitignore,
                ) {
                    Ok(r) => r,
                    Err(_) => return,
                };
                let _ = visit_dir(root, 0, config, max_depth, &state, &rules);
            });
        });
    } else {
        for root in &config.roots {
            let rules =
                IgnoreRules::new(root, config.reachignore.as_deref(), config.use_gitignore)?;
            visit_dir(root, 0, config, max_depth, &state, &rules)?;
        }
    }
    let mut out = state
        .matches
        .lock()
        .map_err(|_| CliError::Io("traverse result lock poisoned".to_owned()))?
        .clone();
    out.sort_by(|left, right| {
        left.components()
            .count()
            .cmp(&right.components().count())
            .then_with(|| left.as_os_str().len().cmp(&right.as_os_str().len()))
            .then_with(|| left.cmp(right))
    });
    out.dedup();
    Ok(TraverseOutcome {
        matches: out,
        layer,
        visited: state.visited_count.load(Ordering::Relaxed),
    })
}

struct VisitState {
    cancel: AtomicBool,
    matches: Mutex<Vec<PathBuf>>,
    visited_links: Mutex<HashSet<PathBuf>>,
    visited_count: AtomicUsize,
}

fn visit_dir(
    dir: &Path,
    depth: usize,
    config: &TraverseConfig,
    max_depth: Option<usize>,
    state: &VisitState,
    rules: &IgnoreRules,
) -> Result<(), CliError> {
    if state.cancel.load(Ordering::Relaxed)
        || depth > HARD_DEPTH_LIMIT
        || max_depth.is_some_and(|limit| depth > limit)
    {
        return Ok(());
    }
    if config.follow_links {
        let canonical = std::fs::canonicalize(dir)?;
        let mut seen = state
            .visited_links
            .lock()
            .map_err(|_| CliError::Io("symlink guard lock poisoned".to_owned()))?;
        if !seen.insert(canonical) {
            return Ok(());
        }
    }
    let mut entries = std::fs::read_dir(dir)?.collect::<Result<Vec<_>, std::io::Error>>()?;
    entries.sort_by_key(|entry| entry.path());
    for entry in entries {
        if state.cancel.load(Ordering::Relaxed) {
            // Already-running tasks are not forcefully interrupted; workers simply
            // stop dispatching deeper work once a high-confidence match is found.
            break;
        }
        let path = entry.path();
        let file_type = entry.file_type()?;
        let is_dir = file_type.is_dir();
        if rules.is_ignored(&path, is_dir) {
            continue;
        }
        state.visited_count.fetch_add(1, Ordering::Relaxed);
        if path_matches(
            &path,
            config.kind,
            config.mode,
            &config.query_terms,
            is_dir,
            file_type.is_file(),
        ) {
            let mut out = state
                .matches
                .lock()
                .map_err(|_| CliError::Io("traverse result lock poisoned".to_owned()))?;
            out.push(path.clone());
            if matches!(config.kind, TargetKind::Directory)
                && (high_confidence_match(&path, &config.query_terms)
                    || shallow_match(depth, max_depth))
            {
                state.cancel.store(true, Ordering::Relaxed);
            }
        }
        if should_recurse(&path, file_type, config.follow_links)? {
            visit_dir(&path, depth + 1, config, max_depth, state, rules)?;
        }
    }
    Ok(())
}

fn should_recurse(
    path: &Path,
    file_type: std::fs::FileType,
    follow_links: bool,
) -> Result<bool, CliError> {
    if file_type.is_dir() {
        return Ok(true);
    }
    if follow_links && file_type.is_symlink() {
        return Ok(std::fs::metadata(path)
            .map(|metadata| metadata.is_dir())
            .unwrap_or(false));
    }
    Ok(false)
}

pub fn serial_walk_for_index(
    root: &Path,
    max_depth: Option<usize>,
    follow_links: bool,
    reachignore: Option<&Path>,
    use_gitignore: bool,
) -> Result<Vec<PathBuf>, CliError> {
    let depth = max_depth.unwrap_or(HARD_DEPTH_LIMIT).min(HARD_DEPTH_LIMIT);
    let rules = IgnoreRules::new(root, reachignore, use_gitignore)?;
    Ok(WalkDir::new(root)
        .follow_links(follow_links)
        .max_depth(depth + 1)
        .into_iter()
        .filter_map(Result::ok)
        .filter(|entry| entry.file_type().is_dir())
        .filter(|entry| !rules.is_ignored(entry.path(), true))
        .map(|entry| entry.into_path())
        .collect())
}

fn path_matches(
    path: &Path,
    kind: TargetKind,
    mode: MatchMode,
    terms: &[String],
    is_dir: bool,
    is_file: bool,
) -> bool {
    if terms.is_empty() {
        return false;
    }
    if matches!(kind, TargetKind::Directory) && !is_dir {
        return false;
    }
    if matches!(kind, TargetKind::File) && !is_file {
        return false;
    }
    let haystack = path.to_string_lossy().to_lowercase();
    let name = path
        .file_name()
        .map(|value| value.to_string_lossy().to_lowercase())
        .unwrap_or_default();
    match mode {
        MatchMode::Exact => terms.len() == 1 && name_matches(&name, &terms[0], kind),
        MatchMode::Path => {
            terms.len() == 1 && terms[0].contains('/') && haystack.contains(&terms[0])
        }
        MatchMode::Broad => terms.iter().all(|term| haystack.contains(term)),
    }
}

fn name_matches(name: &str, query: &str, kind: TargetKind) -> bool {
    if matches!(kind, TargetKind::File) && !query.contains('.') && !query.starts_with('.') {
        name == query || name.starts_with(&format!("{query}."))
    } else {
        name == query
    }
}

fn high_confidence_match(path: &Path, terms: &[String]) -> bool {
    terms.len() == 1
        && path
            .file_name()
            .map(|name| name.to_string_lossy().eq_ignore_ascii_case(&terms[0]))
            .unwrap_or(false)
}

fn shallow_match(depth: usize, max_depth: Option<usize>) -> bool {
    max_depth.is_some_and(|limit| depth < limit.saturating_div(2).max(1))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cancels_before_visiting_deep_siblings_when_exact_match_is_shallow() {
        let root = temp_root("reach-cancel");
        std::fs::create_dir_all(root.join("000-target-dir")).expect("target");
        let mut total_nodes = 1usize;
        for index in 0..2_000 {
            std::fs::create_dir_all(root.join(format!("zzz-deep-{index}/a/b/c/d/e")))
                .expect("deep");
            total_nodes += 6;
        }
        let config = TraverseConfig {
            roots: vec![root.clone()],
            query_terms: vec!["000-target-dir".to_owned()],
            kind: TargetKind::Directory,
            mode: MatchMode::Exact,
            max_depth: Some(8),
            follow_links: false,
            reachignore: None,
            use_gitignore: false,
            deep_fallback: false,
            deep_prompt: false,
        };

        let outcome = search(&config).expect("search");

        assert!(!outcome.matches.is_empty());
        assert!(
            outcome.visited < total_nodes / 10,
            "visited {} of {} nodes",
            outcome.visited,
            total_nodes
        );
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn symlink_loop_does_not_hang_when_following_links() {
        let root = temp_root("reach-loop");
        std::fs::create_dir_all(root.join("a/wanted-dir")).expect("dirs");
        std::fs::create_dir_all(root.join("b")).expect("b");
        #[cfg(unix)]
        {
            std::os::unix::fs::symlink("../b", root.join("a/link-to-b")).expect("symlink b");
            std::os::unix::fs::symlink("../a", root.join("b/link-to-a")).expect("symlink a");
        }
        let config = TraverseConfig {
            roots: vec![root.clone()],
            query_terms: vec!["wanted-dir".to_owned()],
            kind: TargetKind::Directory,
            mode: MatchMode::Exact,
            max_depth: None,
            follow_links: true,
            reachignore: None,
            use_gitignore: false,
            deep_fallback: false,
            deep_prompt: false,
        };

        let (tx, rx) = std::sync::mpsc::channel();
        std::thread::spawn(move || {
            let result = search(&config);
            let _ = tx.send(result);
        });
        let outcome = rx
            .recv_timeout(std::time::Duration::from_secs(2))
            .expect("symlink loop traversal should finish before timeout")
            .expect("search");

        assert_eq!(outcome.layer, 2);
        assert!(outcome
            .matches
            .iter()
            .any(|path| path.ends_with("wanted-dir")));
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn serial_index_walk_stacks_reachignore_and_gitignore() {
        let root = temp_root("reach-ignore-stack");
        std::fs::create_dir_all(root.join("ignored-by-git")).expect("git ignored");
        std::fs::create_dir_all(root.join("ignored-by-reach")).expect("reach ignored");
        std::fs::create_dir_all(root.join("kept-by-both")).expect("kept");
        std::fs::write(root.join(".gitignore"), "ignored-by-git/\n").expect("gitignore");
        let reachignore = root.join(".reachignore");
        std::fs::write(&reachignore, "ignored-by-reach/\n").expect("reachignore");

        let walked =
            serial_walk_for_index(&root, Some(4), false, Some(&reachignore), true).expect("walk");

        assert!(!walked.iter().any(|path| path.ends_with("ignored-by-git")));
        assert!(!walked.iter().any(|path| path.ends_with("ignored-by-reach")));
        assert!(walked.iter().any(|path| path.ends_with("kept-by-both")));
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn nested_gitignore_is_honored_during_live_traversal() {
        let root = temp_root("reach-nested-ignore");
        std::fs::create_dir_all(root.join("project/ignored-dir/target-dir")).expect("target");
        std::fs::create_dir_all(root.join("project/kept-dir")).expect("kept");
        std::fs::write(root.join("project/.gitignore"), "ignored-dir/\n").expect("gitignore");

        let config = TraverseConfig {
            roots: vec![root.clone()],
            query_terms: vec!["target-dir".to_owned()],
            kind: TargetKind::Directory,
            mode: MatchMode::Exact,
            max_depth: None,
            follow_links: false,
            reachignore: None,
            use_gitignore: true,
            deep_fallback: false,
            deep_prompt: false,
        };

        let outcome = search(&config).expect("search");

        assert!(
            !outcome.matches.iter().any(|p| p.ends_with("target-dir")),
            "ignored-dir should not be visited"
        );

        let config_kept = TraverseConfig {
            roots: vec![root.clone()],
            query_terms: vec!["kept-dir".to_owned()],
            kind: TargetKind::Directory,
            mode: MatchMode::Exact,
            max_depth: None,
            follow_links: false,
            reachignore: None,
            use_gitignore: true,
            deep_fallback: false,
            deep_prompt: false,
        };

        let outcome_kept = search(&config_kept).expect("search kept");
        assert!(
            outcome_kept.matches.iter().any(|p| p.ends_with("kept-dir")),
            "kept-dir should be found"
        );

        let _ = std::fs::remove_dir_all(root);
    }

    #[cfg(unix)]
    #[test]
    fn following_links_skips_symlinks_to_files() {
        let root = temp_root("reach-symlink-file");
        std::fs::create_dir_all(root.join("real-target")).expect("target dir");
        std::fs::write(root.join("file-target.txt"), "hello").expect("file");
        std::os::unix::fs::symlink("file-target.txt", root.join("link-to-file"))
            .expect("symlink to file");

        let config = TraverseConfig {
            roots: vec![root.clone()],
            query_terms: vec!["real-target".to_owned()],
            kind: TargetKind::Directory,
            mode: MatchMode::Exact,
            max_depth: None,
            follow_links: true,
            reachignore: None,
            use_gitignore: false,
            deep_fallback: false,
            deep_prompt: false,
        };

        let outcome = search(&config).expect("search should not abort on file symlink");
        assert!(
            outcome.matches.iter().any(|p| p.ends_with("real-target")),
            "real-target should be found"
        );

        let _ = std::fs::remove_dir_all(root);
    }

    fn temp_root(name: &str) -> PathBuf {
        let root = std::env::temp_dir().join(format!("{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).expect("root");
        root
    }
}
