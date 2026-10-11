import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/database.dart';
import 'package:server/src/package_plans.dart';
import 'package:server/src/permissions.dart';
import 'package:sqlite3/sqlite3.dart';

/// Package catalog (Admin, `settings.manage`).
/// GET  -> { packages: [{type, label, durationDays, priceVnd, active, sortOrder, usage}] }
/// POST { label, durationDays, priceVnd, active? } -> creates one (201).
Future<Response> onRequest(RequestContext context) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final denied = denyUnless(context, auth, 'settings.manage');
  if (denied != null) return denied;
  final db = context.read<Database>();

  if (context.request.method == HttpMethod.get) {
    return Response.json(body: {'packages': [for (final p in listPackages(db)) packageAdminJson(db, p)]});
  }
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }

  final Map<String, dynamic> body;
  try {
    body = jsonDecode(await context.request.body()) as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Body không hợp lệ'});
  }
  final fields = parsePackageFields(body, partial: false);
  if (fields.error != null) return Response.json(statusCode: 400, body: {'error': fields.error});

  final code = 'p${newId().replaceAll('-', '').substring(0, 8)}';
  final next = db.select('SELECT COALESCE(MAX(sort_order), -1) + 1 AS n FROM packages').first['n'] as int;
  db.execute(
    'INSERT INTO packages (code, label, duration_days, price_vnd, sort_order, active) VALUES (?, ?, ?, ?, ?, ?)',
    [code, fields.label, fields.durationDays, fields.priceVnd, next, (fields.active ?? true) ? 1 : 0],
  );
  return Response.json(statusCode: 201, body: packageAdminJson(db, findPackage(db, code)!));
}

/// A package plus how many accounts / requests / transactions reference it
/// (a referenced package cannot be deleted, only hidden).
Map<String, dynamic> packageAdminJson(Database db, PackageRow p) {
  int count(String table) =>
      db.select('SELECT COUNT(*) AS c FROM $table WHERE package_type = ?', [p.code]).first['c'] as int;
  return {
    ...p.toJson(),
    'usage': {
      'users': count('users'),
      'requests': count('payment_requests'),
      'transactions': count('transactions'),
    },
  };
}

class PackageFields {
  PackageFields({this.label, this.durationDays, this.priceVnd, this.active, this.error});
  final String? label;
  final int? durationDays;
  final int? priceVnd;
  final bool? active;
  final String? error;
}

/// Validates create/update input; with [partial] only the keys present are checked.
PackageFields parsePackageFields(Map<String, dynamic> body, {required bool partial}) {
  String? label;
  int? days;
  int? price;
  bool? active;
  if (!partial || body.containsKey('label')) {
    label = (body['label'] as Object?)?.toString().trim() ?? '';
    if (label.isEmpty || label.length > 60) return PackageFields(error: 'Tên gói phải từ 1 đến 60 ký tự');
  }
  if (!partial || body.containsKey('durationDays')) {
    days = int.tryParse('${body['durationDays']}');
    if (days == null || days < 1 || days > 3650) return PackageFields(error: 'Thời hạn phải từ 1 đến 3650 ngày');
  }
  if (!partial || body.containsKey('priceVnd')) {
    price = int.tryParse('${body['priceVnd']}');
    if (price == null || price < 0 || price > 1000000000) return PackageFields(error: 'Giá không hợp lệ');
  }
  if (body['active'] is bool) active = body['active'] as bool;
  return PackageFields(label: label, durationDays: days, priceVnd: price, active: active);
}
