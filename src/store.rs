use crate::{dir_depth, dir_tokens, file_stem, CliError};
use rusqlite::{params, params_from_iter, Connection, OptionalExtension, ToSql};
use std::path::Path;

pub const SCHEMA_SQL: &str = "
pragma journal_mode = WAL;
pragma busy_timeout = 5000;
pragma synchronous = NORMAL;
create table if not exists dirs(
  id integer primary key,
  path text unique not null,
  name text not null,
  lower_name text not null,
  parent text not null default '',
  depth integer not null default 0,
  is_git integer not null default 0,
  repo integer not null default 0,
  repo_name text not null default '',
  last_seen integer not null default 0,
  last_used integer not null default 0,
  hit_count integer not null default 0
);
create table if not exists tokens(token text not null, dir_id integer not null, primary key(token, dir_id));
create table if not exists roots(path text primary key, mtime integer not null default 0, config_key text not null default '', last_indexed integer not null default 0);
create table if not exists aliases(name text primary key, path text not null);
create table if not exists workspaces(name text primary key, path text not null);
create table if not exists recent(path text primary key, last_used integer not null);
create table if not exists history(path text primary key, visits integer not null default 0, last_used integer not null default 0);
create table if not exists files(
  path text primary key,
  name text not null,
  lower_name text not null,
  stem text not null,
  lower_stem text not null,
  parent text not null,
  depth integer not null default 0,
  last_seen integer not null default 0
);
create table if not exists stats(key text primary key, value text not null default '');
create index if not exists idx_dirs_lower_name on dirs(lower_name);
create index if not exists idx_dirs_repo on dirs(repo);
create index if not exists idx_dirs_depth on dirs(depth);
create index if not exists idx_dirs_last_used on dirs(last_used);
create index if not exists idx_tokens_token on tokens(token);
create index if not exists idx_tokens_dir_id on tokens(dir_id);
create index if not exists idx_roots_last_indexed on roots(last_indexed);
create index if not exists idx_recent_last_used on recent(last_used);
create index if not exists idx_files_lower_name on files(lower_name);
create index if not exists idx_files_lower_stem on files(lower_stem);
create index if not exists idx_history_last_used on history(last_used);
";

#[derive(Debug, Clone)]
pub struct IndexEntry {
    pub path: String,
}

pub trait IndexStore {
    fn upsert_entry(&mut self, entry: &IndexEntry, timestamp: i64) -> Result<(), CliError>;
    fn query_by_name(&self, name: &str, limit: usize) -> Result<Vec<IndexEntry>, CliError>;
    fn query_by_frecency(&self, limit: usize) -> Result<Vec<IndexEntry>, CliError>;
    fn record_visit(&self, path: &Path, timestamp: i64) -> Result<(), CliError>;
}

pub struct SqliteStore {
    conn: Connection,
}

impl SqliteStore {
    pub fn open(path: &str) -> Result<Self, CliError> {
        let conn = Connection::open(path)?;
        conn.execute_batch(SCHEMA_SQL)?;
        Ok(Self { conn })
    }

    pub fn connection(&self) -> &Connection {
        &self.conn
    }

