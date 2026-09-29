// SQLite schema + migrations.
//
// Conventions: every timestamp is UTC epoch milliseconds (INTEGER). Raw
// tables are keyed by (source, source_record_id) so every ingest is an
// idempotent upsert; `record_id` is the upstream id (Health Connect
// metadata.id) used for deletions. Day tables are keyed by (mode, date) so
// demo and live data never mix.
//
// To change the schema: bump [kSchemaVersion] and append a step to
// [kMigrations] (never edit an old step).

const int kSchemaVersion = 3;

/// Statements that build the schema at version 1.
const List<String> kSchemaV1 = [
  // ── Raw rows ──────────────────────────────────────────────────────────
  '''CREATE TABLE raw_hr (
    source TEXT NOT NULL,
    source_record_id TEXT NOT NULL,
    record_id TEXT,
    origin_package TEXT,
    device TEXT,
    t INTEGER NOT NULL,
    bpm REAL NOT NULL,
    ingested_at INTEGER NOT NULL,
    PRIMARY KEY (source, source_record_id)
  )''',
  'CREATE INDEX raw_hr_time ON raw_hr (source, t)',
  'CREATE INDEX raw_hr_record ON raw_hr (source, record_id)',

  // 1-minute buckets per source and local day (Uint16 LE, bpm*10, 0=empty).
  '''CREATE TABLE hr_day (
    source TEXT NOT NULL,
    date TEXT NOT NULL,
    day_start INTEGER NOT NULL,
    minutes BLOB NOT NULL,
    samples INTEGER NOT NULL,
    last_t INTEGER,
    device TEXT,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (source, date)
  )''',

  '''CREATE TABLE raw_hrv (
    source TEXT NOT NULL,
    source_record_id TEXT NOT NULL,
    record_id TEXT,
    origin_package TEXT,
    device TEXT,
    t INTEGER NOT NULL,
    rmssd REAL NOT NULL,
    ingested_at INTEGER NOT NULL,
    PRIMARY KEY (source, source_record_id)
  )''',
  'CREATE INDEX raw_hrv_time ON raw_hrv (source, t)',
  'CREATE INDEX raw_hrv_record ON raw_hrv (source, record_id)',

  '''CREATE TABLE raw_sleep (
    source TEXT NOT NULL,
    source_record_id TEXT NOT NULL,
    record_id TEXT,
    origin_package TEXT,
    device TEXT,
    start INTEGER NOT NULL,
    "end" INTEGER NOT NULL,
    is_main INTEGER,
    minutes_asleep REAL,
    minutes_awake REAL,
    written_at INTEGER,
    ingested_at INTEGER NOT NULL,
    PRIMARY KEY (source, source_record_id)
  )''',
  'CREATE INDEX raw_sleep_time ON raw_sleep (source, start)',
  'CREATE INDEX raw_sleep_record ON raw_sleep (source, record_id)',

  '''CREATE TABLE raw_sleep_stage (
    source TEXT NOT NULL,
    session_id TEXT NOT NULL,
    start INTEGER NOT NULL,
    "end" INTEGER NOT NULL,
    stage TEXT NOT NULL,
    PRIMARY KEY (source, session_id, start)
  )''',

  '''CREATE TABLE raw_workout (
    source TEXT NOT NULL,
    source_record_id TEXT NOT NULL,
    record_id TEXT,
    origin_package TEXT,
    device TEXT,
    start INTEGER NOT NULL,
    "end" INTEGER NOT NULL,
    name TEXT NOT NULL,
    activity_type TEXT,
    avg_hr REAL,
    calories REAL,
    distance_m REAL,
    ingested_at INTEGER NOT NULL,
    PRIMARY KEY (source, source_record_id)
  )''',
  'CREATE INDEX raw_workout_time ON raw_workout (source, start)',
  'CREATE INDEX raw_workout_record ON raw_workout (source, record_id)',

  // Daily / nightly scalars: rhr, resp, skin_temp_delta, spo2_*, vo2max,
  // steps, weight, hrv_daily, hrv_deep_sleep, hrv_check.
  '''CREATE TABLE raw_scalar (
    source TEXT NOT NULL,
    source_record_id TEXT NOT NULL,
    record_id TEXT,
    origin_package TEXT,
    device TEXT,
    kind TEXT NOT NULL,
    start INTEGER NOT NULL,
    "end" INTEGER NOT NULL,
    value REAL NOT NULL,
    day TEXT,
    ingested_at INTEGER NOT NULL,
    PRIMARY KEY (source, source_record_id)
  )''',
  'CREATE INDEX raw_scalar_time ON raw_scalar (kind, source, start)',
  'CREATE INDEX raw_scalar_record ON raw_scalar (source, record_id)',

  // ── Resolved + computed ───────────────────────────────────────────────
  // DayRecord JSON without hrSamples; the 1-minute HR is the blob.
  '''CREATE TABLE day_record (
    mode TEXT NOT NULL,
    date TEXT NOT NULL,
    json TEXT NOT NULL,
    hr BLOB,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (mode, date)
  )''',
  '''CREATE TABLE day_result (
    mode TEXT NOT NULL,
    date TEXT NOT NULL,
    algo_version INTEGER NOT NULL,
    computed_at INTEGER NOT NULL,
    json TEXT NOT NULL,
    PRIMARY KEY (mode, date)
  )''',

  // ── App state ─────────────────────────────────────────────────────────
  '''CREATE TABLE journal (
    mode TEXT NOT NULL,
    date TEXT NOT NULL,
    json TEXT NOT NULL,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (mode, date)
  )''',
  '''CREATE TABLE sync_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    at INTEGER NOT NULL,
    source TEXT NOT NULL,
    data_type TEXT NOT NULL,
    status TEXT NOT NULL,
    records INTEGER NOT NULL DEFAULT 0,
    message TEXT
  )''',
  'CREATE INDEX sync_log_at ON sync_log (at)',
  '''CREATE TABLE settings (
    key TEXT PRIMARY KEY,
    value TEXT
  )''',
  '''CREATE TABLE change_tokens (
    source TEXT NOT NULL,
    scope TEXT NOT NULL,
    token TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (source, scope)
  )''',
];

