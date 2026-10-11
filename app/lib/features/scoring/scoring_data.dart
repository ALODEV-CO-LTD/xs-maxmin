import '../../core/api_client.dart';
import '../../core/scoring_config.dart';
import 'entry_model.dart';

/// Loads every page of `GET /me/entries` (500 a page, like frontend/src/offline.js fetchAllPages).
Future<List<Entry>> fetchAllEntries(ApiClient api) async {
  final byId = <String, Entry>{};
  var offset = 0;
  for (;;) {
    final page = await api.get('/me/entries?limit=500&offset=$offset') as Map;
    final list = (page['entries'] as List?) ?? const [];
    for (final e in list) {
      final entry = Entry.fromJson(Map<String, dynamic>.from(e as Map));
      byId[entry.id] = entry;
    }
    offset += list.length;
    if (page['hasMore'] != true || list.isEmpty) break;
  }
  return byId.values.toList();
}

Future<List<CustomerRec>> fetchCustomers(ApiClient api) async {
  final res = await api.get('/me/customers') as Map;
  return [for (final c in (res['customers'] as List? ?? const [])) CustomerRec.fromJson(Map<String, dynamic>.from(c as Map))];
}

/// The account-wide payout config; the built-in default when the call fails or answers nothing.
Future<RatesMap> fetchAccountRates(ApiClient api) async {
  try {
    final res = await api.get('/me/scoring-settings') as Map;
    final r = res['rates'];
    if (r is Map && r.isNotEmpty) return Map<String, dynamic>.from(r);
  } catch (_) {/* keep the fallback */}
  return Map<String, dynamic>.from(defaultRates);
}

/// Saved result of one station on one day, or null.
Future<Map<String, dynamic>?> fetchLotteryResult(ApiClient api, String date, String station) async {
  final res = await api.get('/lottery-results?date=$date&station=${Uri.encodeQueryComponent(station)}') as Map;
  final r = res['result'];
  return r is Map ? Map<String, dynamic>.from(r) : null;
}

/// Every station's saved result of [date], keyed by station id.
Future<Map<String, Map<String, dynamic>>> fetchDayResults(ApiClient api, String date) async {
  final res = await api.get('/lottery-results?date=$date&all=1') as Map;
  return {
    for (final r in (res['results'] as List? ?? const []))
      (r as Map)['station'] as String: Map<String, dynamic>.from(r),
  };
}
