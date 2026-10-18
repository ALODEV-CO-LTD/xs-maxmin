import 'dart:math';

import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

final _random = Random.secure();
const _uuid = Uuid();

/// Length of the numeric "Mã ID" a customer hands out to be added as a friend.
const customerCodeLength = 6;

/// A fresh numeric code, unique across every user's codes, not quarantined
/// (see [retiredCodeConflict]) and not guessable (passes [validateCustomCode]),
/// so it is safe to hand to someone else.
String generateUniqueCustomerCode(Database db) {
  final max = pow(10, customerCodeLength).toInt();
  while (true) {
    final code = _random.nextInt(max).toString().padLeft(customerCodeLength, '0');
    if (validateCustomCode(code) != null) continue;
    if (db.select('SELECT 1 FROM customer_codes WHERE code = ?', [code]).isNotEmpty) continue;
    // An auto-generated code never reuses a quarantined one, not even for its old owner.
    if (db.select('SELECT 1 FROM retired_codes WHERE code = ? AND retired_at > ?', [code, _quarantineCutoff()]).isNotEmpty) {
      continue;
    }
    return code;
  }
}

/// A deleted Mã ID stays reserved for this long: friend requests / lookups
/// aimed at the old owner must never land on whoever grabs the number next.
const retiredCodeQuarantine = Duration(days: 90);

String _quarantineCutoff() => DateTime.now().toUtc().subtract(retiredCodeQuarantine).toIso8601String();

/// Notes that somebody found [code] (add-friend or search), so deleting it later quarantines the number.
void markCodeUsed(Database db, String code) {
  db.execute(
    'UPDATE customer_codes SET used_at = ? WHERE code = ? AND used_at IS NULL',
    [DateTime.now().toUtc().toIso8601String(), code],
  );
}

/// Records [code] as just removed from [userId] (called when a Mã ID is deleted).
void retireCode(Database db, String code, String userId) {
  db.execute(
    'INSERT OR REPLACE INTO retired_codes (code, user_id, retired_at) VALUES (?, ?, ?)',
    [code, userId, DateTime.now().toUtc().toIso8601String()],
  );
}

/// Vietnamese error if [code] is quarantined and [userId] is not its previous
/// owner, else null. The previous owner may take their own number back.
String? retiredCodeConflict(Database db, String code, String userId) {
  final rows = db.select('SELECT user_id FROM retired_codes WHERE code = ? AND retired_at > ?', [code, _quarantineCutoff()]);
  if (rows.isEmpty || rows.first['user_id'] == userId) return null;
  return 'Mã này vừa được gỡ khỏi một tài khoản, chưa thể dùng lại trong 90 ngày';
}

/// Makes sure [userId] has at least one Mã ID. Every customer needs an ID to
/// be findable ("tìm bạn bè qua ID"); before this, a code only existed after
/// the customer went to Tài khoản and pressed "Tạo mã mới", so most accounts
/// had no ID at all. Never creates a second one for an account that has any.
void ensureCustomerCode(Database db, String userId) {
  if (db.select('SELECT 1 FROM customer_codes WHERE user_id = ? LIMIT 1', [userId]).isNotEmpty) return;
  db.execute(
    'INSERT INTO customer_codes (id, user_id, code, created_at) VALUES (?, ?, ?, ?)',
    [_uuid.v4(), userId, generateUniqueCustomerCode(db), DateTime.now().toUtc().toIso8601String()],
  );
}

/// Bounds for a Mã ID the customer picks for themselves (K22).
const customCodeMinLength = 6;
const customCodeMaxLength = 12;

/// How many Mã ID ("ID ảo") one account may hold when Admin hasn't set
/// `settings.max_virtual_ids` (K23/A05).
const defaultMaxCustomerCodes = 5;

/// Admin-configurable cap on Mã IDs per account (`settings.max_virtual_ids`).
int maxCustomerCodes(Database db) {
  final rows = db.select('SELECT value FROM settings WHERE key = ?', ['max_virtual_ids']);
  if (rows.isEmpty) return defaultMaxCustomerCodes;
  final n = int.tryParse(rows.first['value'] as String);
  return n == null || n < 1 ? defaultMaxCustomerCodes : n;
}

/// Why a hand-picked Mã ID is not acceptable, or null if it is fine: wrong
/// length / non-digits, or too guessable (one repeated digit like 111111,
/// a straight run like 123456 / 654321, or a short block repeated like
/// 121212 / 123123). Uniqueness is checked separately against the database.
String? validateCustomCode(String code) {
  if (!RegExp(r'^\d+$').hasMatch(code)) return 'Mã ID chỉ được gồm chữ số';
  if (code.length < customCodeMinLength || code.length > customCodeMaxLength) {
    return 'Mã ID phải dài từ $customCodeMinLength đến $customCodeMaxLength chữ số';
  }
  final d = code.codeUnits.map((c) => c - 48).toList();
  if (d.every((x) => x == d.first)) return 'Mã ID quá dễ đoán (lặp một chữ số)';
  final counts = List.filled(10, 0);
  for (final x in d) {
    counts[x]++;
  }
  if (counts.any((n) => n >= 5)) return 'Mã ID quá dễ đoán (có từ 5 chữ số giống nhau)';
  if (code.endsWith('0000')) return 'Mã ID quá dễ đoán (kết thúc bằng nhiều số 0)';
  if (code == code.split('').reversed.join()) return 'Mã ID quá dễ đoán (số đối xứng)';
  final step = d[1] - d[0];
  if ([for (var i = 1; i < d.length; i++) d[i] - d[i - 1]].every((x) => x == step)) {
    return 'Mã ID quá dễ đoán (dãy số tăng/giảm đều)';
  }
  for (var n = 1; n <= d.length ~/ 2; n++) {
    if (d.length % n == 0 && [for (var i = n; i < d.length; i++) d[i] == d[i - n]].every((x) => x)) {
      return 'Mã ID quá dễ đoán (lặp lại một cụm số)';
    }
  }
  return null;
}
