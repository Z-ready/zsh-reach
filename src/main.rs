mod ignore_rules;
mod store;
mod traverse;
mod watcher;

use rusqlite::{params, params_from_iter, Connection, OptionalExtension, ToSql};
use std::collections::HashSet;
use std::env;
use std::fmt::{self, Display};
use std::path::{Component, Path, PathBuf};
use std::process::ExitCode;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use store::{IndexEntry, IndexStore, SqliteStore, SCHEMA_SQL};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Mode {
    Exact,
    Token,
    Path,
    Git,
}

#[derive(Debug, PartialEq, Eq)]
struct QueryArgs {
    db: String,
    mode: Mode,
    terms: Vec<String>,
}

#[derive(Debug)]
enum CliError {
    Usage(&'static str),
    UnknownCommand(String),
    UnknownOption(String),
    UnknownMode(String),
    MissingValue(&'static str),
    EmptyQuery,
    InvalidNumber(String),
    Db(String),
    Io(String),
    Ignore(String),
    Watch(String),
    Time,
}

impl Display for CliError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Usage(message) => write!(f, "{message}"),
            Self::UnknownCommand(command) => write!(f, "unknown command: {command}"),
            Self::UnknownOption(option) => write!(f, "unknown option: {option}"),
            Self::UnknownMode(mode) => write!(f, "unknown mode: {mode}"),
            Self::MissingValue(option) => write!(f, "missing value for {option}"),
            Self::EmptyQuery => write!(f, "query requires at least one term"),
            Self::InvalidNumber(value) => write!(f, "invalid number: {value}"),
            Self::Db(message)
            | Self::Io(message)
            | Self::Ignore(message)
            | Self::Watch(message) => {
                write!(f, "{message}")
            }
            Self::Time => write!(f, "could not obtain epoch time"),
        }
    }
}

impl From<rusqlite::Error> for CliError {
    fn from(error: rusqlite::Error) -> Self {
        Self::Db(error.to_string())
    }
}

impl From<std::io::Error> for CliError {
    fn from(error: std::io::Error) -> Self {
        Self::Io(error.to_string())
    }
}

fn main() -> ExitCode {
    match run(env::args().skip(1).collect()) {
        Ok(output) => {
            print!("{output}");
            ExitCode::SUCCESS
        }
        Err(error) => {
            eprintln!("reach-helper: {error}");
            ExitCode::from(1)
        }
    }
}

fn run(args: Vec<String>) -> Result<String, CliError> {
    let (command, rest) = args.split_first().ok_or(CliError::Usage(
        "usage: reach-helper <command> --db <path> [options]",
    ))?;

    match command.as_str() {
        "init-db" => {
            let conn = open_db(required_value(rest, "--db")?)?;
            ensure_schema(&conn)?;
            Ok(String::new())
        }
        "query" => query(parse_query_args(rest)?),
        "record-frecency" => record_frecency(rest),
        "frecency-query" => frecency_query(rest),
        "frecency-top" => frecency_top(rest),
        "frecency-fields" => frecency_fields(rest),
        "record-recent" => record_recent(rest),
        "recent" => recent(rest),
        "upsert-dir" => upsert_dir_command(rest),
        "delete-path" => delete_path_command(rest),
        "upsert-file" => upsert_file_command(rest),
        "query-file" => query_file_command(rest),
        "delete-file" => delete_file_command(rest),
        "scan" => scan_command(rest),
        "index-root" => index_root_command(rest),
        "root-fresh" => root_fresh_command(rest),
        "watch-once" => watch_once_command(rest),
        "stat-set" => stat_set(rest),
        "stat-inc" => stat_inc(rest),
        "stat-get" => stat_get(rest),
        _ => Err(CliError::UnknownCommand(command.to_owned())),
    }
}

fn open_db(path: &str) -> Result<Connection, CliError> {
    let conn = Connection::open(path)?;
    ensure_schema(&conn)?;
    Ok(conn)
}

