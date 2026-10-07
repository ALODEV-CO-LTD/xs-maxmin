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

final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

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
  int? ttl;

  if (kind == 'data') {
    customer = (body['customerName'] as String?)?.trim();
    from = (body['dateFrom'] as String?)?.trim();
    to = (body['dateTo'] as String?)?.trim();
    if (customer != null && customer.isEmpty) customer = null;
    if (from != null && from.isEmpty) from = null;
    if (to != null && to.isEmpty) to = null;
    for (final d in [from, to]) {
      if (d != null && !_datePattern.hasMatch(d)) {
        return Response.json(statusCode: 400, body: {'error': 'Ngày không hợp lệ (định dạng YYYY-MM-DD)'});
      }
    }
    if (from != null && to != null && from.compareTo(to) > 0) {
      return Response.json(statusCode: 400, body: {'error': 'Ngày bắt đầu phải trước ngày kết thúc'});
    }
    willDeleteNow = countScheduledData(db, userId, customer, from, to);
    scopeText = 'Toàn bộ số liệu đã nhập'
        '${customer != null ? ' của khách "$customer"' : ' của mọi khách'}'
        '${from != null || to != null ? ' trong khoảng ${from ?? 'đầu'} đến ${to ?? 'nay'}' : ' ở mọi ngày'}'
        ' (hiện có $willDeleteNow bản ghi khớp). Không thể hoàn tác.';
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
       ttl_seconds, run_at, status, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?)
    ''',
    [id, userId, kind, customer, from, to, friendId, chatScope, ttl, runAt.toIso8601String(), now.toIso8601String()],
  );
  final saved = db.select('SELECT * FROM deletion_schedules WHERE id = ?', [id]).first;
  return Response.json(statusCode: 201, body: scheduleJson(saved, userId, db));
}
