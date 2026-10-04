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