fn ensure_schema(conn: &Connection) -> Result<(), CliError> {
    conn.execute_batch(SCHEMA_SQL)?;
    Ok(())
}

fn parse_query_args(args: &[String]) -> Result<QueryArgs, CliError> {
    let db = required_value(args, "--db")?.to_owned();
    let mode = parse_mode(required_value(args, "--mode")?)?;
    let terms = terms_after_separator(args)?;
    if terms.is_empty() {
        return Err(CliError::EmptyQuery);
    }
    Ok(QueryArgs { db, mode, terms })
}

fn parse_mode(value: &str) -> Result<Mode, CliError> {
    match value {
        "exact" => Ok(Mode::Exact),
        "token" => Ok(Mode::Token),
        "path" => Ok(Mode::Path),
        "git" => Ok(Mode::Git),
        _ => Err(CliError::UnknownMode(value.to_owned())),
    }
}

fn required_value<'a>(args: &'a [String], flag: &'static str) -> Result<&'a str, CliError> {
    let mut index = 0usize;
    while index < args.len() {
        if args[index] == flag {
            let value = args.get(index + 1).ok_or(CliError::MissingValue(flag))?;
            return Ok(value);
        }
        index += 1;
    }
    Err(CliError::MissingValue(flag))
}

fn optional_value<'a>(args: &'a [String], flag: &str) -> Option<&'a str> {
    let mut index = 0usize;
    while index < args.len() {
        if args[index] == flag {
            return args.get(index + 1).map(String::as_str);
        }
        index += 1;
    }
    None
}

fn optional_values<'a>(args: &'a [String], flag: &str) -> Vec<&'a str> {
    let mut values = Vec::new();
    let mut index = 0usize;
    while index < args.len() {
        if args[index] == flag {
            if let Some(value) = args.get(index + 1) {
                values.push(value.as_str());
            }
            index += 1;
        }
        index += 1;
    }
    values
}

fn has_flag(args: &[String], flag: &str) -> bool {
    args.iter().any(|arg| arg == flag)
}

fn terms_after_separator(args: &[String]) -> Result<Vec<String>, CliError> {
    let mut terms = Vec::new();
    let mut passthrough = false;
    let mut index = 0usize;
    while index < args.len() {
        let arg = &args[index];
        if passthrough {
            terms.push(arg.to_lowercase());
        } else if arg == "--" {
            passthrough = true;
        } else if matches!(
            arg.as_str(),
            "--db"
                | "--mode"
                | "--threshold"
                | "--now"
                | "--kind"
                | "--root"
                | "--max-depth"
                | "--reachignore"
                | "--path"
                | "--key"
                | "--value"
                | "--fallback"
                | "--mtime"
                | "--config-key"
                | "--limit"
                | "--timeout-ms"
        ) {
            index += 1;
            if index >= args.len() {
                return Err(CliError::MissingValue(match arg.as_str() {
                    "--db" => "--db",
                    "--mode" => "--mode",
                    "--threshold" => "--threshold",
                    "--now" => "--now",
                    "--kind" => "--kind",
                    "--root" => "--root",
                    "--max-depth" => "--max-depth",
                    "--reachignore" => "--reachignore",
                    "--path" => "--path",
                    "--key" => "--key",
                    "--value" => "--value",
                    "--fallback" => "--fallback",
                    "--mtime" => "--mtime",
                    "--config-key" => "--config-key",
                    "--limit" => "--limit",
                    "--timeout-ms" => "--timeout-ms",
                    _ => "--",
                }));
            }
        } else if matches!(
            arg.as_str(),
            "--follow-links"
                | "--no-gitignore"
                | "--deep-fallback"
                | "--no-deep-prompt"
                | "--debug-layer"
        ) {
        } else if arg.starts_with('-') {
            return Err(CliError::UnknownOption(arg.to_owned()));
        }
        index += 1;
    }
    Ok(terms)
}

