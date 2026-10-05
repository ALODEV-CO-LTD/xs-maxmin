import 'dart:io';

import 'package:bcrypt/bcrypt.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import 'package_plans.dart';
import 'customer_codes.dart';
import 'deletion_scheduler.dart';

const _uuid = Uuid();

Database? _cachedDb;

/// Singleton accessor used by the root middleware so every request shares
/// the same open sqlite3 connection instead of reopening the file.
Database get appDatabase => _cachedDb ??= _openAppDatabase();

/// Opens (and if needed initializes + seeds) the SQLite database used by
/// the whole server.
Database _openAppDatabase() {
  final dataDir = Directory(p.join(Directory.current.path, 'data'));
  if (!dataDir.existsSync()) {
    dataDir.createSync(recursive: true);
  }
  final dbFile = File(p.join(dataDir.path, 'xoso.db'));
  final isNew = !dbFile.existsSync();

  final db = sqlite3.open(dbFile.path);
  db.execute('PRAGMA foreign_keys = ON;');
  _createSchema(db);
  _migrateSchema(db);
  if (isNew) {
    _seed(db);
  }
  // Admin is reached through the Phản hồi (feedback) page only, never as a
  // friend. Earlier builds friended every account with Admin (and sending
  // feedback created that link too), so clear any such rows left behind.
  _removeAdminFriendships(db);
  // Every customer gets a Mã ID so they can be found by it (see ensureCustomerCode).
  for (final u in db.select("SELECT id FROM users WHERE role = 'user'")) {
    ensureCustomerCode(db, u['id'] as String);
  }
  // Background job that carries out the deletion schedules (K35/K36/S05).
  startDeletionScheduler(db);
  return db;
}

/// Adds columns to tables that already existed before this column was
/// introduced - `CREATE TABLE IF NOT EXISTS` alone does nothing for an
/// existing table, so new nullable columns must be migrated in here.
/// Deletes every friendship row that involves an admin account. Admin talks
/// to customers only through the Phản hồi (feedback) thread, so an admin
/// should never appear in anyone's friend list, chat or call list. Idempotent
/// and cheap - it runs on every boot so a stray row can't survive a restart.
void _removeAdminFriendships(Database db) {
  db.execute(
    "DELETE FROM friendships WHERE user_id IN (SELECT id FROM users WHERE role = 'admin') "
    "OR friend_id IN (SELECT id FROM users WHERE role = 'admin')",
  );
}

void _migrateSchema(Database db) {
  _ensureColumn(db, 'data_entries', 'score', 'TEXT');
  _ensureColumn(db, 'data_entries', 'result', 'TEXT');
  // Which betting type this entry is ("de", "lo", ...) - each type has its
  // own payout rate (see users.scoring_rates below). Nullable so old rows
  // fall back to the 'de' default in the frontend.
  _ensureColumn(db, 'data_entries', 'bet_type', 'TEXT');
  // Per-user payout-rate config ("tỉ lệ ăn"): JSON object of
  // {betTypeKey: rate}, e.g. '{"de":70,"lo":20}' - each account sets its
  // own (see routes/api/me/scoring-settings), not admin-controlled. Null
  // means "use the built-in default" (same default baked into that route).
  _ensureColumn(db, 'users', 'scoring_rates', 'TEXT');
  // Chat attachments (files / images, <= 5 MB each) stored with the message.
  _ensureColumn(db, 'direct_messages', 'attachment_name', 'TEXT');
  _ensureColumn(db, 'direct_messages', 'attachment_type', 'TEXT');
  _ensureColumn(db, 'direct_messages', 'attachment_size', 'INTEGER');
  _ensureColumn(db, 'direct_messages', 'attachment_data', 'BLOB');
  // Mã khôi phục (K07/K08): only a bcrypt hash of the code is stored, never
  // the code itself (see recovery_codes.dart). The failed-attempt counter and
  // lock-until timestamp throttle guessing on /api/auth/recover. All nullable
  // / defaulted so existing accounts simply have "no code yet".
  _ensureColumn(db, 'users', 'recovery_code_hash', 'TEXT');
  _ensureColumn(db, 'users', 'recovery_code_created_at', 'TEXT');
  _ensureColumn(db, 'users', 'recovery_failed_attempts', 'INTEGER NOT NULL DEFAULT 0');
  _ensureColumn(db, 'users', 'recovery_locked_until', 'TEXT');
  // Optional label on a Mã ID ("ID ảo"), e.g. "Cho khách quen" (K23).
  _ensureColumn(db, 'customer_codes', 'label', 'TEXT');
  // Last-change timestamp of an entry (ISO-8601 UTC). The offline client
  // sends the value it last saw when it replays an edit; a mismatch means the
  // entry was changed elsewhere meanwhile (conflict, see entries/[id].dart).
  _ensureColumn(db, 'data_entries', 'updated_at', 'TEXT');
}

void _ensureColumn(Database db, String table, String column, String type) {
  final existing = db.select('PRAGMA table_info($table)').map((r) => r['name'] as String);
  if (!existing.contains(column)) {
    db.execute('ALTER TABLE $table ADD COLUMN $column $type');
  }
}