/// Upgrade steps: index i upgrades from version i+1 to i+2.
/// (e.g. `['ALTER TABLE raw_hr ADD COLUMN quality REAL']`.)
const List<List<String>> kMigrations = [kCoachSchemaV2, kAnyAppSchemaV3];

/// v2 → v3: any app via Health Connect (decision 2026-09-29). HR buckets are
/// kept per origin app, so the resolver can use ONE app's heart rate per day
/// (never averaging two apps' samples into one minute). Rows written before
/// v3 came through the Fitbit-only filter, so Health Connect buckets are
/// Google Health (Fitbit) ones; demo and Bluetooth buckets get their fixed
/// origins; the Google Health API has its own.
const List<String> kAnyAppSchemaV3 = [
  '''CREATE TABLE hr_day_v3 (
    source TEXT NOT NULL,
    origin TEXT NOT NULL DEFAULT '',
    date TEXT NOT NULL,
    day_start INTEGER NOT NULL,
    minutes BLOB NOT NULL,
    samples INTEGER NOT NULL,
    last_t INTEGER,
    device TEXT,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (source, origin, date)
  )''',
  '''INSERT INTO hr_day_v3 (source, origin, date, day_start, minutes, samples,
    last_t, device, updated_at)
  SELECT source,
    CASE source
      WHEN 'hc' THEN 'com.fitbit.FitbitMobile'
      WHEN 'demo' THEN 'app.airlog.demo'
      WHEN 'ble' THEN 'app.airlog.live'
      WHEN 'ghapi' THEN 'health.googleapis.com'
      ELSE '' END,
    date, day_start, minutes, samples, last_t, device, updated_at
  FROM hr_day''',
  'DROP TABLE hr_day',
  'ALTER TABLE hr_day_v3 RENAME TO hr_day',
  // HRV ladder: Health Connect recordingMethod (AUTOMATIC / UNKNOWN count
  // for nightly HRV; ACTIVE / MANUAL are spot checks, never scored).
  'ALTER TABLE raw_hrv ADD COLUMN recording_method TEXT',
];

/// v1 → v2: the AI coach (data/coach). Chats, confirmed memories, the daily
/// cloud-usage meter and the insight-card cache. API keys are never stored
/// here (secure storage only), and none of these tables is exported.
const List<String> kCoachSchemaV2 = [
  '''CREATE TABLE coach_conversation (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )''',
  '''CREATE TABLE coach_message (
    id TEXT PRIMARY KEY,
    conversation_id TEXT NOT NULL,
    at INTEGER NOT NULL,
    seq INTEGER NOT NULL,
    json TEXT NOT NULL
  )''',
  'CREATE INDEX coach_message_conv ON coach_message (conversation_id, seq)',
  '''CREATE TABLE coach_memory (
    id TEXT PRIMARY KEY,
    text TEXT NOT NULL,
    category TEXT NOT NULL,
    expires_on TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER
  )''',
  '''CREATE TABLE coach_usage (
    day TEXT NOT NULL,
    provider TEXT NOT NULL,
    requests INTEGER NOT NULL,
    input_tokens INTEGER NOT NULL,
    output_tokens INTEGER NOT NULL,
    PRIMARY KEY (day, provider)
  )''',
  '''CREATE TABLE coach_insight (
    id TEXT NOT NULL,
    date TEXT NOT NULL,
    revision INTEGER NOT NULL,
    algo_version INTEGER NOT NULL,
    level TEXT NOT NULL,
    json TEXT NOT NULL,
    PRIMARY KEY (id, revision, algo_version, level)
  )''',
  'CREATE INDEX coach_insight_date ON coach_insight (date)',
  '''CREATE TABLE coach_insight_feedback (
    id TEXT PRIMARY KEY,
    feedback TEXT NOT NULL,
    at INTEGER NOT NULL
  )''',
  '''CREATE TABLE coach_kv (
    key TEXT PRIMARY KEY,
    value TEXT
  )''',
];

/// Every table the app owns (export, wipe, tests).
const List<String> kRawTables = [
  'raw_hr',
  'hr_day',
  'raw_hrv',
  'raw_sleep',
  'raw_sleep_stage',
  'raw_workout',
  'raw_scalar',
];

/// Coach tables (v2). Wiped with the data; never exported.
const List<String> kCoachTables = [
  'coach_conversation',
  'coach_message',
  'coach_memory',
  'coach_usage',
  'coach_insight',
  'coach_insight_feedback',
  'coach_kv',
];

const List<String> kAppTables = [
  'day_record',
  'day_result',
  'journal',
  'sync_log',
  'settings',
  'change_tokens',
];
