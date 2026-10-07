import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/database.dart';
import 'package:server/src/deletion_scheduler.dart';
import 'package:server/src/reauth_limit.dart';
import 'package:server/src/sessions.dart';
import 'package:server/src/user_repo.dart';
import 'package:sqlite3/sqlite3.dart';

/// Deletion schedules (K35/K36/S05) - the user schedules the removal of
///   * `kind: 'data'`: their own saved entries (optionally one customer and/or
///     a date range), carried out once at `runAt`; or
///   * `kind: 'chat'`: messages/images older than `ttlSeconds` in one friend
///     conversation, applied continuously from `runAt` (default: now) until
///     cancelled. It affects the conversation for BOTH people.
/// A background Timer (lib/src/deletion_scheduler.dart) performs them.
///
/// GET  -> { schedules: [...] } mine, plus chat rules a friend set on a
///         conversation with me.
/// POST -> without `confirm: true` it creates nothing and returns the
///         warning ({ preview: true, scopeText, willDeleteNow, runAt, ... })
///         the app must show first; with `confirm: true` it creates the
///         schedule. 'data' also needs the account `password`.
Future<Response> onRequest(RequestContext context) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  return switch (context.request.method) {
    HttpMethod.get => _list(context, auth.userId),
    HttpMethod.post => await _create(context, auth.userId),
    _ => Response(statusCode: 405, body: 'Method not allowed'),
  };
}

Map<String, dynamic> scheduleJson(Row r, String viewerId, Database db) {
  final friendId = r['friend_id'] as String?;
  String? friendName;
  if (friendId != null) {
    final otherId = r['user_id'] == viewerId ? friendId : r['user_id'] as String;
    final f = db.select('SELECT name FROM users WHERE id = ?', [otherId]);
    friendName = f.isEmpty ? null : f.first['name'] as String;
  }
  return {
    'id': r['id'],
    'kind': r['kind'],
    'customerName': r['customer_name'],
    'dateFrom': r['date_from'],
    'dateTo': r['date_to'],
    'friendId': friendId == null ? null : (r['user_id'] == viewerId ? friendId : r['user_id']),
    'friendName': friendName,
    'chatScope': r['chat_scope'],
    'ttlSeconds': r['ttl_seconds'],
    'runAt': r['run_at'],
    'status': r['status'],
    'deletedCount': r['deleted_count'],
    'createdAt': r['created_at'],
    'executedAt': r['executed_at'],
    'setByMe': r['user_id'] == viewerId,
    // Recurring 'data' schedules (null repeat = one-off).
    'repeat': r['repeat_every'] == null ? null : {'every': r['repeat_every'], 'unit': r['repeat_unit']},
    'keepDays': r['keep_days'] ?? 0,
    'runCount': r['run_count'] ?? 0,
    'nextRunAt': r['status'] == 'pending' ? r['run_at'] : null,
    'lastRunAt': r['executed_at'],
  };
}

Response _list(RequestContext context, String userId) {
  final db = context.read<Database>();
  final rows = db.select(
    '''
    SELECT * FROM deletion_schedules
    WHERE status != 'cancelled' AND (user_id = ? OR (kind = 'chat' AND friend_id = ?))
    ORDER BY created_at DESC
    LIMIT 100
    ''',
    [userId, userId],
  );
  return Response.json(body: {'schedules': [for (final r in rows) scheduleJson(r, userId, db)]});
}

/// "dd/MM/yyyy HH:mm" in Vietnam time.
String _vnText(DateTime t) {
  final v = t.toUtc().add(vietnamOffset);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(v.day)}/${two(v.month)}/${v.year} ${two(v.hour)}:${two(v.minute)}';
}

String _ttlText(int s) => switch (s) {
      3600 => '1 giờ',
      86400 => '1 ngày',
      604800 => '7 ngày',
      2592000 => '30 ngày',
      _ => '$s giây',
    };

