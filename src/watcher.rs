use crate::CliError;
use notify::{Config, RecommendedWatcher, RecursiveMode, Watcher};
use std::path::PathBuf;
use std::sync::mpsc::channel;
use std::time::Duration;

pub fn watch_once(roots: &[PathBuf], timeout: Duration) -> Result<(), CliError> {
    let (tx, rx) = channel();
    let mut watcher = RecommendedWatcher::new(tx, Config::default())
        .map_err(|error| CliError::Watch(error.to_string()))?;
    for root in roots {
        watcher
            .watch(root, RecursiveMode::Recursive)
            .map_err(|error| CliError::Watch(error.to_string()))?;
    }
    rx.recv_timeout(timeout)
        .map_err(|error| CliError::Watch(error.to_string()))?
        .map_err(|error| CliError::Watch(error.to_string()))?;
    Ok(())
}
