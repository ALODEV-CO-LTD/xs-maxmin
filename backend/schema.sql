-- =============================================================================
-- XOSO -- Production database schema (SQLite)
-- =============================================================================
-- This file documents the schema exactly as maintained by
-- lib/src/database.dart (_createSchema + _migrateSchema), which runs
-- idempotently on every server startup. It is NOT executed automatically --
-- it exists purely as an up-to-date, readable reference and as the basis for
-- writing ad-hoc queries against production. Table/column order matches the
-- live database verified on xs.maxmin.vn on 2026-09-30.
--
-- Live file location on production:
--   /opt/xs-maxmin/backend/build/data/xoso.db
--   (NOT /opt/xs-maxmin/backend/data/xoso.db -- that path is a stale, unused
--   empty file left over from before the systemd WorkingDirectory was
--   changed to backend/build/ to fix the sqlite3 native-assets startup bug;
--   database.dart resolves its data/ folder relative to the process's
--   working directory, so build/data/ is the one the running app actually
--   reads and writes.)
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Accounts (both "admin" back-office users and "user" dai ly accounts)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
  id                    TEXT PRIMARY KEY,
  name                  TEXT NOT NULL,
  username              TEXT NOT NULL UNIQUE,
  password_hash         TEXT NOT NULL,
  second_password_hash  TEXT,               -- optional second PIN/password
  wipe_password_hash    TEXT,               -- optional "wipe data" password
  role                  TEXT NOT NULL CHECK (role IN ('user', 'admin')),
  package_type          TEXT NOT NULL DEFAULT 'none',
  package_started_at    TEXT,
  package_expires_at    TEXT,
  data_quota_total      INTEGER NOT NULL DEFAULT 0,
  data_used             INTEGER NOT NULL DEFAULT 0,
  status                TEXT NOT NULL DEFAULT 'active',
  created_at            TEXT NOT NULL,
  scoring_rates         TEXT,               -- JSON: {typeKey: {rate, tiers[]}} -- added via migration
  -- Mã khôi phục: bcrypt hash only (never the code), + throttle state -- added via migration
  recovery_code_hash        TEXT,
  recovery_code_created_at  TEXT,
  recovery_failed_attempts  INTEGER NOT NULL DEFAULT 0,
  recovery_locked_until     TEXT,
  tokens_valid_after        INTEGER           -- epoch s; revokes session-less tokens issued before it
);


-- -----------------------------------------------------------------------------
-- Each account's own customer roster (added for the Vue rebuild).
-- Entries and scoring pick a customer FROM here, instead of free-typing a
-- name on every row, so a typo never silently creates a duplicate customer.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS customers (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  created_at  TEXT NOT NULL,
  UNIQUE (user_id, name)
);


-- -----------------------------------------------------------------------------
-- Bet entries a customer places ("Nhap so"). `result` is filled in
-- automatically by ScoringView once a lottery_results row exists for the
-- same date, using the owning account's scoring_rates config.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS data_entries (
  id             TEXT PRIMARY KEY,
  user_id        TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  customer_name  TEXT,
  entry_date     TEXT NOT NULL,
  value          TEXT NOT NULL,   -- the number(s) played
  score          TEXT,            -- diem vao (stake)
  result         TEXT,            -- diem ra (auto-computed payout), null until scored
  note           TEXT,
  created_at     TEXT NOT NULL,
  bet_type       TEXT             -- key into the owning user's scoring_rates, e.g. 'de' / 'lo' -- added via migration
);
CREATE INDEX IF NOT EXISTS idx_data_entries_user_date ON data_entries(user_id, entry_date, created_at);


-- -----------------------------------------------------------------------------
-- Daily lottery draw results (27 numbers across 8 prize tiers). Shared
-- across all accounts (not user-scoped) -- one row per draw_date.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS lottery_results (
  id          TEXT PRIMARY KEY,
  draw_date   TEXT NOT NULL UNIQUE,
  dac_biet    TEXT NOT NULL,   -- JSON array, 1 number
  giai_nhat   TEXT NOT NULL,   -- JSON array, 1 number
  giai_nhi    TEXT NOT NULL,   -- JSON array, 2 numbers
  giai_ba     TEXT NOT NULL,   -- JSON array, 6 numbers
  giai_tu     TEXT NOT NULL,   -- JSON array, 4 numbers
  giai_nam    TEXT NOT NULL,   -- JSON array, 6 numbers
  giai_sau    TEXT NOT NULL,   -- JSON array, 3 numbers
  giai_bay    TEXT NOT NULL,   -- JSON array, 4 numbers
  created_at  TEXT NOT NULL,
  updated_at  TEXT NOT NULL
);


-- -----------------------------------------------------------------------------
-- Package purchases / renewals (billing history)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS transactions (
  id            TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type          TEXT NOT NULL CHECK (type IN ('purchase', 'renew')),
  package_type  TEXT NOT NULL,
  amount        INTEGER NOT NULL,
  created_at    TEXT NOT NULL
);


-- -----------------------------------------------------------------------------
-- Pending package purchase requests awaiting admin approval
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS payment_requests (
  id            TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  package_type  TEXT NOT NULL,
  amount        INTEGER NOT NULL,
  status        TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  created_at    TEXT NOT NULL,
  decided_at    TEXT,
  decided_by    TEXT REFERENCES users(id)
);