fn now_epoch() -> Result<i64, CliError> {
    let duration = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| CliError::Time)?;
    i64::try_from(duration.as_secs()).map_err(|_| CliError::Time)
}

fn now_arg(args: &[String]) -> Result<i64, CliError> {
    match optional_value(args, "--now") {
        Some(value) => value
            .parse::<i64>()
            .map_err(|_| CliError::InvalidNumber(value.to_owned())),
        None => now_epoch(),
    }
}

fn query(args: QueryArgs) -> Result<String, CliError> {
    if matches!(args.mode, Mode::Exact) && args.terms.len() == 1 {
        let store = SqliteStore::open(&args.db)?;
        let rows = store
            .query_by_name(&args.terms[0], 50)?
            .into_iter()
            .map(|entry| entry.path)
            .collect::<Vec<_>>();
        return Ok(join_lines(&rows));
    }
    let conn = open_db(&args.db)?;
    let rows = query_paths(&conn, args.mode, &args.terms)?;
    Ok(join_lines(&rows))
}

fn query_paths(conn: &Connection, mode: Mode, terms: &[String]) -> Result<Vec<String>, CliError> {
    if terms.is_empty() {
        return Err(CliError::EmptyQuery);
    }
    let first = &terms[0];
    match mode {
        Mode::Exact => {
            if terms.len() != 1 {
                return Err(CliError::Usage("exact mode requires one query term"));
            }
            collect_paths(
                conn,
                "select path from dirs where lower_name = ?1 order by last_used desc, hit_count desc, depth asc, length(path), path limit 50",
                &[first],
            )
        }
        Mode::Path => query_path_fragments(conn, terms, first),
        Mode::Token => query_tokens(conn, terms, first, false),
        Mode::Git => query_tokens(conn, terms, first, true),
    }
}

fn query_path_fragments(
    conn: &Connection,
    terms: &[String],
    first: &str,
) -> Result<Vec<String>, CliError> {
    let clauses = terms
        .iter()
        .map(|_| "lower(path) like ?")
        .collect::<Vec<_>>()
        .join(" and ");
    let sql = format!(
        "select path from dirs where {clauses} order by case when lower_name = ? then 0 else 1 end, last_used desc, hit_count desc, depth asc, length(path), path limit 50"
    );
    let patterns = terms
        .iter()
        .map(|term| format!("%{term}%"))
        .collect::<Vec<_>>();
    let mut values: Vec<&dyn ToSql> = patterns.iter().map(|value| value as &dyn ToSql).collect();
    values.push(&first);
    collect_paths(conn, &sql, &values)
}

fn query_tokens(
    conn: &Connection,
    terms: &[String],
    first: &str,
    git_only: bool,
) -> Result<Vec<String>, CliError> {
    let placeholders = std::iter::repeat_n("?", terms.len())
        .collect::<Vec<_>>()
        .join(",");
    let repo_filter = if git_only { "d.repo = 1 and " } else { "" };
    let exact_column = if git_only {
        "d.repo_name"
    } else {
        "d.lower_name"
    };
    let sql = format!(
        "select d.path from dirs d join tokens t on t.dir_id = d.id where {repo_filter}t.token in ({placeholders}) group by d.path having count(distinct t.token) = {} order by case when {exact_column} = ? then 0 else 1 end, d.last_used desc, d.hit_count desc, d.depth asc, length(d.path), d.path limit 50",
        terms.len()
    );
    let mut values: Vec<&dyn ToSql> = terms.iter().map(|term| term as &dyn ToSql).collect();
    values.push(&first);
    collect_paths(conn, &sql, &values)
}

fn collect_paths(
    conn: &Connection,
    sql: &str,
    values: &[&dyn ToSql],
) -> Result<Vec<String>, CliError> {
    let mut stmt = conn.prepare(sql)?;
    let rows = stmt.query_map(params_from_iter(values.iter()), |row| {
        row.get::<_, String>(0)
    })?;
    let mut out = Vec::new();
    for row in rows {
        out.push(row?);
    }
    Ok(out)
}

