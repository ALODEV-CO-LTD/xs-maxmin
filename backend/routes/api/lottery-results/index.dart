import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/database.dart';
import 'package:sqlite3/sqlite3.dart';

/// The official Miền Bắc lottery draw for a given day. This is a shared,
/// public fact (not scoped to a user) - any logged-in user may read or
/// upsert it, since it's the same real-world number for everyone and the
/// point is to let whoever sees the result first record it for the rest.
///
/// GET    ?date=YYYY-MM-DD  -> { result: {...} | null }
/// POST   { drawDate, dacBiet, giaiNhat, giaiNhi[2], giaiBa[6], giaiTu[4],
///          giaiNam[6], giaiSau[3], giaiBay[4] } -> upsert by drawDate
/// DELETE ?date=YYYY-MM-DD  -> removes that day's result (e.g. it was
///          entered for the wrong date) - { ok: true } either way, deleting
///          a date with nothing saved is not an error.
const _tierCounts = {
  'giaiNhi': 2,
  'giaiBa': 6,
  'giaiTu': 4,
  'giaiNam': 6,
  'giaiSau': 3,
  'giaiBay': 4,
};

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
      'dacBiet': r['dac_biet'],
      'giaiNhat': r['giai_nhat'],
      'giaiNhi': jsonDecode(r['giai_nhi'] as String),
      'giaiBa': jsonDecode(r['giai_ba'] as String),
      'giaiTu': jsonDecode(r['giai_tu'] as String),
      'giaiNam': jsonDecode(r['giai_nam'] as String),
      'giaiSau': jsonDecode(r['giai_sau'] as String),
      'giaiBay': jsonDecode(r['giai_bay'] as String),
      'updatedAt': r['updated_at'],
    };

Response _get(RequestContext context) {
  final date = context.request.uri.queryParameters['date'];
  if (date == null || date.isEmpty) {
    return Response.json(statusCode: 400, body: {'error': 'Thiếu ngày (date)'});
  }
  final db = context.read<Database>();
  final rows = db.select('SELECT * FROM lottery_results WHERE draw_date = ?', [date]);
  return Response.json(body: {'result': rows.isEmpty ? null : _rowToJson(rows.first)});
}

Response _delete(RequestContext context) {
  final date = context.request.uri.queryParameters['date'];
  if (date == null || date.isEmpty) {
    return Response.json(statusCode: 400, body: {'error': 'Thiếu ngày (date)'});
  }
  final db = context.read<Database>();
  db.execute('DELETE FROM lottery_results WHERE draw_date = ?', [date]);
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

  final dacBiet = (body['dacBiet'] as String?)?.trim();
  final giaiNhat = (body['giaiNhat'] as String?)?.trim();
  if (dacBiet == null || dacBiet.isEmpty || giaiNhat == null || giaiNhat.isEmpty) {
    return Response.json(statusCode: 400, body: {'error': 'Thiếu giải đặc biệt hoặc giải nhất'});
  }

  final tiers = <String, List<String>>{};
  for (final entry in _tierCounts.entries) {
    final raw = body[entry.key];
    if (raw is! List) {
      return Response.json(statusCode: 400, body: {'error': 'Thiếu dữ liệu ${entry.key}'});
    }
    final values = raw.map((v) => (v as String?)?.trim() ?? '').toList();
    if (values.length != entry.value || values.any((v) => v.isEmpty)) {
      return Response.json(
        statusCode: 400,
        body: {'error': '${entry.key} phải có đủ ${entry.value} số'},
      );
    }
    tiers[entry.key] = values;
  }

  final db = context.read<Database>();
  final now = DateTime.now().toUtc().toIso8601String();
  final existing = db.select('SELECT id, created_at FROM lottery_results WHERE draw_date = ?', [drawDate]);
  final id = existing.isEmpty ? newId() : existing.first['id'] as String;
  final createdAt = existing.isEmpty ? now : existing.first['created_at'] as String;

  db.execute(
    '''
    INSERT INTO lottery_results (
      id, draw_date, dac_biet, giai_nhat, giai_nhi, giai_ba, giai_tu, giai_nam, giai_sau, giai_bay,
      created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT (draw_date) DO UPDATE SET
      dac_biet = excluded.dac_biet,
      giai_nhat = excluded.giai_nhat,
      giai_nhi = excluded.giai_nhi,
      giai_ba = excluded.giai_ba,
      giai_tu = excluded.giai_tu,
      giai_nam = excluded.giai_nam,
      giai_sau = excluded.giai_sau,
      giai_bay = excluded.giai_bay,
      updated_at = excluded.updated_at
    ''',
    [
      id,
      drawDate,
      dacBiet,
      giaiNhat,
      jsonEncode(tiers['giaiNhi']),
      jsonEncode(tiers['giaiBa']),
      jsonEncode(tiers['giaiTu']),
      jsonEncode(tiers['giaiNam']),
      jsonEncode(tiers['giaiSau']),
      jsonEncode(tiers['giaiBay']),
      createdAt,
      now,
    ],
  );

  final saved = db.select('SELECT * FROM lottery_results WHERE draw_date = ?', [drawDate]);
  return Response.json(body: {'result': _rowToJson(saved.first)});
}
