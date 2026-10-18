import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/request_body.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/database.dart';
import 'package:server/src/lottery_stations.dart';
import 'package:sqlite3/sqlite3.dart';

/// Official lottery draws, one result per (date, station): Miền Bắc ('mb') or a Miền Nam / Miền
/// Trung station such as 'mn-tphcm' (lib/src/lottery_stations.dart; Miền Bắc has 8 prize groups,
/// Miền Nam/Trung 9 with a 6-digit special prize and an eighth prize). Results belong to the
/// ACCOUNT (not to its customers, and not shared between accounts): what one account saves or
/// corrects is never seen by another (upsert by user + date + station).
///
/// GET    ?date=YYYY-MM-DD[&station=mb]  -> { result: {...} | null }   (station defaults to 'mb')
/// GET    ?date=YYYY-MM-DD&all=1         -> { results: [{...}, ...] }  every station saved that day
/// POST   { drawDate, station?, dacBiet, giaiNhat, giaiNhi[], ... } -> upsert (counts and digit
///        lengths are checked against the station's region)
/// DELETE ?date=YYYY-MM-DD[&station=mb] -> removes that result ({ ok: true } even if none)
Future<Response> onRequest(RequestContext context) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  return switch (context.request.method) {
    HttpMethod.get => _get(context, auth.userId),
    HttpMethod.post => _upsert(context, auth.userId),
    HttpMethod.delete => _delete(context, auth.userId),
    _ => Response(statusCode: 405, body: 'Method not allowed'),
  };
}

/// How many numbers a group may have beyond the region's usual count.
const _maxExtraNumbers = 20;

Map<String, dynamic> _rowToJson(Row r) => {
      'drawDate': r['draw_date'],
      'station': r['station'],
      ...(jsonDecode(r['data'] as String) as Map<String, dynamic>),
      'updatedAt': r['updated_at'],
    };

final _drawDatePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// True for a real calendar date written exactly `YYYY-MM-DD`.
bool isValidDrawDate(String s) {
  if (!_drawDatePattern.hasMatch(s)) return false;
  final d = DateTime.tryParse(s);
  if (d == null) return false;
  final two = (int n) => n.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}' == s;
}

Response _get(RequestContext context, String userId) {
  final qp = context.request.uri.queryParameters;
  final date = qp['date'];
  if (date == null || date.isEmpty) {
    return Response.json(statusCode: 400, body: {'error': 'Thiếu ngày (date)'});
  }
  final db = context.read<Database>();
  if (qp['all'] == '1') {
    final rows = db.select('SELECT * FROM lottery_results WHERE user_id = ? AND draw_date = ? ORDER BY station', [userId, date]);
    return Response.json(body: {'results': [for (final r in rows) _rowToJson(r)]});
  }
  final station = qp['station'] ?? 'mb';
  final rows = db.select('SELECT * FROM lottery_results WHERE user_id = ? AND draw_date = ? AND station = ?', [userId, date, station]);
  return Response.json(body: {'result': rows.isEmpty ? null : _rowToJson(rows.first)});
}

Response _delete(RequestContext context, String userId) {
  final qp = context.request.uri.queryParameters;
  final date = qp['date'];
  if (date == null || date.isEmpty) {
    return Response.json(statusCode: 400, body: {'error': 'Thiếu ngày (date)'});
  }
  context.read<Database>().execute('DELETE FROM lottery_results WHERE user_id = ? AND draw_date = ? AND station = ?', [userId, date, qp['station'] ?? 'mb']);
  return Response.json(body: {'ok': true});
}

Future<Response> _upsert(RequestContext context, String userId) async {
  final read = await readJsonBody(context, smallBodyMaxBytes);
  if (read.error != null) return read.error!;
  final body = read.body!;

  final rawDate = body['drawDate'];
  if (rawDate == null || (rawDate is String && rawDate.trim().isEmpty)) {
    return Response.json(statusCode: 400, body: {'error': 'Thiếu ngày (drawDate)'});
  }
  // Strictly YYYY-MM-DD: any other form ("2026-10-18 00:00") would be stored under a key the lookups never find.
  final drawDate = rawDate is String ? rawDate.trim() : null;
  if (drawDate == null || !isValidDrawDate(drawDate)) {
    return Response.json(statusCode: 400, body: {'error': 'Ngày không hợp lệ (định dạng YYYY-MM-DD)'});
  }

  final rawStation = body['station'];
  if (rawStation != null && rawStation is! String) {
    return Response.json(statusCode: 400, body: {'error': 'Đài không hợp lệ'});
  }
  final station = (rawStation as String?)?.trim() ?? 'mb';
  if (!isResultStation(station)) {
    return Response.json(statusCode: 400, body: {'error': 'Đài không hợp lệ'});
  }
  final region = regionOf(station)!;

  // Every prize group of the region must be present with the right count and digit length.
  final data = <String, dynamic>{};
  for (final prize in region.structure) {
    final raw = body[prize.tier];
    final values = raw is List ? raw.map((v) => (v?.toString() ?? '').trim()).toList() : [raw?.toString().trim() ?? ''];
    // The count of the region is the minimum; a draw may have more numbers in a group (extra boxes added by the user).
    final single = prize.tier == 'dacBiet' || prize.tier == 'giaiNhat';
    final most = single ? prize.count : prize.count + _maxExtraNumbers;
    if (values.length < prize.count || values.length > most || values.any((v) => v.isEmpty)) {
      return Response.json(statusCode: 400, body: {'error': '${prize.label} phải có ít nhất ${prize.count} số${single ? '' : ' (tối đa $most)'}'});
    }
    final bad = values.where((v) => !RegExp('^\\d{${prize.digits}}\$').hasMatch(v));
    if (bad.isNotEmpty) {
      return Response.json(statusCode: 400, body: {'error': '${prize.label}: mỗi số phải có đúng ${prize.digits} chữ số'});
    }
    // The special and first prize are single strings (as before); every other group is a list.
    data[prize.tier] = (prize.tier == 'dacBiet' || prize.tier == 'giaiNhat') ? values.first : values;
  }

  final db = context.read<Database>();
  final now = DateTime.now().toUtc().toIso8601String();
  final existing = db.select('SELECT id, created_at FROM lottery_results WHERE user_id = ? AND draw_date = ? AND station = ?', [userId, drawDate, station]);
  final id = existing.isEmpty ? newId() : existing.first['id'] as String;
  final createdAt = existing.isEmpty ? now : existing.first['created_at'] as String;
  db.execute(
    '''
    INSERT INTO lottery_results (id, user_id, draw_date, station, data, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT (user_id, draw_date, station) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at
    ''',
    [id, userId, drawDate, station, jsonEncode(data), createdAt, now],
  );
  final saved = db.select('SELECT * FROM lottery_results WHERE user_id = ? AND draw_date = ? AND station = ?', [userId, drawDate, station]);
  return Response.json(body: {'result': _rowToJson(saved.first)});
}