fn frecency_score(visits: i64, last_used: i64, now: i64) -> f64 {
    let age = now - last_used;
    let multiplier = if age <= 3_600 {
        4.0
    } else if age <= 86_400 {
        2.0
    } else if age <= 604_800 {
        0.5
    } else {
        0.25
    };
    visits as f64 * multiplier
}

fn record_frecency(args: &[String]) -> Result<String, CliError> {
    let store = SqliteStore::open(required_value(args, "--db")?)?;
    let path = required_value(args, "--path")?;
    let threshold = optional_value(args, "--threshold").unwrap_or("1");
    let threshold = threshold
        .parse::<f64>()
        .map_err(|_| CliError::InvalidNumber(threshold.to_owned()))?;
    let now = now_arg(args)?;
    store.record_visit(Path::new(path), now)?;
    let cutoff = now - 604_800;
    store.connection().execute(
        "delete from history where not exists (select 1 from dirs d where d.path = history.path) and last_used < ?1",
        params![cutoff],
    )?;
    prune_low_score_history(store.connection(), now, threshold, cutoff)?;
    Ok(String::new())
}

fn prune_low_score_history(
    conn: &Connection,
    now: i64,
    threshold: f64,
    cutoff: i64,
) -> Result<(), CliError> {
    let mut stmt =
        conn.prepare("select path, visits, last_used from history where last_used < ?1")?;
    let rows = stmt.query_map(params![cutoff], |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, i64>(1)?,
            row.get::<_, i64>(2)?,
        ))
    })?;
    for row in rows {
        let (path, visits, last_used) = row?;
        if frecency_score(visits, last_used, now) < threshold {
            conn.execute("delete from history where path = ?1", params![path])?;
        }
    }
    Ok(())
}

fn frecency_query(args: &[String]) -> Result<String, CliError> {
    let conn = open_db(required_value(args, "--db")?)?;
    let threshold = optional_value(args, "--threshold").unwrap_or("1");
    let threshold = threshold
        .parse::<f64>()
        .map_err(|_| CliError::InvalidNumber(threshold.to_owned()))?;
    let now = now_arg(args)?;
    let terms = terms_after_separator(args)?;
    if terms.is_empty() {
        return Err(CliError::EmptyQuery);
    }
    let rows = frecency_paths(&conn, &terms, now, threshold)?;
    Ok(join_lines(&rows))
}

fn frecency_top(args: &[String]) -> Result<String, CliError> {
    let store = SqliteStore::open(required_value(args, "--db")?)?;
    let limit = optional_value(args, "--limit")
        .unwrap_or("50")
        .parse::<usize>()
        .map_err(|_| {
            CliError::InvalidNumber(optional_value(args, "--limit").unwrap_or("50").to_owned())
        })?;
    let rows = store
        .query_by_frecency(limit)?
        .into_iter()
        .map(|entry| entry.path)
        .collect::<Vec<_>>();
    Ok(join_lines(&rows))
}

fn frecency_paths(
    conn: &Connection,
    terms: &[String],
    now: i64,
    threshold: f64,
) -> Result<Vec<String>, CliError> {
    let mut stmt = conn.prepare("select path, visits, last_used from history")?;
    let rows = stmt.query_map([], |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, i64>(1)?,
            row.get::<_, i64>(2)?,
        ))
    })?;
    let mut scored = Vec::new();
    for row in rows {
        let (path, visits, last_used) = row?;
        let lower = path.to_lowercase();
        let matches = if terms.len() == 1 && !terms[0].contains('/') {
            lower.ends_with(&format!("/{}", terms[0]))
        } else {
            terms.iter().all(|term| lower.contains(term))
        };
        let score = frecency_score(visits, last_used, now);
        if matches && score >= threshold {
            scored.push((path, score, last_used));
        }
    }
    scored.sort_by(|left, right| {
        let left_exact = left.0.to_lowercase().ends_with(&format!("/{}", terms[0]));
        let right_exact = right.0.to_lowercase().ends_with(&format!("/{}", terms[0]));
        left_exact
            .cmp(&right_exact)
            .reverse()
            .then_with(|| right.1.total_cmp(&left.1))
            .then_with(|| right.2.cmp(&left.2))
            .then_with(|| left.0.len().cmp(&right.0.len()))
            .then_with(|| left.0.cmp(&right.0))
    });
    Ok(scored.into_iter().take(50).map(|row| row.0).collect())
}

