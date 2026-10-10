import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/security.dart';
import 'package:sqlite3/sqlite3.dart';

/// Multi-level Admin (A07). An account with `role = 'admin'` is either
///  - the root Admin: `users.staff_permissions IS NULL` - every permission,
///    and the only one that can manage staff accounts; or
///  - a staff account (e.g. chăm sóc khách hàng, quản lý hệ thống): the same
///    role with an explicit list of permission keys ticked by the root Admin.
/// The role column keeps its CHECK ('user' | 'admin'), so staff is expressed
/// by this list. Permissions are read from the database on every request, so
/// removing one (or locking the account) takes effect immediately.
const adminPermissions = <String, String>{
  'users.view': 'Xem danh sách và thông tin khách hàng',
  'users.lock': 'Khoá/mở khoá tài khoản khách, thu hồi phiên đăng nhập',
  'users.recovery': 'Hỗ trợ khôi phục tài khoản (duyệt yêu cầu, đặt lại mật khẩu, cấp lại mã khôi phục, gỡ khoá đăng nhập)',
  'users.delete': 'Xoá vĩnh viễn tài khoản khách và dữ liệu của họ',
  'support.messages': 'Xem và trả lời phản hồi của khách',
  'payments.manage': 'Duyệt/từ chối thanh toán, xem gia hạn và doanh thu',
  'stats.view': 'Xem thống kê hệ thống',
  'announcements.manage': 'Đăng thông báo và bảo trì',
  'settings.manage': 'Cài đặt hệ thống (ngân hàng, giá gói)',
  'backups.manage': 'Sao lưu và tải cơ sở dữ liệu',
  'security.view': 'Xem nhật ký bảo mật',
  'security.policy': 'Cấu hình chính sách bảo mật (số lần nhập sai, thời gian khoá, thời hạn đăng nhập, đóng dấu màn hình)',
};

/// Permission keys of an account row; `null` = root Admin (everything).
List<String>? permissionsOf(Row user) {
  final raw = user['staff_permissions'] as String?;
  if (raw == null) return null;
  try {
    return [for (final p in jsonDecode(raw) as List) p.toString()].where(adminPermissions.containsKey).toList();
  } catch (_) {
    return const [];
  }
}

/// True for the root Admin (the only role allowed to manage staff).
bool isRootRow(Row user) => user['role'] == 'admin' && user['staff_permissions'] == null;

/// The permission list as sent to clients: every key for the root Admin.
List<String> effectivePermissions(Row user) =>
    user['role'] != 'admin' ? const [] : (permissionsOf(user) ?? adminPermissions.keys.toList());

/// Returns a 403/401 response unless the caller is an admin account that holds
/// [permission]; null means "allowed, carry on".
Response? denyUnless(RequestContext context, AuthTokenPayload auth, String permission) {
  if (auth.role != 'admin') return forbidden();
  final rows = context.read<Database>().select('SELECT * FROM users WHERE id = ?', [auth.userId]);
  if (rows.isEmpty) return unauthorized();
  final granted = permissionsOf(rows.first);
  if (granted == null || granted.contains(permission)) return null;
  return forbidden('Tài khoản của bạn chưa được cấp quyền này. Hãy liên hệ Admin.');
}

/// Only the root Admin (managing staff accounts and their permissions).
Response? denyUnlessRoot(RequestContext context, AuthTokenPayload auth) {
  if (auth.role != 'admin') return forbidden();
  final rows = context.read<Database>().select('SELECT * FROM users WHERE id = ?', [auth.userId]);
  if (rows.isEmpty) return unauthorized();
  return isRootRow(rows.first) ? null : forbidden('Chỉ Admin gốc được quản lý phân quyền.');
}

/// Admin accounts that may handle customer support (root + staff holding
/// `support.messages`); a new customer message is pushed to all of them.
List<String> supportAdminIds(Database db) {
  final out = <String>[];
  for (final r in db.select("SELECT * FROM users WHERE role = 'admin' AND status != 'locked'")) {
    final p = permissionsOf(r);
    if (p == null || p.contains('support.messages')) out.add(r['id'] as String);
  }
  return out;
}
