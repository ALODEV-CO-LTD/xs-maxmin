import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/database.dart';
import 'package:server/src/lottery_stations.dart';
import 'package:sqlite3/sqlite3.dart';

/// Official lottery draws, one result per (date, station): Miền Bắc ('mb') or a Miền Nam / Miền
/// Trung station such as 'mn-tphcm' (lib/src/lottery_stations.dart; Miền Bắc has 8 prize groups,
/// Miền Nam/Trung 9 with a 6-digit special prize and an eighth prize). A draw is a shared, public
/// fact (not scoped to a user): whoever enters it first makes it available to everyone, and
/// anyone can correct it afterward (upsert by date + station).
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
    HttpMethod.get => _get(context),
    HttpMethod.post => _upsert(context),
    HttpMethod.delete => _delete(context),
    _ => Response(statusCode: 405, body: 'Method not allowed'),
  };
}

Map<String, dynamic> _rowToJson(Row r) => {
      'drawDate': r['draw_date'],
      'station': r['station'],
      ...(jsonDecode(r['data'] as String) as Map<String, dynamic>),
      'updatedAt': r['updated_at'],
    };

Response _get(RequestContext context) {
  final qp = context.request.uri.queryParameters;
  final date = qp['date'];
  if (date == null || date.isEmpty) {
    return Response.json(statusCode: 400, body: {'error': 'Thiếu ngày (date)'});
  }
  final db = context.read<Database>();
  if (qp['all'] == '1') {
    final rows = db.select('SELECT * FROM lottery_results WHERE draw_date = ? ORDER BY station', [date]);
    return Response.json(body: {'results': [for (final r in rows) _rowToJson(r)]});
  }
  final station = qp['station'] ?? 'mb';
  final rows = db.select('SELECT * FROM lottery_results WHERE draw_date = ? AND station = ?', [date, station]);
  return Response.json(body: {'result': rows.isEmpty ? null : _rowToJson(rows.first)});
}

Response _delete(RequestContext context) {
  final qp = context.request.uri.queryParameters;
  final date = qp['date'];
  if (date == null || date.isEmpty) {
    return Response.json(statusCode: 400, body: {'error': 'Thiếu ngày (date)'});
  }
  context.read<Database>().execute('DELETE FROM lottery_results WHERE draw_date = ? AND station = ?', [date, qp['station'] ?? 'mb']);
  return Response.json(body: {'ok': true});
}

Future<Response> _upsert(RequestContext context) async {
  final Map<String, dynamic> body;
  try {
    body = jsonDecode(await context.request.body()) as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Body không hợp lệ'});
  }

  final drawDate = (body['drawDate'] as String?)?.trim();
  if (drawDate == null || drawDate.isEmpty) {
    return Response.json(statusCode: 400, body: {'error': 'Thiếu ngày (drawDate)'});
  }
  try {
    DateTime.parse(drawDate);
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Ngày không hợp lệ'});
  }

  final station = (body['station'] as String?)?.trim() ?? 'mb';
  if (!isResultStation(station)) {
    return Response.json(statusCode: 400, body: {'error': 'Đài không hợp lệ'});
  }
  final region = regionOf(station)!;

  // Every prize group of the region must be present with the right count and digit length.
  final data = <String, dynamic>{};
  for (final prize in region.structure) {
    final raw = body[prize.tier];
    final values = raw is List ? raw.map((v) => (v?.toString() ?? '').trim()).toList() : [raw?.toString().trim() ?? ''];
    if (values.length != prize.count || values.any((v) => v.isEmpty)) {
      return Response.json(statusCode: 400, body: {'error': '${prize.label} phải có đủ ${prize.count} số'});
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
  final existing = db.select('SELECT id, created_at FROM lottery_results WHERE draw_date = ? AND station = ?', [drawDate, station]);
  final id = existing.isEmpty ? newId() : existing.first['id'] as String;
  final createdAt = existing.isEmpty ? now : existing.first['created_at'] as String;
  db.execute(
    '''
    INSERT INTO lottery_results (id, draw_date, station, data, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?)
    ON CONFLICT (draw_date, station) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at
    ''',
    [id, drawDate, station, jsonEncode(data), createdAt, now],
  );
  final saved = db.select('SELECT * FROM lottery_results WHERE draw_date = ? AND station = ?', [drawDate, station]);
  return Response.json(body: {'result': _rowToJson(saved.first)});
}