fn frecency_fields(args: &[String]) -> Result<String, CliError> {
    let conn = open_db(required_value(args, "--db")?)?;
    let path = required_value(args, "--path")?;
    let now = now_arg(args)?;
    let row = conn
        .query_row(
            "select visits, last_used from history where path = ?1",
            params![path],
            |row| Ok((row.get::<_, i64>(0)?, row.get::<_, i64>(1)?)),
        )
        .optional()?;
    match row {
        Some((visits, last_used)) => Ok(format!(
            "{:.6}\t{}\t{}\n",
            frecency_score(visits, last_used, now),
            last_used,
            visits
        )),
        None => Ok("0\t0\t0\n".to_owned()),
    }
}

fn record_recent(args: &[String]) -> Result<String, CliError> {
    let conn = open_db(required_value(args, "--db")?)?;
    let path = required_value(args, "--path")?;
    let now = now_arg(args)?;
    conn.execute(
        "insert or replace into recent(path, last_used) values(?1, ?2)",
        params![path, now],
    )?;
    conn.execute(
        "delete from recent where path not in (select path from recent order by last_used desc, rowid desc limit 50)",
        [],
    )?;
    Ok(String::new())
}

fn recent(args: &[String]) -> Result<String, CliError> {
    let conn = open_db(required_value(args, "--db")?)?;
    collect_paths(
        &conn,
        "select path from recent order by last_used desc, rowid desc limit 50",
        &[],
    )
    .map(|paths| join_lines(&paths))
}

fn upsert_dir_command(args: &[String]) -> Result<String, CliError> {
    let conn = open_db(required_value(args, "--db")?)?;
    let path = required_value(args, "--path")?;
    let now = now_arg(args)?;
    upsert_dir(&conn, Path::new(path), now)?;
    Ok(String::new())
}

fn upsert_dir(conn: &Connection, path: &Path, now: i64) -> Result<(), CliError> {
    let path_text = path.to_string_lossy().to_string();
    let name = path
        .file_name()
        .map(|value| value.to_string_lossy().to_string())
        .unwrap_or_else(|| path_text.clone());
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
    let tx = conn.unchecked_transaction()?;
    tx.execute(
        "insert into dirs(path, name, lower_name, parent, depth, is_git, repo, repo_name, last_seen, last_used, hit_count)
         values(?1, ?2, ?3, ?4, ?5, ?6, ?6, ?7, ?8, ?8, coalesce((select hit_count from dirs where path = ?1), 0) + 1)
         on conflict(path) do update set name = excluded.name, lower_name = excluded.lower_name, parent = excluded.parent,
         depth = excluded.depth, is_git = excluded.is_git, repo = excluded.repo, repo_name = excluded.repo_name,
         last_seen = excluded.last_seen, last_used = excluded.last_used, hit_count = dirs.hit_count + 1",
        params![path_text, name, name.to_lowercase(), parent, depth, is_git, repo_name, now],
    )?;
    tx.execute(
        "delete from tokens where dir_id in (select id from dirs where path = ?1)",
        params![path_text],
    )?;
    let id: i64 = tx.query_row(
        "select id from dirs where path = ?1",
        params![path_text],
        |row| row.get(0),
    )?;
    for token in dir_tokens(&path_text) {
        tx.execute(
            "insert or ignore into tokens(token, dir_id) values(?1, ?2)",
            params![token, id],
        )?;
    }
    tx.commit()?;
    Ok(())
}

