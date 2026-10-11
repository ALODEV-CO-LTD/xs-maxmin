import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/package_plans.dart';
import 'package:server/src/permissions.dart';
import 'package:sqlite3/sqlite3.dart';

import 'index.dart' show packageAdminJson, parsePackageFields;

/// PATCH { label?, durationDays?, priceVnd?, active? } -> the updated package.
///   Changing price/duration only affects FUTURE requests: an existing request keeps
///   the amount it was made with.
/// DELETE -> removes it, but only when no account, request or transaction uses it
///   (otherwise 409: hide it with `active: false` instead).
Future<Response> onRequest(RequestContext context, String code) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final denied = denyUnless(context, auth, 'settings.manage');
  if (denied != null) return denied;
  final db = context.read<Database>();

  final pkg = findPackage(db, code);
  if (pkg == null) return Response.json(statusCode: 404, body: {'error': 'Không tìm thấy gói'});

  switch (context.request.method) {
    case HttpMethod.patch:
      final Map<String, dynamic> body;
      try {
        body = jsonDecode(await context.request.body()) as Map<String, dynamic>;
      } catch (_) {
        return Response.json(statusCode: 400, body: {'error': 'Body không hợp lệ'});
      }
      final f = parsePackageFields(body, partial: true);
      if (f.error != null) return Response.json(statusCode: 400, body: {'error': f.error});
      db.execute(
        'UPDATE packages SET label = ?, duration_days = ?, price_vnd = ?, active = ? WHERE code = ?',
        [
          f.label ?? pkg.label,
          f.durationDays ?? pkg.durationDays,
          f.priceVnd ?? pkg.priceVnd,
          (f.active ?? pkg.active) ? 1 : 0,
          code,
        ],
      );
      return Response.json(body: packageAdminJson(db, findPackage(db, code)!));
    case HttpMethod.delete:
      final usage = (packageAdminJson(db, pkg)['usage'] as Map<String, dynamic>).values.cast<int>().fold(0, (a, b) => a + b);
      if (usage > 0) {
        return Response.json(
          statusCode: 409,
          body: {'error': 'Gói đã có tài khoản hoặc giao dịch sử dụng nên không thể xoá. Hãy ẩn gói để ngừng bán.'},
        );
      }
      db.execute('DELETE FROM packages WHERE code = ?', [code]);
      return Response.json(body: {'ok': true});
    default:
      return Response(statusCode: 405, body: 'Method not allowed');
  }
}
