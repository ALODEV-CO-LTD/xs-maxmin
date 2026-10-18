import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/request_body.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/database.dart';
import 'package:server/src/lottery_stations.dart';
import 'package:server/src/entry_list.dart';
import 'package:server/src/user_repo.dart';
import 'package:sqlite3/sqlite3.dart';

Future<Response> onRequest(RequestContext context) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  return switch (context.request.method) {
    HttpMethod.get => _list(context, auth.userId),
    HttpMethod.post => _create(context, auth.userId),
    _ => Response(statusCode: 405, body: 'Method not allowed'),
  };
}

Response _list(RequestContext context, String userId) {
  final db = context.read<Database>();
  // Paged: ?limit= (default 500, max 1000) & ?offset=. `hasMore` tells the
  // client to fetch the next page (frontend loadAllEntries does that).
  final q = context.request.uri.queryParameters;
  final page = listEntriesPage(db, userId, limitParam: q['limit'], offsetParam: q['offset']);
  return Response.json(
    body: {
      'entries': [for (final r in page.rows) _entryJson(r)],
      'total': page.total,
      'offset': page.offset,
      'hasMore': page.offset + page.rows.length < page.total,
    },
  );
}

Future<Response> _create(RequestContext context, String userId) async {
  final read = await readJsonBody(context, smallBodyMaxBytes);
  if (read.error != null) return read.error!;
  final body = read.body!;
  final badText = checkTextFields(body, entryTextLimits);
  if (badText != null) return badText;

  final value = (body['value'] as String?)?.trim();
  final note = (body['note'] as String?)?.trim();
  final customerName = (body['customerName'] as String?)?.trim();
  final score = (body['score'] as String?)?.trim();
  final result = (body['result'] as String?)?.trim();
  final betType = (body['betType'] as String?)?.trim();
  final station = _station(body['station']);
  if (value == null || value.isEmpty) {
    return Response.json(statusCode: 400, body: {'error': 'Vui lòng nhập số liệu'});
  }
  if (customerName == null || customerName.isEmpty) {
    return Response.json(statusCode: 400, body: {'error': 'Vui lòng nhập tên khách hàng'});
  }

  final now = DateTime.now().toUtc();
  final requestedDate = (body['entryDate'] as String?)?.trim();
  String entryDate;
  if (requestedDate == null || requestedDate.isEmpty) {
    entryDate = vietnamToday(now); // not the UTC date: 0-7h in Vietnam is still "yesterday" in UTC
  } else {
    try {
      entryDate = DateTime.parse(requestedDate).toIso8601String().substring(0, 10);
    } catch (_) {
      return Response.json(statusCode: 400, body: {'error': 'Ngày không hợp lệ'});
    }
  }

  // Offline queue replay: the client picks the id up front so a retry after a
  // lost response can't create a duplicate - an existing row with the same id
  // (same user) is simply returned again.
  final clientId = (body['clientId'] as String?)?.trim();
  final hasClientId = clientId != null && RegExp(r'^[A-Za-z0-9-]{8,64}$').hasMatch(clientId);
  if (hasClientId) {
    final dup = context.read<Database>().select('SELECT * FROM data_entries WHERE id = ?', [clientId]);
    if (dup.isNotEmpty) {
      final r = dup.first;
      if (r['user_id'] != userId) {
        return Response.json(statusCode: 409, body: {'error': 'Mã bản ghi đã tồn tại'});
      }
      return Response.json(body: _entryJson(r));
    }
  }

  final self = loadSelfRow(context, userId);
  if (self == null) return unauthorized('Tài khoản không tồn tại');

  final expiresAt = self['package_expires_at'] as String?;
  final isActive =
      expiresAt != null && DateTime.parse(expiresAt).isAfter(DateTime.now().toUtc());
  if (!isActive) {
    return Response.json(
      statusCode: 403,
      body: {'error': 'Gói đã hết hạn, vui lòng gia hạn để tiếp tục nhập số liệu'},
    );
  }

  final quotaTotal = self['data_quota_total'] as int;
  final quotaUsed = self['data_used'] as int;
  if (quotaUsed >= quotaTotal) {
    return Response.json(
      statusCode: 403,
      body: {'error': 'Đã dùng hết số liệu của gói hiện tại'},
    );
  }

  final db = context.read<Database>();
  final id = hasClientId ? clientId : newId();
  final createdAt = now.toIso8601String();
  db.execute(
    '''
    INSERT INTO data_entries (id, user_id, customer_name, entry_date, value, score, result, bet_type, station, note, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    [id, userId, customerName, entryDate, value, score, result, betType, station, note, createdAt, createdAt],
  );
  db.execute('UPDATE users SET data_used = data_used + 1 WHERE id = ?', [userId]);

  return Response.json(
    statusCode: 201,
    body: {
      'id': id,
      'customerName': customerName,
      'entryDate': entryDate,
      'value': value,
      'score': score,
      'result': result,
      'betType': betType,
      'station': station,
      'note': note,
      'createdAt': createdAt,
      'updatedAt': createdAt,
    },
  );
}

/// An entry's station: 'mb', a region code or a station id; anything else (or absent) = null (Miền Bắc).
String? _station(Object? raw) {
  final s = raw is String ? raw.trim() : '';
  return s.isNotEmpty && isEntryStation(s) ? s : null;
}

Map<String, Object?> _entryJson(Row r) => {
      'id': r['id'],
      'customerName': r['customer_name'],
      'entryDate': r['entry_date'],
      'value': r['value'],
      'score': r['score'],
      'result': r['result'],
      'betType': r['bet_type'],
      'station': r['station'],
      'note': r['note'],
      'createdAt': r['created_at'],
      'updatedAt': r['updated_at'] ?? r['created_at'],
    };
