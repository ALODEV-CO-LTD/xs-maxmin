import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/request_body.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/deletion_scheduler.dart';
import 'package:server/src/reauth_limit.dart';
import 'package:server/src/sessions.dart';
import 'package:server/src/user_repo.dart';
import 'package:sqlite3/sqlite3.dart';

/// POST /api/me/entries/bulk-delete - delete the CALLER's saved entries on
/// demand. Body:
///   { customerName?, dateFrom?, dateTo?, keepDays?, dryRun?, password?,
///     allDataConfirmed? }
/// * `dryRun: true` -> { count } - how many would go; deletes nothing and
///   needs no password.
/// * otherwise the account `password` is required (403 wrong, 429 locked) and
///   the response is { deleted: n }.
/// * with no limit at all (no customer, no dates, keepDays 0) the call is a
///   400 unless `allDataConfirmed: true`, so a missing field never wipes
///   everything by accident.
/// Scope = the same dataEntriesFilter the schedules use (one source of truth),
/// always restricted to the caller's user_id.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  final read = await readJsonBody(context, smallBodyMaxBytes);
  if (read.error != null) return read.error!;
  final body = read.body!;

  String? clean(Object? v) {
    final s = v is String ? v.trim() : null;
    return s == null || s.isEmpty ? null : s;
  }

  final customer = clean(body['customerName']);
  final from = clean(body['dateFrom']);
  final to = clean(body['dateTo']);
  final rawKeep = body['keepDays'];
  if (rawKeep != null && (rawKeep is! num || rawKeep != rawKeep.truncate())) {
    return Response.json(statusCode: 400, body: {'error': 'Số ngày giữ lại không hợp lệ'});
  }
  final keepDays = (rawKeep as num?)?.toInt() ?? 0;
  final scopeError = validateDataScope(from, to, keepDays);
  if (scopeError != null) return Response.json(statusCode: 400, body: {'error': scopeError});

  final limited = customer != null || from != null || to != null || keepDays > 0;
  if (!limited && body['allDataConfirmed'] != true) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Chưa chọn phạm vi xoá (khách, khoảng ngày hoặc giữ lại N ngày); xác nhận xoá toàn bộ nếu đúng ý'},
    );
  }

  final db = context.read<Database>();
  final userId = auth.userId;
  final now = DateTime.now().toUtc();

  if (body['dryRun'] == true) {
    final n = countScheduledData(db, userId, customer, from, to, keepDays: keepDays, now: now);
    return Response.json(body: {'count': n});
  }

  final self = loadSelfRow(context, userId);
  if (self == null) return unauthorized('Tài khoản không tồn tại');
  final ip = clientIp(context);
  // Shared throttle (403 wrong / 429 locked), never 401.
  final denied = checkReauthPassword(
    db,
    self,
    body['password'] as String?,
    action: 'Xoá số liệu',
    ip: ip,
    wrongMessage: 'Mật khẩu không đúng',
  );
  if (denied != null) return denied;

  final int n;
  db.execute('BEGIN IMMEDIATE');
  try {
    n = deleteDataScope(db, userId, customer, from, to, keepDays: keepDays, now: now);
    db.execute('COMMIT');
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
  logSecurityEvent(
    db,
    'entries_deleted',
    userId: userId,
    ip: ip,
    detail: 'Xoá $n bản ghi số liệu'
        '${customer != null ? ' của khách "$customer"' : ''}'
        '${from != null || to != null ? ' (${from ?? 'đầu'} đến ${to ?? 'nay'})' : ''}'
        '${keepDays > 0 ? ', giữ lại $keepDays ngày' : ''}',
  );
  return Response.json(body: {'deleted': n});
}
