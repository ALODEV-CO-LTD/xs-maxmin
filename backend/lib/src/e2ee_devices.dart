import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

/// One public key per DEVICE of a user (docs/MA_HOA_2_DAU.md). A person who uses the app on a phone and a tablet has two key
/// pairs; the sender encrypts the message once for each device, so neither device overwrites the other's key (they did when
/// the account had a single key: every launch of the "other" device replaced it and friends saw "key changed" again and again).
///
/// [legacyDeviceId] stands for the single key older app versions publish with `PUT /me/e2ee-key`.
const legacyDeviceId = 'legacy';

/// At most this many devices per account: a sender encrypts once per device, so the list must stay small. When a new device
/// registers beyond it, the one not seen for the longest time is dropped.
const maxDevicesPerUser = 6;

/// What a client may use as its device id (random, made on the device). `legacy` is reserved.
final deviceIdPattern = RegExp(r'^[A-Za-z0-9_-]{8,64}$');

const e2eeDevicesDdl = '''
  CREATE TABLE IF NOT EXISTS e2ee_devices (
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL,
    public_key TEXT NOT NULL,
    created_at TEXT NOT NULL,
    last_seen TEXT NOT NULL,
    PRIMARY KEY (user_id, device_id)
  )
''';

String _now() => DateTime.now().toUtc().toIso8601String();

/// Creates the table and gives every account that already has a single key a `legacy` device with it. Safe to run again.
void ensureE2eeDevicesTable(Database db) {
  db.execute(e2eeDevicesDdl);
  final cols = db.select('PRAGMA table_info(users)').map((r) => r['name'] as String);
  if (!cols.contains('e2ee_public_key')) return;
  db.execute(
    '''
    INSERT OR IGNORE INTO e2ee_devices (user_id, device_id, public_key, created_at, last_seen)
    SELECT id, '$legacyDeviceId', e2ee_public_key, ?, ? FROM users WHERE e2ee_public_key IS NOT NULL
    ''',
    [_now(), _now()],
  );
}

/// Publishes or refreshes [deviceId]'s key of [userId]. `users.e2ee_public_key` follows the newest key, which is what older app
/// versions (one key per account) read from the friend list. Returns true when the key is new or changed.
bool upsertDevice(Database db, String userId, String deviceId, Map<String, String> key) {
  final json = jsonEncode(key);
  final now = _now();
  final old = db.select('SELECT public_key FROM e2ee_devices WHERE user_id = ? AND device_id = ?', [userId, deviceId]);
  final changed = old.isEmpty || old.first['public_key'] != json;
  if (old.isEmpty) {
    db.execute('INSERT INTO e2ee_devices (user_id, device_id, public_key, created_at, last_seen) VALUES (?, ?, ?, ?, ?)', [userId, deviceId, json, now, now]);
  } else {
    db.execute('UPDATE e2ee_devices SET public_key = ?, last_seen = ? WHERE user_id = ? AND device_id = ?', [json, now, userId, deviceId]);
  }
  // beyond the limit: drop the devices not seen for the longest time (never the one that just registered)
  final extra = db.select(
    'SELECT device_id FROM e2ee_devices WHERE user_id = ? AND device_id != ? ORDER BY last_seen DESC LIMIT -1 OFFSET ?',
    [userId, deviceId, maxDevicesPerUser - 1],
  );
  for (final r in extra) {
    db.execute('DELETE FROM e2ee_devices WHERE user_id = ? AND device_id = ?', [userId, r['device_id']]);
  }
  if (changed) db.execute('UPDATE users SET e2ee_public_key = ? WHERE id = ?', [json, userId]);
  return changed;
}

/// Removes one device. When it held the key older clients read, that follows the newest remaining device (or goes empty).
bool removeDevice(Database db, String userId, String deviceId) {
  final had = db.select('SELECT 1 FROM e2ee_devices WHERE user_id = ? AND device_id = ?', [userId, deviceId]).isNotEmpty;
  if (!had) return false;
  db.execute('DELETE FROM e2ee_devices WHERE user_id = ? AND device_id = ?', [userId, deviceId]);
  final newest = db.select('SELECT public_key FROM e2ee_devices WHERE user_id = ? ORDER BY last_seen DESC LIMIT 1', [userId]);
  db.execute('UPDATE users SET e2ee_public_key = ? WHERE id = ?', [newest.isEmpty ? null : newest.first['public_key'], userId]);
  return true;
}

/// The devices of [userId], newest registration first: `{id, publicKey, createdAt, lastSeen}`.
List<Map<String, dynamic>> devicesOf(Database db, String userId) => [
      for (final r in db.select('SELECT device_id, public_key, created_at, last_seen FROM e2ee_devices WHERE user_id = ? ORDER BY last_seen DESC', [userId]))
        {'id': r['device_id'], 'publicKey': jsonDecode(r['public_key'] as String), 'createdAt': r['created_at'], 'lastSeen': r['last_seen']},
    ];

/// The same, only what a friend needs to encrypt to each device: `{id, publicKey}`.
List<Map<String, dynamic>> friendDevices(Database db, String userId) => [
      for (final d in devicesOf(db, userId)) {'id': d['id'], 'publicKey': d['publicKey']},
    ];