void _createSchema(Database db) {
  // Device sessions (K10/A04/A14/S04): the JWT carries the row id as `sid`;
  // a row with revoked_at set is rejected by the auth middleware.
  db.execute('''
    CREATE TABLE IF NOT EXISTS device_sessions (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      device_label TEXT,
      user_agent TEXT,
      ip TEXT,
      created_at TEXT NOT NULL,
      last_seen TEXT NOT NULL,
      revoked_at TEXT,
      revoked_by TEXT
    );
  ''');
  db.execute('CREATE INDEX IF NOT EXISTS idx_device_sessions_user ON device_sessions(user_id)');

  // Failed-login counters per account+IP with temporary lock (K03/S03).
  db.execute('''
    CREATE TABLE IF NOT EXISTS login_attempts (
      key TEXT PRIMARY KEY,
      fail_count INTEGER NOT NULL DEFAULT 0,
      last_fail_at TEXT NOT NULL,
      locked_until TEXT
    );
  ''');

  // Minimal security event log (NFR-07). Never stores passwords/tokens.
  db.execute('''
    CREATE TABLE IF NOT EXISTS security_events (
      id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      user_id TEXT,
      username TEXT,
      ip TEXT,
      detail TEXT,
      created_at TEXT NOT NULL
    );
  ''');
  db.execute('CREATE INDEX IF NOT EXISTS idx_security_events_created ON security_events(created_at)');

  db.execute('''
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      username TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL,
      second_password_hash TEXT,
      wipe_password_hash TEXT,
      role TEXT NOT NULL CHECK (role IN ('user', 'admin')),
      package_type TEXT NOT NULL DEFAULT 'none',
      package_started_at TEXT,
      package_expires_at TEXT,
      data_quota_total INTEGER NOT NULL DEFAULT 0,
      data_used INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'active',
      created_at TEXT NOT NULL
    );
  ''');

  db.execute('''
    CREATE TABLE IF NOT EXISTS data_entries (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      customer_name TEXT,
      entry_date TEXT NOT NULL,
      value TEXT NOT NULL,
      score TEXT,
      result TEXT,
      note TEXT,
      created_at TEXT NOT NULL
    );
  ''');

  db.execute('''
    CREATE TABLE IF NOT EXISTS transactions (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      type TEXT NOT NULL CHECK (type IN ('purchase', 'renew')),
      package_type TEXT NOT NULL,
      amount INTEGER NOT NULL,
      created_at TEXT NOT NULL
    );
  ''');

  db.execute('''
    CREATE TABLE IF NOT EXISTS messages (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      sender TEXT NOT NULL CHECK (sender IN ('user', 'admin', 'system')),
      content TEXT NOT NULL,
      created_at TEXT NOT NULL
    );
  ''');

  db.execute('''
    CREATE TABLE IF NOT EXISTS customer_codes (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      code TEXT NOT NULL UNIQUE,
      created_at TEXT NOT NULL
    );
  ''');

  db.execute('''
    CREATE TABLE IF NOT EXISTS settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    );
  ''');

  // A purchase/renew no longer applies instantly - the user transfers money
  // manually (bank info from `settings`, see package_plans.dart) and this
  // row sits 'pending' until an admin confirms the money arrived and
  // approves it (only then does user_repo's applyApprovedPackage touch the
  // user's package/quota and insert into `transactions`), or rejects it.
  db.execute('''
    CREATE TABLE IF NOT EXISTS payment_requests (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      package_type TEXT NOT NULL,
      amount INTEGER NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
      created_at TEXT NOT NULL,
      decided_at TEXT,
      decided_by TEXT REFERENCES users(id)
    );
  ''');

  // One row per direction (both A→B and B→A are inserted together when two
  // users become friends) so "my friends" is a single indexed lookup on
  // user_id, with no OR/UNION needed.
  db.execute('''
    CREATE TABLE IF NOT EXISTS friendships (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      friend_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TEXT NOT NULL,
      UNIQUE (user_id, friend_id)
    );
  ''');

  db.execute('''
    CREATE TABLE IF NOT EXISTS direct_messages (
      id TEXT PRIMARY KEY,
      from_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      to_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      content TEXT NOT NULL,
      created_at TEXT NOT NULL,
      attachment_name TEXT,
      attachment_type TEXT,
      attachment_size INTEGER,
      attachment_data BLOB
    );
  ''');

  // The official Miền Bắc lottery draw for one day - an objective public
  // fact, the same for every user, so unlike data_entries this is NOT
  // scoped to a user_id: whoever enters it first makes it available to
  // everyone, and anyone can correct it afterward (upsert by draw_date).
  // Each prize tier is stored as a JSON array of its numbers (as printed,
  // left-to-right/top-to-bottom) even when it only holds one value, so
  // every tier is read the same way.
  db.execute('''
    CREATE TABLE IF NOT EXISTS lottery_results (
      id TEXT PRIMARY KEY,
      draw_date TEXT NOT NULL UNIQUE,
      dac_biet TEXT NOT NULL,
      giai_nhat TEXT NOT NULL,
      giai_nhi TEXT NOT NULL,
      giai_ba TEXT NOT NULL,
      giai_tu TEXT NOT NULL,
      giai_nam TEXT NOT NULL,
      giai_sau TEXT NOT NULL,
      giai_bay TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
  ''');

  // Admin broadcast notices (bảo trì, đổi chính sách...) shown as a banner
  // to every user (A16). `active = 0` hides one without deleting it.
  db.execute('''
    CREATE TABLE IF NOT EXISTS announcements (
      id TEXT PRIMARY KEY,
      kind TEXT NOT NULL DEFAULT 'info' CHECK (kind IN ('info', 'maintenance', 'policy')),
      title TEXT NOT NULL,
      body TEXT NOT NULL DEFAULT '',
      active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      created_by TEXT REFERENCES users(id)
    );
  ''');

  // Per-customer entry-syntax template (K16): the user confirms how THIS
  // customer writes their messages (type aliases, stake markers...). `config`
  // is a JSON object. Never learned automatically - only saved on request.
  db.execute('''
    CREATE TABLE IF NOT EXISTS customer_syntax_templates (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      customer_name TEXT NOT NULL,
      config TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE (user_id, customer_name)
    );
  ''');

  // A user's own customer roster - entering data (data_entries) is meant
  // to pick a name FROM here (see routes/api/me/entries), not free-type a
  // new one each time, so a typo doesn't silently create a duplicate
  // "phantom" customer. data_entries.customer_name stays plain TEXT rather
  // than a foreign key on purpose: a customer removed from the roster
  // still keeps their historical entries readable.
  db.execute('''
    CREATE TABLE IF NOT EXISTS customers (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      created_at TEXT NOT NULL,
      UNIQUE (user_id, name)
    );
  ''');

  // User-set deletion schedules (K35/K36/S05). `kind` is 'data' (the user's
  // own saved entries, optionally narrowed by customer and/or date range) or
  // 'chat' (messages/images in one friend conversation older than
  // `ttl_seconds`, re-applied every run until cancelled). 'data' schedules
  // run once at `run_at`; `friend_id`/`ttl_seconds` apply to 'chat' only.
  db.execute('''
    CREATE TABLE IF NOT EXISTS deletion_schedules (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      kind TEXT NOT NULL CHECK (kind IN ('data', 'chat')),
      customer_name TEXT,
      date_from TEXT,
      date_to TEXT,
      friend_id TEXT REFERENCES users(id) ON DELETE CASCADE,
      chat_scope TEXT,
      ttl_seconds INTEGER,
      run_at TEXT,
      status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'done', 'cancelled')),
      deleted_count INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      executed_at TEXT
    );
  ''');
}