Future<Response> _create(RequestContext context, String userId) async {
  final Map<String, dynamic> body;
  try {
    body = jsonDecode(await context.request.body()) as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Body không hợp lệ'});
  }
  final db = context.read<Database>();
  final kind = body['kind'];
  final confirm = body['confirm'] == true;
  final now = DateTime.now().toUtc();

  DateTime runAt = now;
  final runAtRaw = body['runAt'];
  if (runAtRaw is String && runAtRaw.isNotEmpty) {
    final parsed = DateTime.tryParse(runAtRaw);
    if (parsed == null) return Response.json(statusCode: 400, body: {'error': 'Thời điểm không hợp lệ'});
    runAt = parsed.toUtc();
  } else if (kind == 'data') {
    return Response.json(statusCode: 400, body: {'error': 'Vui lòng chọn thời điểm xoá'});
  }
  if (kind == 'data' && runAt.isBefore(now.subtract(const Duration(minutes: 1)))) {
    return Response.json(statusCode: 400, body: {'error': 'Thời điểm xoá phải ở tương lai'});
  }
  if (runAt.isAfter(now.add(const Duration(days: 366)))) {
    return Response.json(statusCode: 400, body: {'error': 'Thời điểm xoá quá xa (tối đa 1 năm)'});
  }

  final String scopeText;
  final int willDeleteNow;
  String? customer, from, to, friendId, chatScope;
  int? ttl, repeatEvery;
  String? repeatUnit;
  var keepDays = 0;

  if (kind != 'data' && (body['repeat'] != null || body['keepDays'] != null)) {
    return Response.json(statusCode: 400, body: {'error': 'Chỉ lịch xoá số liệu mới có lặp lại / giữ lại N ngày'});
  }

  if (kind == 'data') {
    customer = (body['customerName'] as String?)?.trim();
    from = (body['dateFrom'] as String?)?.trim();
    to = (body['dateTo'] as String?)?.trim();
    if (customer != null && customer.isEmpty) customer = null;
    if (from != null && from.isEmpty) from = null;
    if (to != null && to.isEmpty) to = null;
    final rawKeep = body['keepDays'];
    if (rawKeep != null && (rawKeep is! num || rawKeep != rawKeep.truncate())) {
      return Response.json(statusCode: 400, body: {'error': 'Số ngày giữ lại không hợp lệ'});
    }
    keepDays = (rawKeep as num?)?.toInt() ?? 0;
    final rawRepeat = body['repeat'];
    if (rawRepeat != null) {
      if (rawRepeat is! Map) {
        return Response.json(statusCode: 400, body: {'error': 'Chu kỳ lặp không hợp lệ'});
      }
      final every = rawRepeat['every'];
      final unit = rawRepeat['unit'];
      if (every is! num || every != every.truncate() || every < 1 || every > 365 ||
          (unit != 'day' && unit != 'week' && unit != 'month')) {
        return Response.json(
          statusCode: 400,
          body: {'error': 'Chu kỳ lặp không hợp lệ (mỗi 1-365 ngày/tuần/tháng)'},
        );
      }
      if (from != null || to != null) {
        return Response.json(
          statusCode: 400,
          body: {'error': 'Lịch lặp lại không dùng khoảng ngày; hãy dùng "giữ lại N ngày gần nhất"'},
        );
      }
      repeatEvery = every.toInt();
      repeatUnit = unit as String;
    }
    final scopeError = validateDataScope(from, to, keepDays);
    if (scopeError != null) return Response.json(statusCode: 400, body: {'error': scopeError});
    willDeleteNow = countScheduledData(db, userId, customer, from, to, keepDays: keepDays, now: now);
    final unitText = switch (repeatUnit) { 'week' => 'tuần', 'month' => 'tháng', _ => 'ngày' };
    scopeText = 'Toàn bộ số liệu đã nhập'
        '${customer != null ? ' của khách "$customer"' : ' của mọi khách'}'
        '${from != null || to != null ? ' trong khoảng ${from ?? 'đầu'} đến ${to ?? 'nay'}' : ' ở mọi ngày'}'
        '${keepDays > 0 ? ', giữ lại $keepDays ngày gần nhất' : ''}'
        '${repeatEvery != null ? ', lặp lại mỗi ${repeatEvery == 1 ? '' : '$repeatEvery '}$unitText, lần đầu lúc ${_vnText(runAt)} (giờ Việt Nam)' : ''}'
        ' (nếu xoá ngay bây giờ sẽ xoá $willDeleteNow bản ghi). Không thể hoàn tác.';
  } else if (kind == 'chat') {
    friendId = body['friendId'] as String?;
    ttl = body['ttlSeconds'] is num ? (body['ttlSeconds'] as num).toInt() : null;
    chatScope = body['chatScope'] as String? ?? 'all';
    if (friendId == null) return Response.json(statusCode: 400, body: {'error': 'Thiếu người bạn'});
    if (ttl == null || !allowedChatTtlSeconds.contains(ttl)) {
      return Response.json(statusCode: 400, body: {'error': 'Thời gian tự xoá không hợp lệ'});
    }
    if (chatScope != 'all' && chatScope != 'images') {
      return Response.json(statusCode: 400, body: {'error': 'Phạm vi xoá không hợp lệ'});
    }
    final isFriend = db.select(
      'SELECT 1 FROM friendships WHERE user_id = ? AND friend_id = ?',
      [userId, friendId],
    ).isNotEmpty;
    if (!isFriend) return Response.json(statusCode: 404, body: {'error': 'Không phải bạn bè'});
    final friendName = db.select('SELECT name FROM users WHERE id = ?', [friendId]).first['name'];
    final cutoff = runAt.subtract(Duration(seconds: ttl)).toIso8601String();
    willDeleteNow = countChatBefore(db, userId, friendId, chatScope, cutoff);
    scopeText = '${chatScope == 'images' ? 'Ảnh' : 'Tin nhắn và tệp đính kèm'} '
        'cũ hơn ${_ttlText(ttl)} trong cuộc trò chuyện với "$friendName" sẽ bị xoá tự động và liên tục, '
        'phía CẢ HAI người (hiện có $willDeleteNow mục sẽ bị xoá ngay khi áp dụng). Không thể hoàn tác.';
  } else {
    return Response.json(statusCode: 400, body: {'error': 'Loại lịch xoá không hợp lệ'});
  }

  final preview = {
    'preview': true,
    'kind': kind,
    'scopeText': scopeText,
    'willDeleteNow': willDeleteNow,
    'runAt': runAt.toIso8601String(),
    if (kind == 'data') ...{
      'repeat': repeatEvery == null ? null : {'every': repeatEvery, 'unit': repeatUnit},
      'keepDays': keepDays,
      'firstRunAt': runAt.toIso8601String(),
    },
  };
  if (!confirm) return Response.json(body: preview);

  if (kind == 'data') {
    final self = loadSelfRow(context, userId);
    if (self == null) return unauthorized('Tài khoản không tồn tại');
    // Shared throttle (403 wrong / 429 locked), never 401.
    final denied = checkReauthPassword(
      db,
      self,
      body['password'] as String?,
      action: 'Lịch xoá dữ liệu',
      ip: clientIp(context),
      wrongMessage: 'Mật khẩu không đúng',
    );
    if (denied != null) return denied;
  } else {
    // One rule per conversation: a new one replaces whatever either friend set.
    db.execute(
      '''
      UPDATE deletion_schedules SET status = 'cancelled'
      WHERE kind = 'chat' AND status = 'pending'
        AND ((user_id = ? AND friend_id = ?) OR (user_id = ? AND friend_id = ?))
      ''',
      [userId, friendId, friendId, userId],
    );
  }

  final id = newId();
  db.execute(
    '''
    INSERT INTO deletion_schedules
      (id, user_id, kind, customer_name, date_from, date_to, friend_id, chat_scope,
       ttl_seconds, run_at, status, created_at, repeat_every, repeat_unit, keep_days, first_run_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?, ?, ?)
    ''',
    [
      id, userId, kind, customer, from, to, friendId, chatScope, ttl,
      runAt.toIso8601String(), now.toIso8601String(),
      repeatEvery, repeatUnit, keepDays, kind == 'data' ? runAt.toIso8601String() : null,
    ],
  );
  if (kind == 'data') {
    logSecurityEvent(
      db,
      'deletion_scheduled',
      userId: userId,
      ip: clientIp(context),
      detail: repeatEvery == null ? 'Đặt lịch xoá số liệu một lần' : 'Đặt lịch xoá số liệu lặp mỗi $repeatEvery $repeatUnit',
    );
  }
  final saved = db.select('SELECT * FROM deletion_schedules WHERE id = ?', [id]).first;
  return Response.json(statusCode: 201, body: scheduleJson(saved, userId, db));
}
