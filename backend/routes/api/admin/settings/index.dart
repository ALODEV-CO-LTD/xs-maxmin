import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/permissions.dart';
import 'package:sqlite3/sqlite3.dart';

/// The only keys `settings.manage` may write or delete here: the bank-transfer info, the Mã ID cap and the legacy
/// per-package price overrides. Everything else (`policy.*` = security.policy, `maintenance_*` = maintenance.manage,
/// `app_*` = the app-version page, internal markers such as `perm_split_maintenance`) is refused. Keys are compared
/// case-insensitively and must match exactly (SQLite LIKE, used to read `policy.%`, is case-insensitive).
const editableSettingKeys = {'bank_name', 'bank_bin', 'bank_account_number', 'bank_account_holder', 'max_virtual_ids'};
final _priceKey = RegExp(r'^package_price_[a-z0-9_]{1,40}$');

bool isEditableSettingKey(String key) {
  final k = key.toLowerCase();
  return key == k && (editableSettingKeys.contains(k) || _priceKey.hasMatch(k));
}

Response? _rejectKeys(Iterable<String> keys) {
  final bad = keys.where((k) => !isEditableSettingKey(k)).toList();
  if (bad.isEmpty) return null;
  final policy = bad.any((k) => k.toLowerCase().startsWith('policy.'));
  return Response.json(
    statusCode: policy ? 403 : 400,
    body: {'error': policy ? 'Chính sách bảo mật chỉnh ở trang Chính sách bảo mật.' : 'Không được chỉnh khoá cài đặt: ${bad.take(3).join(', ')}'},
  );
}

Future<Response> onRequest(RequestContext context) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final denied = denyUnless(context, auth, 'settings.manage');
  if (denied != null) return denied;

  return switch (context.request.method) {
    HttpMethod.get => _get(context),
    HttpMethod.put => _put(context),
    HttpMethod.delete => _delete(context),
    _ => Response(statusCode: 405, body: 'Method not allowed'),
  };
}

Response _get(RequestContext context) {
  final db = context.read<Database>();
  // `policy.*` belongs to the security-policy page (its own permission) and internal
  // markers are not for editing here.
  // Internal one-time markers (unread_epoch, e2ee_friend_chat_purged, perm_split_maintenance)
  // are not settings and are hidden too.
  final rows = db.select(
    "SELECT key, value FROM settings WHERE key NOT LIKE 'policy.%' "
    "AND key NOT IN ('unread_epoch', 'e2ee_friend_chat_purged', 'perm_split_maintenance')",
  );
  return Response.json(
    body: {for (final r in rows) r['key'] as String: r['value']},
  );
}

Future<Response> _put(RequestContext context) async {
  final Map<String, dynamic> body;
  try {
    body = jsonDecode(await context.request.body()) as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Body không hợp lệ'});
  }

  // Per-account cap on Mã ID ("ID ảo", K23/A05): a whole number 1-100.
  final cap = body['max_virtual_ids'];
  if (cap != null) {
    final n = int.tryParse(cap.toString().trim());
    if (n == null || n < 1 || n > 100) {
      return Response.json(statusCode: 400, body: {'error': 'Giới hạn ID ảo phải là số nguyên từ 1 đến 100'});
    }
    body['max_virtual_ids'] = n;
  }

  final rejected = _rejectKeys(body.keys);
  if (rejected != null) return rejected;
  for (final v in body.values) {
    if ((v is! String && v is! num) || v.toString().length > 200) {
      return Response.json(statusCode: 400, body: {'error': 'Giá trị cài đặt không hợp lệ'});
    }
  }

  final db = context.read<Database>();
  for (final entry in body.entries) {
    db.execute(
      'INSERT INTO settings (key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [entry.key, entry.value.toString()],
    );
  }
  return _get(context);
}

/// Removes one or more override keys - e.g. restoring a package's price to
/// its hard-coded default after an admin override.  Body: {"keys": ["k1",
/// "k2"]}.
Future<Response> _delete(RequestContext context) async {
  final Map<String, dynamic> body;
  try {
    body = jsonDecode(await context.request.body()) as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Body không hợp lệ'});
  }

  final raw = body['keys'];
  if (raw is! List || raw.isEmpty || raw.any((k) => k is! String)) {
    return Response.json(statusCode: 400, body: {'error': 'Thiếu danh sách key cần xoá'});
  }
  final keys = raw.cast<String>();
  final rejected = _rejectKeys(keys);
  if (rejected != null) return rejected;

  final db = context.read<Database>();
  for (final key in keys) {
    db.execute('DELETE FROM settings WHERE key = ?', [key]);
  }
  return _get(context);
}