    pub fn upsert_file(&self, path: &Path, timestamp: i64) -> Result<(), CliError> {
        let path_text = path.to_string_lossy().to_string();
        let name = path
            .file_name()
            .map(|value| value.to_string_lossy().to_string())
            .unwrap_or_else(|| path_text.clone());
        let stem = file_stem(&name);
        let parent = path
            .parent()
            .map(|value| value.to_string_lossy().to_string())
            .unwrap_or_default();
        let depth = dir_depth(Path::new(&parent));
        self.conn.execute(
            "insert or replace into files(path, name, lower_name, stem, lower_stem, parent, depth, last_seen)
             values(?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            params![
                path_text,
                name,
                name.to_lowercase(),
                stem,
                stem.to_lowercase(),
                parent,
                depth,
                timestamp
            ],
        )?;
        Ok(())
    }

    pub fn collect_paths(&self, sql: &str, values: &[&dyn ToSql]) -> Result<Vec<String>, CliError> {
        let mut stmt = self.conn.prepare(sql)?;
        let rows = stmt.query_map(params_from_iter(values.iter()), |row| {
            row.get::<_, String>(0)
        })?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    pub fn stat_get(&self, key: &str, fallback: &str) -> Result<String, CliError> {
        Ok(self
            .conn
            .query_row(
                "select value from stats where key = ?1",
                params![key],
                |row| row.get::<_, String>(0),
            )
            .optional()?
            .unwrap_or_else(|| fallback.to_owned()))
    }
}

impl IndexStore for SqliteStore {
    fn upsert_entry(&mut self, entry: &IndexEntry, timestamp: i64) -> Result<(), CliError> {
        let path = Path::new(&entry.path);
        let name = path
            .file_name()
            .map(|value| value.to_string_lossy().to_string())
            .unwrap_or_else(|| entry.path.clone());
        let parent = path
            .parent()
            .map(|value| value.to_string_lossy().to_string())
            .unwrap_or_default();
        let depth = dir_depth(path);
        let is_git = i64::from(path.join(".git").exists());
        let repo_name = if is_git == 1 {
            name.to_lowercase()
        } else {
            String::new()
        };
        let tx = self.conn.unchecked_transaction()?;
        tx.execute(
            "insert into dirs(path, name, lower_name, parent, depth, is_git, repo, repo_name, last_seen, last_used, hit_count)
             values(?1, ?2, ?3, ?4, ?5, ?6, ?6, ?7, ?8, ?8, coalesce((select hit_count from dirs where path = ?1), 0) + 1)
             on conflict(path) do update set name = excluded.name, lower_name = excluded.lower_name, parent = excluded.parent,
             depth = excluded.depth, is_git = excluded.is_git, repo = excluded.repo, repo_name = excluded.repo_name,
             last_seen = excluded.last_seen, last_used = excluded.last_used, hit_count = dirs.hit_count + 1",
            params![
                entry.path,
                name,
                name.to_lowercase(),
                parent,
                depth,
                is_git,
                repo_name,
                timestamp
            ],
        )?;
        tx.execute(
            "delete from tokens where dir_id in (select id from dirs where path = ?1)",
            params![entry.path],
        )?;
        let id: i64 = tx.query_row(
            "select id from dirs where path = ?1",
            params![entry.path],
            |row| row.get(0),
        )?;
        for token in dir_tokens(&entry.path) {
            tx.execute(
                "insert or ignore into tokens(token, dir_id) values(?1, ?2)",
                params![token, id],
            )?;
        }
        tx.commit()?;
        Ok(())
    }

    fn query_by_name(&self, name: &str, limit: usize) -> Result<Vec<IndexEntry>, CliError> {
        let limit_value =
            i64::try_from(limit).map_err(|_| CliError::InvalidNumber(limit.to_string()))?;
        let rows = self.collect_paths(
            "select path from dirs where lower_name = ?1 order by last_used desc, hit_count desc, depth asc, length(path), path limit ?2",
            &[&name, &limit_value],
        )?;
        Ok(rows.into_iter().map(|path| IndexEntry { path }).collect())
    }

    fn query_by_frecency(&self, limit: usize) -> Result<Vec<IndexEntry>, CliError> {
        let limit_value =
            i64::try_from(limit).map_err(|_| CliError::InvalidNumber(limit.to_string()))?;
        let rows = self.collect_paths(
            "select path from history order by last_used desc, visits desc, length(path), path limit ?1",
            &[&limit_value],
        )?;
        Ok(rows.into_iter().map(|path| IndexEntry { path }).collect())
    }

    fn record_visit(&self, path: &Path, timestamp: i64) -> Result<(), CliError> {
        self.conn.execute(
            "insert into history(path, visits, last_used) values(?1, 1, ?2)
             on conflict(path) do update set visits = history.visits + 1, last_used = excluded.last_used",
            params![path.to_string_lossy(), timestamp],
        )?;
        Ok(())
    }
}

// Storage intentionally stays behind `IndexStore`: if a future release evaluates
// redb or sled, re-check their maintenance state then and switch only at init.

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn index_store_queries_entries_when_using_sqlite() {
        let db = std::env::temp_dir().join(format!("reach-store-{}.sqlite3", std::process::id()));
        let _ = std::fs::remove_file(&db);
        let path = std::env::temp_dir()
            .join(format!("reach-store-dir-{}", std::process::id()))
            .join("service");
        std::fs::create_dir_all(&path).expect("fixture directory");
        let mut store = SqliteStore::open(&db.to_string_lossy()).expect("store");
        store
            .upsert_entry(
                &IndexEntry {
                    path: path.to_string_lossy().to_string(),
                },
                100,
            )
            .expect("upsert");
        store.record_visit(&path, 200).expect("visit");

        let by_name = store.query_by_name("service", 10).expect("name query");
        let by_frecency = store.query_by_frecency(10).expect("frecency query");

        assert_eq!(by_name[0].path, path.to_string_lossy());
        assert_eq!(by_frecency[0].path, path.to_string_lossy());
        let _ = std::fs::remove_file(db);
        let _ = std::fs::remove_dir_all(path.parent().unwrap_or_else(|| Path::new("/")));
    }

    #[test]
    fn sqlite_store_allows_concurrent_history_writes_without_lock_errors() {
        let db =
            std::env::temp_dir().join(format!("reach-concurrent-{}.sqlite3", std::process::id()));
        let _ = std::fs::remove_file(&db);
        let db_text = db.to_string_lossy().to_string();
        let store = SqliteStore::open(&db_text).expect("store");
        let journal_mode: String = store
            .connection()
            .query_row("pragma journal_mode", [], |row| row.get(0))
            .expect("journal mode");
        let busy_timeout: i64 = store
            .connection()
            .query_row("pragma busy_timeout", [], |row| row.get(0))
            .expect("busy timeout");
        assert_eq!(journal_mode.to_lowercase(), "wal");
        assert_eq!(busy_timeout, 5_000);
        drop(store);

        let mut handles = Vec::new();
        for thread_index in 0..16 {
            let db_for_thread = db_text.clone();
            handles.push(std::thread::spawn(move || -> Result<(), String> {
                let store = SqliteStore::open(&db_for_thread).map_err(|error| error.to_string())?;
                for visit_index in 0..50 {
                    let path = std::env::temp_dir()
                        .join(format!("reach-concurrent-{thread_index}-{visit_index}"));
                    store
                        .record_visit(&path, i64::from(thread_index * 1_000 + visit_index))
                        .map_err(|error| error.to_string())?;
                }
                Ok(())
            }));
        }

        let mut errors = Vec::new();
        for handle in handles {
            match handle.join().expect("thread should not panic") {
                Ok(()) => {}
                Err(error) => errors.push(error),
            }
        }

        assert!(
            errors.is_empty(),
            "concurrent write errors: {}",
            errors.join("; ")
        );
        let final_store = SqliteStore::open(&db_text).expect("final store");
        let count: i64 = final_store
            .connection()
            .query_row("select count(*) from history", [], |row| row.get(0))
            .expect("count");
        assert_eq!(count, 800);
        let _ = std::fs::remove_file(db);
    }
}
