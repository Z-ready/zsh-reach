use crate::CliError;
use ignore::gitignore::{Gitignore, GitignoreBuilder};
use std::path::{Path, PathBuf};

pub const DEFAULT_IGNORES: &[&str] = &[
    ".git/",
    "node_modules/",
    "target/",
    "venv/",
    ".venv/",
    "__pycache__/",
    "dist/",
    "build/",
    ".cache/",
    "Library/",
    "Trash/",
];

pub struct IgnoreRules {
    matcher: Gitignore,
}

impl IgnoreRules {
    pub fn new(
        root: &Path,
        reachignore: Option<&Path>,
        use_gitignore: bool,
    ) -> Result<Self, CliError> {
        let mut builder = GitignoreBuilder::new(root);
        for pattern in DEFAULT_IGNORES {
            builder
                .add_line(None, pattern)
                .map_err(|error| CliError::Ignore(error.to_string()))?;
        }
        if let Some(path) = reachignore {
            if path.is_file() {
                builder.add(path);
            }
        }
        if use_gitignore {
            add_gitignores(root, &mut builder)?;
        }
        let matcher = builder
            .build()
            .map_err(|error| CliError::Ignore(error.to_string()))?;
        Ok(Self { matcher })
    }

    pub fn is_ignored(&self, path: &Path, is_dir: bool) -> bool {
        self.matcher
            .matched_path_or_any_parents(path, is_dir)
            .is_ignore()
    }
}

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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ignores_reachignore_and_gitignore_when_both_match() {
        let root = std::env::temp_dir().join(format!("reach-ignore-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(root.join("ignored-by-git")).expect("create git dir");
        std::fs::create_dir_all(root.join("ignored-by-reach")).expect("create reach dir");
        std::fs::write(root.join(".gitignore"), "ignored-by-git/\n").expect("write gitignore");
        let reachignore = root.join(".reachignore");
        std::fs::write(&reachignore, "ignored-by-reach/\n").expect("write reachignore");

        let rules = IgnoreRules::new(&root, Some(&reachignore), true).expect("rules");

        assert!(rules.is_ignored(&root.join("ignored-by-git"), true));
        assert!(rules.is_ignored(&root.join("ignored-by-reach"), true));
        let _ = std::fs::remove_dir_all(root);
    }
}
