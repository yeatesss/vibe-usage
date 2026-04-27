-- Sessions per source-file: holds project-level metadata (cwd, git branch) and
-- the time-range observed within a single jsonl session log. Joined with
-- usage_events at query time to aggregate by project.
CREATE TABLE sessions (
  source_file  TEXT PRIMARY KEY,
  tool         TEXT    NOT NULL,
  cwd          TEXT    NOT NULL DEFAULT '',
  git_branch   TEXT    NOT NULL DEFAULT '',
  first_ts_utc INTEGER,
  last_ts_utc  INTEGER,
  updated_at   INTEGER NOT NULL
);

CREATE INDEX idx_sessions_tool_cwd ON sessions(tool, cwd);

-- Force a single re-scan so existing usage_events get sessions rows backfilled.
-- usage_events stays intact (UNIQUE(source_file, source_offset) deduplicates).
DELETE FROM log_files;
