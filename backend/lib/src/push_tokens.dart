import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

final _hex = RegExp(r'^[0-9a-fA-F]+$');

/// APNs device tokens are hex strings; accept 32..200 chars (Apple may grow them).
bool isValidPushToken(String t) => t.length >= 32 && t.length <= 200 && _hex.hasMatch(t);

/// Registers [token] for [userId]. A token is unique: if it was registered for
/// another account it moves to this one.
void upsertPushToken(Database db, String userId, String platform, String token, {String? deviceLabel}) {
  final now = DateTime.now().toUtc().toIso8601String();
  final label = (deviceLabel == null || deviceLabel.isEmpty) ? null : (deviceLabel.length > 80 ? deviceLabel.substring(0, 80) : deviceLabel);
  final t = token.toLowerCase();
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

/// Deletes a token. With [userId] only that user's own token is removed.
bool deletePushToken(Database db, String token, {String? userId}) {
  final t = token.toLowerCase();
  if (userId == null) {
    db.execute('DELETE FROM push_tokens WHERE token = ?', [t]);
  } else {
    db.execute('DELETE FROM push_tokens WHERE token = ? AND user_id = ?', [t, userId]);
  }
  return db.updatedRows > 0;
}

List<String> pushTokensOf(Database db, String userId) => [
      for (final r in db.select("SELECT token FROM push_tokens WHERE user_id = ? AND platform = 'ios'", [userId])) r['token'] as String,
    ];