void _seed(Database db) {
  final now = DateTime.now().toUtc();

  String hash(String pw) => BCrypt.hashpw(pw, BCrypt.gensalt());

  final adminId = _uuid.v4();
  db.execute(
    '''
    INSERT INTO users (id, name, username, password_hash, role, package_type, status, created_at)
    VALUES (?, ?, ?, ?, 'admin', 'none', 'active', ?)
    ''',
    [adminId, 'Admin', '1', hash('1'), now.toIso8601String()],
  );

  final sampleUsers = [
    ('Nguyễn Văn A', '2', '2', PackageType.oneMonth, 15),
    ('Trần Thị Hương', 'tranthihuong', 'user123', PackageType.threeMonths, 90),
    ('Phạm Văn Long', 'phamvanlong', 'user123', PackageType.sixMonths, 180),
    ('Đỗ Ngọc Mai', 'dongocmai', 'user123', PackageType.oneMonth, 20),
    ('Hoàng Văn Tùng', 'hoangvantung', 'user123', PackageType.twelveMonths, 330),
  ];

  for (final (name, username, password, pkg, daysLeft) in sampleUsers) {
    final id = _uuid.v4();
    final plan = packagePlans[pkg]!;
    final startedAt = now.subtract(Duration(days: plan.durationDays - daysLeft));
    final expiresAt = startedAt.add(Duration(days: plan.durationDays));
    db.execute(
      '''
      INSERT INTO users (
        id, name, username, password_hash, role, package_type,
        package_started_at, package_expires_at, data_quota_total, data_used,
        status, created_at
      ) VALUES (?, ?, ?, ?, 'user', ?, ?, ?, ?, ?, 'active', ?)
      ''',
      [
        id,
        name,
        username,
        hash(password),
        pkg.wireValue,
        startedAt.toIso8601String(),
        expiresAt.toIso8601String(),
        plan.quota,
        (plan.quota * 0.68).round(),
        now.toIso8601String(),
      ],
    );
    db.execute(
      '''
      INSERT INTO transactions (id, user_id, type, package_type, amount, created_at)
      VALUES (?, ?, 'purchase', ?, ?, ?)
      ''',
      [_uuid.v4(), id, pkg.wireValue, plan.priceVnd, startedAt.toIso8601String()],
    );
  }
}

String newId() => _uuid.v4();
