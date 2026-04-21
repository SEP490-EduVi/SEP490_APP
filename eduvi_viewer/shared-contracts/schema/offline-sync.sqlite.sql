PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS schema_migrations (
  version INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  applied_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS packages (
  package_id TEXT PRIMARY KEY,
  package_type TEXT NOT NULL CHECK (package_type IN ('slide', 'game')),
  title TEXT NOT NULL,
  version TEXT NOT NULL,
  source_file_path TEXT NOT NULL,
  install_path TEXT NOT NULL,
  checksum_sha256 TEXT NOT NULL,
  manifest_json TEXT NOT NULL,
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
  installed_at TEXT NOT NULL,
  last_opened_at TEXT
);

CREATE TABLE IF NOT EXISTS sessions (
  session_id TEXT PRIMARY KEY,
  package_id TEXT NOT NULL,
  mode TEXT NOT NULL CHECK (mode IN ('new', 'resume')),
  state TEXT NOT NULL CHECK (state IN ('created', 'running', 'paused', 'completed', 'crashed')),
  launch_contract_path TEXT,
  started_at TEXT NOT NULL,
  ended_at TEXT,
  last_activity_at TEXT NOT NULL,
  last_snapshot_id TEXT,
  crash_recovered INTEGER NOT NULL DEFAULT 0 CHECK (crash_recovered IN (0, 1)),
  FOREIGN KEY (package_id) REFERENCES packages(package_id) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS progress_snapshots (
  snapshot_id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  package_id TEXT NOT NULL,
  level_id TEXT NOT NULL,
  checkpoint TEXT,
  score INTEGER NOT NULL,
  timer_ms_remaining INTEGER NOT NULL DEFAULT 0,
  state_json TEXT NOT NULL,
  checksum_sha256 TEXT NOT NULL,
  payload_path TEXT,
  is_valid INTEGER NOT NULL DEFAULT 1 CHECK (is_valid IN (0, 1)),
  created_at TEXT NOT NULL,
  FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
  FOREIGN KEY (package_id) REFERENCES packages(package_id) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS game_results (
  result_id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  package_id TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('completed', 'failed', 'aborted')),
  score INTEGER NOT NULL,
  duration_ms INTEGER NOT NULL,
  accuracy REAL,
  detail_json TEXT,
  completed_at TEXT NOT NULL,
  FOREIGN KEY (session_id) REFERENCES sessions(session_id) ON DELETE CASCADE,
  FOREIGN KEY (package_id) REFERENCES packages(package_id) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS app_settings (
  setting_key TEXT PRIMARY KEY,
  setting_value TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_packages_type_active
  ON packages(package_type, is_active);

CREATE INDEX IF NOT EXISTS idx_sessions_package_started
  ON sessions(package_id, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_snapshots_session_created
  ON progress_snapshots(session_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_results_package_completed
  ON game_results(package_id, completed_at DESC);
