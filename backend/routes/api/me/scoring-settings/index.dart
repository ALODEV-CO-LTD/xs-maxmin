import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/scoring_rates.dart';
import 'package:server/src/user_repo.dart';
import 'package:sqlite3/sqlite3.dart';

/// Per-user payout config ("tỉ lệ ăn" + which prize tiers to compare
/// against) used by ScoringView's auto-calc and EntriesView's "Loại đánh"
/// picker - each account (each "đại lý" running their own customers) sets
/// its own, NOT admin-controlled: deliberately under /me, reachable by any
/// logged-in user, with no role check.
///
/// Each bet type maps to `{rate, tiers, digits}`: `rate` is the payout
/// multiple, `tiers` is which of the 8 prize groups in a lottery_results
/// row (dacBiet/giaiNhat/giaiNhi/giaiBa/giaiTu/giaiNam/giaiSau/giaiBay)
/// count as a match - e.g. "đề" traditionally only checks `dacBiet`, while
/// "lô" checks all 8. `digits` is how many trailing digits to compare (2
/// for "đề"/"lô", 3 for "3 càng", 4 for "bao lô 4", ...) - defaults to 2,
/// matching every type's behavior before this field existed. Stored as one
/// JSON blob (key `scoring_rates` on `users` for historical reasons - it
/// used to hold only rates, see below).
///
/// GET  -> { rates: {typeKey: {rate, tiers, digits}} }  (falls back to the
///          built-in default if the user never saved an override)
/// PUT  { rates: {typeKey: {rate, tiers, digits}} } -> saves it as this
///      user's own
final Map<String, dynamic> _defaultRates = {
  'de': {'rate': 70, 'tiers': ['dacBiet'], 'digits': 2},
  'lo': {'rate': 20, 'tiers': List<String>.from(validTiers), 'digits': 2},
};

Future<Response> onRequest(RequestContext context) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  return switch (context.request.method) {
    HttpMethod.get => _get(context, auth.userId),
    HttpMethod.put => _put(context, auth.userId),
    _ => Response(statusCode: 405, body: 'Method not allowed'),
  };
}

Response _get(RequestContext context, String userId) {
  final self = loadSelfRow(context, userId);
  if (self == null) return unauthorized('Tài khoản không tồn tại');

  final raw = self['scoring_rates'] as String?;
  Map<String, dynamic> rates = _defaultRates;
  if (raw != null) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded.isNotEmpty) {
        final normalized = <String, dynamic>{};
        for (final entry in decoded.entries) {
          final n = normalizeRateEntry(entry.value);
          if (n != null) normalized[entry.key as String] = n;
        }
        if (normalized.isNotEmpty) rates = normalized;
      }
    } catch (_) {
      // Malformed row - fall back to the built-in defaults.
    }
  }
  return Response.json(
    body: {'rates': rates, 'availableTiers': validTiers, 'digitRange': [minDigits, maxDigits]},
  );
}

Future<Response> _put(RequestContext context, String userId) async {
  final Map<String, dynamic> body;
  try {
    body = jsonDecode(await context.request.body()) as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Body không hợp lệ'});
  }

  final rates = body['rates'];
  if (rates is! Map || rates.isEmpty) {
    return Response.json(statusCode: 400, body: {'error': 'Cần ít nhất một loại đánh'});
  }

  final normalized = <String, dynamic>{};
  for (final entry in rates.entries) {
    final key = entry.key;
    if (key is! String || key.trim().isEmpty) {
      return Response.json(statusCode: 400, body: {'error': 'Mã loại đánh không hợp lệ'});
    }
    final n = normalizeRateEntry(entry.value);
    if (n == null) {
      return Response.json(
        statusCode: 400,
        body: {'error': 'Cấu hình của "$key" không hợp lệ (cần tỉ lệ > 0 và ít nhất 1 giải)'},
      );
    }
    normalized[key] = n;
  }

  final db = context.read<Database>();
  db.execute('UPDATE users SET scoring_rates = ? WHERE id = ?', [jsonEncode(normalized), userId]);

  return Response.json(
    body: {'rates': normalized, 'availableTiers': validTiers, 'digitRange': [minDigits, maxDigits]},
  );
}
