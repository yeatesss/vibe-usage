CREATE TABLE usage_events (
  id                       INTEGER PRIMARY KEY AUTOINCREMENT,
  ts_utc                   INTEGER NOT NULL,
  tool                     TEXT    NOT NULL,
  model                    TEXT    NOT NULL,
  input_tokens             INTEGER NOT NULL DEFAULT 0,
  output_tokens            INTEGER NOT NULL DEFAULT 0,
  cache_read_tokens        INTEGER NOT NULL DEFAULT 0,
  cache_write_tokens       INTEGER NOT NULL DEFAULT 0,
  reasoning_output_tokens  INTEGER NOT NULL DEFAULT 0,
  source_file              TEXT    NOT NULL,
  source_offset            INTEGER NOT NULL
);
CREATE INDEX        idx_events_ts        ON usage_events(ts_utc);
CREATE INDEX        idx_events_tool_ts   ON usage_events(tool, ts_utc);
CREATE UNIQUE INDEX uniq_events_source   ON usage_events(source_file, source_offset);

CREATE TABLE log_files (
  path             TEXT    PRIMARY KEY,
  tool             TEXT    NOT NULL,
  size_bytes       INTEGER NOT NULL,
  mtime_unix       INTEGER NOT NULL,
  last_total_json  TEXT,
  last_model       TEXT,
  updated_at       INTEGER NOT NULL
);

CREATE TABLE pricing_profiles (
  model                            TEXT NOT NULL,
  source                           TEXT NOT NULL,
  effective_from                   TEXT NOT NULL,
  input_usd_per_million            TEXT NOT NULL,
  cached_input_usd_per_million     TEXT NOT NULL,
  cache_creation_usd_per_million   TEXT NOT NULL,
  output_usd_per_million           TEXT NOT NULL,
  reasoning_output_usd_per_million TEXT NOT NULL,
  PRIMARY KEY (model, source, effective_from)
);

CREATE TABLE metadata (
  k TEXT PRIMARY KEY,
  v TEXT NOT NULL
);

-- Claude family: cached_input = input × 0.1, cache_creation = input × 1.25, reasoning_output = output
INSERT INTO pricing_profiles VALUES
  ('claude-opus-4-7',   'claude', '2026-03-01', '5.00', '0.50', '6.25', '25.00', '25.00'),
  ('claude-opus-4-6',   'claude', '2025-12-01', '5.00', '0.50', '6.25', '25.00', '25.00'),
  ('claude-opus-4-5',   'claude', '2025-09-01', '5.00', '0.50', '6.25', '25.00', '25.00'),
  ('claude-sonnet-4-6', 'claude', '2025-12-01', '3.00', '0.30', '3.75', '15.00', '15.00'),
  ('claude-sonnet-4-5', 'claude', '2025-09-01', '3.00', '0.30', '3.75', '15.00', '15.00'),
  ('claude-sonnet-4',   'claude', '2025-05-01', '3.00', '0.30', '3.75', '15.00', '15.00'),
  ('claude-haiku-4-5',  'claude', '2025-09-01', '1.00', '0.10', '1.25',  '5.00',  '5.00'),
  ('gpt-5.4-codex',     'codex',  '2026-03-01', '1.75', '0.175','0.00', '14.00', '14.00'),
  ('gpt-5.2-codex',     'codex',  '2025-12-23', '1.75', '0.175','0.00', '14.00', '14.00');
