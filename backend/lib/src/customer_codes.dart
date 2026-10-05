import 'dart:math';

import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

final _random = Random.secure();
const _uuid = Uuid();

/// Length of the numeric "Mã ID" a customer hands out to be added as a friend.
const customerCodeLength = 6;

/// A fresh numeric code, unique across every user's codes, so it is safe to
/// hand to someone else without colliding with anyone else's.
String generateUniqueCustomerCode(Database db) {
  final max = pow(10, customerCodeLength).toInt();
  while (true) {
    final code = _random.nextInt(max).toString().padLeft(customerCodeLength, '0');
    if (db.select('SELECT 1 FROM customer_codes WHERE code = ?', [code]).isEmpty) {
      return code;
    }
  }
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
  final step = d[1] - d[0];
  if ((step == 1 || step == -1) && [for (var i = 1; i < d.length; i++) d[i] - d[i - 1]].every((x) => x == step)) {
    return 'Mã ID quá dễ đoán (dãy số tăng/giảm dần)';
  }
  for (var n = 1; n <= d.length ~/ 2; n++) {
    if (d.length % n == 0 && [for (var i = n; i < d.length; i++) d[i] == d[i - n]].every((x) => x)) {
      return 'Mã ID quá dễ đoán (lặp lại một cụm số)';
    }
  }
  return null;
}