fn delete_path_command(args: &[String]) -> Result<String, CliError> {
    let conn = open_db(required_value(args, "--db")?)?;
    let path = required_value(args, "--path")?;
    conn.execute(
        "delete from tokens where dir_id in (select id from dirs where path = ?1)",
        params![path],
    )?;
    conn.execute("delete from dirs where path = ?1", params![path])?;
    conn.execute("delete from history where path = ?1", params![path])?;
    Ok(String::new())
}

fn upsert_file_command(args: &[String]) -> Result<String, CliError> {
    let store = SqliteStore::open(required_value(args, "--db")?)?;
    let path = required_value(args, "--path")?;
    let now = now_arg(args)?;
    store.upsert_file(Path::new(path), now)?;
    Ok(String::new())
}

fn query_file_command(args: &[String]) -> Result<String, CliError> {
    let conn = open_db(required_value(args, "--db")?)?;
    let terms = terms_after_separator(args)?;
    let query = terms.first().ok_or(CliError::EmptyQuery)?;
    let rows = if query_has_extension(query) {
        collect_paths(
            &conn,
            "select path from files where lower_name = ?1 order by depth asc, length(parent), parent, path limit 100",
            &[query],
        )?
    } else {
        collect_paths(
            &conn,
            "select path from files where lower_name = ?1 or lower_stem = ?1 order by case when lower_name = ?1 then 0 else 1 end, depth asc, length(parent), parent, path limit 100",
            &[query],
        )?
    };
    Ok(join_lines(&rows))
}

fn delete_file_command(args: &[String]) -> Result<String, CliError> {
    let conn = open_db(required_value(args, "--db")?)?;
    let path = required_value(args, "--path")?;
    conn.execute("delete from files where path = ?1", params![path])?;
    Ok(String::new())
}

fn stat_set(args: &[String]) -> Result<String, CliError> {
    let conn = open_db(required_value(args, "--db")?)?;
    let key = required_value(args, "--key")?;
    let value = required_value(args, "--value")?;
    conn.execute(
        "insert or replace into stats(key, value) values(?1, ?2)",
        params![key, value],
    )?;
    Ok(String::new())
}

fn stat_inc(args: &[String]) -> Result<String, CliError> {
    let conn = open_db(required_value(args, "--db")?)?;
    let key = required_value(args, "--key")?;
    conn.execute(
        "insert into stats(key, value) values(?1, '1') on conflict(key) do update set value = cast(stats.value as integer) + 1",
        params![key],
    )?;
    Ok(String::new())
}

fn stat_get(args: &[String]) -> Result<String, CliError> {
    let store = SqliteStore::open(required_value(args, "--db")?)?;
    let key = required_value(args, "--key")?;
    let fallback = optional_value(args, "--fallback").unwrap_or("0");
    let value = store.stat_get(key, fallback)?;
    Ok(format!("{value}\n"))
}

