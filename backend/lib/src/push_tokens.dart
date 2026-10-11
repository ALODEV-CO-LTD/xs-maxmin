import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

final _hex = RegExp(r'^[0-9a-fA-F]+$');

/// APNs device tokens are hex strings; accept 32..200 chars (Apple may grow them).
bool isValidPushToken(String t) => t.length >= 32 && t.length <= 200 && _hex.hasMatch(t);

final _fcmToken = RegExp(r'^[A-Za-z0-9_:\-]+$');

/// FCM registration tokens: URL-safe characters (letters, digits, `-`, `_`, `:`),
/// 100..400 chars. Case-sensitive.
bool isValidFcmToken(String t) => t.length >= 100 && t.length <= 400 && _fcmToken.hasMatch(t);

bool isValidPushTokenFor(String platform, String t) => switch (platform) {
      'ios' => isValidPushToken(t),
      'android' => isValidFcmToken(t),
      _ => false,
    };

/// Registers [token] for [userId]. A token is unique: if it was registered for
/// another account it moves to this one.
void upsertPushToken(Database db, String userId, String platform, String token, {String? deviceLabel}) {
  final now = DateTime.now().toUtc().toIso8601String();
  final label = (deviceLabel == null || deviceLabel.isEmpty) ? null : (deviceLabel.length > 80 ? deviceLabel.substring(0, 80) : deviceLabel);
  final t = platform == 'ios' ? token.toLowerCase() : token;
  final existing = db.select('SELECT id FROM push_tokens WHERE token = ?', [t]);
  if (existing.isEmpty) {
    db.execute(
      'INSERT INTO push_tokens (id, user_id, platform, token, device_label, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [const Uuid().v4(), userId, platform, t, label, now, now],
    );
  } else {
    db.execute(
      'UPDATE push_tokens SET user_id = ?, platform = ?, device_label = ?, updated_at = ? WHERE token = ?',
      [userId, platform, label, now, t],
    );
  }
}

/// Deletes a token. With [userId] only that user's own token is removed. iOS
/// tokens are stored lower-cased; FCM tokens are case-sensitive (exact match).
bool deletePushToken(Database db, String token, {String? userId}) {
  final lower = token.toLowerCase();
  const match = "(token = ? OR (platform = 'ios' AND token = ?))";
  if (userId == null) {
    db.execute('DELETE FROM push_tokens WHERE $match', [token, lower]);
  } else {
    db.execute('DELETE FROM push_tokens WHERE $match AND user_id = ?', [token, lower, userId]);
  }
  return db.updatedRows > 0;
}

/// Tokens of [userId]; only those of [platform] when given.
List<String> pushTokensOf(Database db, String userId, {String? platform}) => [
      for (final r in platform == null
          ? db.select('SELECT token FROM push_tokens WHERE user_id = ?', [userId])
          : db.select('SELECT token FROM push_tokens WHERE user_id = ? AND platform = ?', [userId, platform]))
        r['token'] as String,
    ];

/// Creates the table (iOS + Android) or upgrades a dev DB that still has the
/// iOS-only CHECK by recreating the table and copying the rows. Idempotent.
/// A token belongs to exactly ONE user: registering it again for another
/// account moves it (UNIQUE token).
void ensurePushTokensTable(Database db) {
  db.execute('''
    CREATE TABLE IF NOT EXISTS push_tokens (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      platform TEXT NOT NULL CHECK (platform IN ('ios', 'android')),
      token TEXT NOT NULL UNIQUE,
      device_label TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
  ''');
  final sql = db.select("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'push_tokens'").first['sql'] as String;
  if (!sql.contains("'android'")) {
    db.execute('ALTER TABLE push_tokens RENAME TO push_tokens_old');
    db.execute('DROP INDEX IF EXISTS idx_push_tokens_user');
    db.execute('''
      CREATE TABLE push_tokens (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        platform TEXT NOT NULL CHECK (platform IN ('ios', 'android')),
        token TEXT NOT NULL UNIQUE,
        device_label TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    db.execute('INSERT INTO push_tokens SELECT id, user_id, platform, token, device_label, created_at, updated_at FROM push_tokens_old');
    db.execute('DROP TABLE push_tokens_old');
  }
  db.execute('CREATE INDEX IF NOT EXISTS idx_push_tokens_user ON push_tokens(user_id)');
}
