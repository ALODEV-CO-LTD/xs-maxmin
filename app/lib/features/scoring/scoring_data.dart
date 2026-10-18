import '../../core/api_client.dart';
import '../entries/offline_store.dart';
import '../../core/scoring_config.dart';
import 'entry_model.dart';

/// True while the figures on screen come from the copy saved on the phone because the server could not be reached.
/// The calculation itself never needs the network: it only needs this data (entries, customers, payout rates and the
/// day's lottery results), which is saved on the phone every time it is read.
class DataSource {
  static bool fromCache = false;
}

/// The COMPLETE history, from the server and saved on the phone; offline: the saved copy (pass [overlay] to also include
/// the entries typed offline that are still waiting to be synced). Throws when offline with nothing saved yet.
Future<List<Entry>> fetchAllEntries(ApiClient api, {bool overlay = false}) async {
  final store = await OfflineStore.open(api, api.auth);
  final r = await store.loadAllEntries(overlay: overlay);
  DataSource.fromCache = r.fromCache;
  // offline with nothing saved yet: an error only when there is not even a number typed offline waiting to be sent
  if (r.noCache && r.entries.isEmpty) throw ApiError(0, 'Đang offline và chưa có số liệu đã lưu trên máy. Hãy mở app khi có mạng một lần.');
  return [for (final e in r.entries) Entry.fromJson(Map<String, dynamic>.from(e.toJson()))];
}

/// GET with the saved copy as fallback when the network is down (same cache as Nhập số).
Future<dynamic> _cachedGet(ApiClient api, String path) async => (await OfflineStore.open(api, api.auth)).cachedGet(path);

Future<List<CustomerRec>> fetchCustomers(ApiClient api) async {
  final res = await _cachedGet(api, '/me/customers') as Map;
  return [for (final c in (res['customers'] as List? ?? const [])) CustomerRec.fromJson(Map<String, dynamic>.from(c as Map))];
}

/// The account-wide payout config; the built-in default when the call fails or answers nothing.
Future<RatesMap> fetchAccountRates(ApiClient api) async {
  try {
    final res = await _cachedGet(api, '/me/scoring-settings') as Map;
    final r = res['rates'];
    if (r is Map && r.isNotEmpty) return Map<String, dynamic>.from(r);
  } catch (_) {/* keep the fallback */}
  return Map<String, dynamic>.from(defaultRates);
}

/// Saved result of one station on one day, or null. The account's own result; what is kept on the phone wins.
Future<Map<String, dynamic>?> fetchLotteryResult(ApiClient api, String date, String station) async =>
    (await OfflineStore.open(api, api.auth)).lotteryResult(date, station);

/// Every station's saved result of [date], keyed by station id (the account's own).
Future<Map<String, Map<String, dynamic>>> fetchDayResults(ApiClient api, String date) async =>
    (await OfflineStore.open(api, api.auth)).dayResults(date);