fn scan_command(args: &[String]) -> Result<String, CliError> {
    let roots = optional_values(args, "--root")
        .into_iter()
        .map(PathBuf::from)
        .collect::<Vec<_>>();
    if roots.is_empty() {
        return Err(CliError::MissingValue("--root"));
    }
    let kind = match optional_value(args, "--kind").unwrap_or("dir") {
        "dir" => traverse::TargetKind::Directory,
        "file" => traverse::TargetKind::File,
        value => return Err(CliError::UnknownMode(value.to_owned())),
    };
    let mode = match optional_value(args, "--mode").unwrap_or("exact") {
        "exact" => traverse::MatchMode::Exact,
        "path" => traverse::MatchMode::Path,
        "broad" => traverse::MatchMode::Broad,
        value => return Err(CliError::UnknownMode(value.to_owned())),
    };
    let max_depth = optional_value(args, "--max-depth")
        .map(|value| {
            value
                .parse::<usize>()
                .map_err(|_| CliError::InvalidNumber(value.to_owned()))
        })
        .transpose()?;
    let reachignore = optional_value(args, "--reachignore").map(PathBuf::from);
    let terms = terms_after_separator(args)?;
    let config = traverse::TraverseConfig {
        roots,
        query_terms: terms.into_iter().map(|term| term.to_lowercase()).collect(),
        kind,
        mode,
        max_depth,
        follow_links: has_flag(args, "--follow-links"),
        reachignore,
        use_gitignore: !has_flag(args, "--no-gitignore"),
        deep_fallback: has_flag(args, "--deep-fallback"),
        deep_prompt: !has_flag(args, "--no-deep-prompt"),
    };
    let outcome = traverse::search(&config)?;
    if has_flag(args, "--debug-layer") {
        eprintln!(
            "reach-helper: scan layer={} visited={}",
            outcome.layer, outcome.visited
        );
    }
    let rows = outcome
        .matches
        .into_iter()
        .map(|path| path.to_string_lossy().to_string())
        .collect::<Vec<_>>();
    Ok(join_lines(&rows))
}

fn index_root_command(args: &[String]) -> Result<String, CliError> {
    let db = required_value(args, "--db")?;
    let root = PathBuf::from(required_value(args, "--root")?);
    let now = now_arg(args)?;
    let max_depth = optional_value(args, "--max-depth")
        .map(|value| {
            value
                .parse::<usize>()
                .map_err(|_| CliError::InvalidNumber(value.to_owned()))
        })
        .transpose()?;
    let reachignore = optional_value(args, "--reachignore").map(PathBuf::from);
    let mut store = SqliteStore::open(db)?;
    let dirs = traverse::serial_walk_for_index(
        &root,
        max_depth,
        has_flag(args, "--follow-links"),
        reachignore.as_deref(),
        !has_flag(args, "--no-gitignore"),
    )?;
    let indexed = dirs
        .iter()
        .map(|dir| dir.to_string_lossy().to_string())
        .collect::<HashSet<_>>();
    prune_missing_under_root(store.connection(), &root, &indexed)?;
    for dir in dirs {
        store.upsert_entry(
            &IndexEntry {
                path: dir.to_string_lossy().to_string(),
            },
            now,
        )?;
    }
    let root_text = root.to_string_lossy().to_string();
    store.connection().execute(
        "insert or replace into roots(path, mtime, config_key, last_indexed) values(?1, ?2, ?3, ?4)",
        params![
            root_text,
            optional_value(args, "--mtime").unwrap_or("0"),
            optional_value(args, "--config-key").unwrap_or(""),
            now
        ],
    )?;
    Ok(String::new())
}

fn prune_missing_under_root(
    conn: &Connection,
    root: &Path,
    indexed: &HashSet<String>,
) -> Result<(), CliError> {
    let root_text = root.to_string_lossy().to_string();
    let root_like = format!("{root_text}/%");
    let mut stmt = conn.prepare("select path from dirs where path = ?1 or path like ?2")?;
    let rows = stmt.query_map(params![root_text, root_like], |row| row.get::<_, String>(0))?;
    let mut missing = Vec::new();
    for row in rows {
        let path = row?;
        if !indexed.contains(&path) {
            missing.push(path);
        }
    }
    for path in missing {
        conn.execute(
            "delete from tokens where dir_id in (select id from dirs where path = ?1)",
            params![path],
        )?;
        conn.execute("delete from dirs where path = ?1", params![path])?;
        conn.execute(
            "delete from files where path = ?1 or path like ?2",
            params![path, format!("{path}/%")],
        )?;
    }
    Ok(())
}