-- -----------------------------------------------------------------------------
-- System/admin broadcast messages to a user
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS messages (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  sender      TEXT NOT NULL CHECK (sender IN ('user', 'admin', 'system')),
  content     TEXT NOT NULL,
  created_at  TEXT NOT NULL
);


-- -----------------------------------------------------------------------------
-- Peer-to-peer chat between accounts
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS direct_messages (
  id            TEXT PRIMARY KEY,
  from_user_id  TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  to_user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  content       TEXT NOT NULL,
  created_at    TEXT NOT NULL,
  attachment_name TEXT,           -- chat attachment (file / image, <= 5 MB)
  attachment_type TEXT,
  attachment_size INTEGER,
  attachment_data BLOB
);

CREATE TABLE IF NOT EXISTS friendships (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  friend_id   TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at  TEXT NOT NULL,
  UNIQUE (user_id, friend_id)
);


-- -----------------------------------------------------------------------------
-- Per-account short invite/lookup code (used to add friends)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS customer_codes (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  code        TEXT NOT NULL UNIQUE,
  created_at  TEXT NOT NULL,
  label       TEXT                -- optional note on a "virtual ID" -- added via migration
);
-- Max IDs per account: settings key `max_virtual_ids` (default 5, Admin-editable).


-- -----------------------------------------------------------------------------
-- User-set deletion schedules, executed by a background Timer in the server.
--   kind 'data': one-off delete of the user's data_entries (optionally one
--                customer_name and/or entry_date range) at run_at.
--   kind 'chat': standing rule - messages (chat_scope 'all') or image
--                attachments ('images') older than ttl_seconds in the
--                conversation with friend_id are deleted for both sides.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS deletion_schedules (
  id             TEXT PRIMARY KEY,
  user_id        TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind           TEXT NOT NULL CHECK (kind IN ('data', 'chat')),
  customer_name  TEXT,
  date_from      TEXT,
  date_to        TEXT,
  friend_id      TEXT REFERENCES users(id) ON DELETE CASCADE,
  chat_scope     TEXT,
  ttl_seconds    INTEGER,
  run_at         TEXT,
  status         TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'done', 'cancelled')),
  deleted_count  INTEGER NOT NULL DEFAULT 0,
  created_at     TEXT NOT NULL,
  executed_at    TEXT
);


-- -----------------------------------------------------------------------------
-- Free-form key/value app settings
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS settings (
  key    TEXT PRIMARY KEY,
  value  TEXT NOT NULL
);

-- Read markers for the unread badges (peer_key = other user's id, or 'support'
-- for a customer's conversation with Admin). Messages older than the
-- 'unread_epoch' setting count as read when no marker exists.
CREATE TABLE IF NOT EXISTS message_reads (
  user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  peer_key     TEXT NOT NULL,
  last_read_at TEXT NOT NULL,
  PRIMARY KEY (user_id, peer_key)
);


-- -----------------------------------------------------------------------------
-- Device sessions, login throttling and security event log
-- (JWT carries device_sessions.id as the `sid` claim)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS device_sessions (
  id           TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_label TEXT,
  user_agent   TEXT,
  ip           TEXT,
  created_at   TEXT NOT NULL,
  last_seen    TEXT NOT NULL,
  revoked_at   TEXT,
  revoked_by   TEXT
);
CREATE INDEX IF NOT EXISTS idx_device_sessions_user ON device_sessions(user_id);

CREATE TABLE IF NOT EXISTS login_attempts (
  key          TEXT PRIMARY KEY,  -- "<username lowercase>|<ip>"
  fail_count   INTEGER NOT NULL DEFAULT 0,
  last_fail_at TEXT NOT NULL,
  locked_until TEXT
);

CREATE TABLE IF NOT EXISTS security_events (
  id         TEXT PRIMARY KEY,
  type       TEXT NOT NULL,       -- login_failed, login_locked, session_revoked, data_wiped
  user_id    TEXT,
  username   TEXT,
  ip         TEXT,
  detail     TEXT,                -- never a password or token
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_security_events_created ON security_events(created_at);

-- Call history (voice calls only), written by the signaling relay.
CREATE TABLE IF NOT EXISTS call_logs (
  id               TEXT PRIMARY KEY,
  caller_id        TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  callee_id        TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status           TEXT NOT NULL,   -- ringing | in_progress | completed | missed | rejected | busy | failed
  created_at       TEXT NOT NULL,
  answered_at      TEXT,
  ended_at         TEXT,
  duration_seconds INTEGER NOT NULL DEFAULT 0,
  callee_seen      INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_call_logs_caller ON call_logs(caller_id, created_at);
CREATE INDEX IF NOT EXISTS idx_call_logs_callee ON call_logs(callee_id, created_at);


-- =============================================================================
-- Handy reference queries
-- =============================================================================

-- Every account and how much of its data quota is used
-- SELECT username, role, package_type, data_used, data_quota_total, status FROM users ORDER BY created_at;

-- One account's customer roster
-- SELECT name, created_at FROM customers WHERE user_id = :userId ORDER BY name COLLATE NOCASE;

-- Entries still waiting to be scored (lottery_results exists for that date but result is still null)
-- SELECT e.* FROM data_entries e
-- JOIN lottery_results r ON r.draw_date = e.entry_date
-- WHERE e.user_id = :userId AND e.result IS NULL;

-- An account's own payout config (parse the JSON in application code)
-- SELECT scoring_rates FROM users WHERE id = :userId;
