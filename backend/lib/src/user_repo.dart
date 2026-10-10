import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/permissions.dart';
import 'package:sqlite3/sqlite3.dart';

import 'database.dart' show newId;
import 'package_plans.dart';

/// Fetches the row for the currently authenticated user, or null if the
/// account was deleted after the token was issued.
Row? loadSelfRow(RequestContext context, String userId) {
  final db = context.read<Database>();
  final rows = db.select('SELECT * FROM users WHERE id = ?', [userId]);
  return rows.isEmpty ? null : rows.first;
}

/// JSON shape for `GET /api/me` - includes the user's own quota numbers.
/// This is the ONLY place data_used/data_quota_total are exposed, and it
/// is only reachable by the user themselves (see routes/api/me/index.dart).
Map<String, dynamic> meJson(Row row) {
  final pkg = PackageType.fromWire(row['package_type'] as String);
  return {
    'id': row['id'],
    'name': row['name'],
    'username': row['username'],
    'role': row['role'],
    // Admin accounts only: the permission keys they hold (all of them for the root
    // Admin) and whether they are the root Admin.
    'permissions': effectivePermissions(row),
    'isRoot': isRootRow(row),
    'hasSecondPassword': row['second_password_hash'] != null,
    'hasWipePassword': row['wipe_password_hash'] != null,
    // Only whether a mã khôi phục exists - the code itself is stored hashed
    // and is never exposed (not here, not to admins).
    'hasRecoveryCode': row['recovery_code_hash'] != null,
    'package': {
      'type': pkg.wireValue,
      'label': pkg.label,
      'startedAt': row['package_started_at'],
      'expiresAt': row['package_expires_at'],
      'isActive': _isPackageActive(row),
    },
    'stats': {
      'total': row['data_quota_total'],
      'used': row['data_used'],
      'remaining':
          ((row['data_quota_total'] as int) - (row['data_used'] as int)).clamp(
            0,
            1 << 31,
          ),
    },
  };
}

/// JSON shape used by admin endpoints - registration/package info ONLY.
/// Deliberately excludes data_used/data_quota_total and never touches
/// data_entries: admins must not be able to see a user's entered numbers.
Map<String, dynamic> adminSubscriberJson(Row row) {
  final pkg = PackageType.fromWire(row['package_type'] as String);
  return {
    'id': row['id'],
    'name': row['name'],
    'username': row['username'],
    'package': {
      'type': pkg.wireValue,
      'label': pkg.label,
      'expiresAt': row['package_expires_at'],
    },
    'status': _isPackageActive(row) ? 'active' : 'expired',
    // Whether the ADMIN has locked this account (blocks login), separate
    // from the package active/expired 'status' above - see
    // routes/api/admin/users/[id].dart (PATCH) and routes/api/auth/login.dart.
    'accountLocked': row['status'] == 'locked',
  };
}

/// Actually grants [pkg] to [userId] - extends from the current expiry if
/// they still have an active package/trial, otherwise starts from now;
/// quota is additive, never reset. Only called from one place: an admin
/// approving a pending `payment_requests` row (see
/// routes/api/admin/payment-requests/[id]/approve.dart) - a purchase no
/// longer applies itself the moment the user asks for it.
///
/// Records the completed purchase/renewal into `transactions` at
/// [priceVnd] and returns the transaction type used ('purchase' or
/// 'renew'), only for logging/response purposes.
String applyApprovedPackage(
  Database db,
  String userId,
  PackageType pkg,
  int priceVnd,
) {
  final self = loadSelfRowById(db, userId);
  final now = DateTime.now().toUtc();
  final currentExpiry = (self['package_expires_at'] as String?) != null
      ? DateTime.parse(self['package_expires_at'] as String)
      : null;
  final hadActivePackage = currentExpiry != null && currentExpiry.isAfter(now);
  final startFrom = hadActivePackage ? currentExpiry : now;
  final plan = packagePlans[pkg]!;
  final newExpiry = startFrom.add(Duration(days: plan.durationDays));
  final txType = hadActivePackage ? 'renew' : 'purchase';

  db.execute(
    '''
    UPDATE users SET
      package_type = ?,
      package_started_at = ?,
      package_expires_at = ?,
      data_quota_total = data_quota_total + ?,
      status = 'active'
    WHERE id = ?
    ''',
    [pkg.wireValue, now.toIso8601String(), newExpiry.toIso8601String(), plan.quota, userId],
  );
  db.execute(
    'INSERT INTO transactions (id, user_id, type, package_type, amount, created_at) VALUES (?, ?, ?, ?, ?, ?)',
    [newId(), userId, txType, pkg.wireValue, priceVnd, now.toIso8601String()],
  );
  return txType;
}

Row loadSelfRowById(Database db, String userId) {
  final rows = db.select('SELECT * FROM users WHERE id = ?', [userId]);
  if (rows.isEmpty) {
    throw StateError('User $userId not found');
  }
  return rows.first;
}

bool _isPackageActive(Row row) {
  final expiresAt = row['package_expires_at'] as String?;
  if (expiresAt == null) return false;
  return DateTime.parse(expiresAt).isAfter(DateTime.now().toUtc());
}

String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}