fn root_fresh_command(args: &[String]) -> Result<String, CliError> {
    let store = SqliteStore::open(required_value(args, "--db")?)?;
    let root = required_value(args, "--root")?;
    let mtime = required_value(args, "--mtime")?;
    let config_key = required_value(args, "--config-key")?;
    let stored = store
        .connection()
        .query_row(
            "select mtime || char(9) || config_key from roots where path = ?1",
            params![root],
            |row| row.get::<_, String>(0),
        )
        .optional()?;
    if stored.as_deref() == Some(&format!("{mtime}\t{config_key}")) {
        Ok("1\n".to_owned())
    } else {
        Ok("0\n".to_owned())
    }
}

fn watch_once_command(args: &[String]) -> Result<String, CliError> {
    let roots = optional_values(args, "--root")
        .into_iter()
        .map(PathBuf::from)
        .collect::<Vec<_>>();
    if roots.is_empty() {
        return Err(CliError::MissingValue("--root"));
    }
    let timeout_ms = optional_value(args, "--timeout-ms")
        .unwrap_or("86400000")
        .parse::<u64>()
        .map_err(|_| {
            CliError::InvalidNumber(
                optional_value(args, "--timeout-ms")
                    .unwrap_or("")
                    .to_owned(),
            )
        })?;
    watcher::watch_once(&roots, Duration::from_millis(timeout_ms))?;
    Ok(String::new())
}

pub fn dir_depth(path: &Path) -> i64 {
    path.components()
        .filter(|component| matches!(component, Component::Normal(_)))
        .count() as i64
}

pub fn dir_tokens(path: &str) -> Vec<String> {
    let mut tokens = Vec::new();
    for part in path.to_lowercase().split('/') {
        push_unique(&mut tokens, part);
        for token in part.split(['-', '_', '.']) {
            push_unique(&mut tokens, token);
        }
    }
    tokens
}

fn push_unique(tokens: &mut Vec<String>, token: &str) {
    if !token.is_empty() && !tokens.iter().any(|existing| existing == token) {
        tokens.push(token.to_owned());
    }
}

fn query_has_extension(query: &str) -> bool {
    query.contains('.') && !query.starts_with('.')
}

pub fn file_stem(name: &str) -> String {
    if query_has_extension(name) {
        name.rsplit_once('.')
            .map(|(stem, _extension)| stem.to_owned())
            .unwrap_or_else(|| name.to_owned())
    } else {
        name.to_owned()
    }
}

fn join_lines(rows: &[String]) -> String {
    if rows.is_empty() {
        String::new()
    } else {
        format!("{}\n", rows.join("\n"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_query_args_when_terms_follow_separator() {
        let args = vec![
            "--db".to_string(),
            "/tmp/index.sqlite3".to_string(),
            "--mode".to_string(),
            "token".to_string(),
            "--".to_string(),
            "App".to_string(),
            "Backend".to_string(),
        ];

        let parsed = parse_query_args(&args).expect("query args should parse");

        assert_eq!(
            parsed,
            QueryArgs {
                db: "/tmp/index.sqlite3".to_string(),
                mode: Mode::Token,
                terms: vec!["app".to_string(), "backend".to_string()]
            }
        );
    }

    #[test]
    fn frecency_score_when_age_changes_multiplier() {
        assert_eq!(frecency_score(2, 1_000, 1_100), 8.0);
        assert_eq!(frecency_score(2, 1_000, 91_000), 1.0);
        assert_eq!(frecency_score(2, 1_000, 1_300_000), 0.5);
    }

    #[test]
    fn dir_tokens_when_path_has_separators() {
        let tokens = dir_tokens("/tmp/openai-api/src_plugin");

        assert!(tokens.contains(&"openai-api".to_string()));
        assert!(tokens.contains(&"openai".to_string()));
        assert!(tokens.contains(&"api".to_string()));
        assert!(tokens.contains(&"src".to_string()));
        assert!(tokens.contains(&"plugin".to_string()));
    }
}
