import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/lottery_stations.dart';
import '../../core/scoring_config.dart';
import '../account/stats_money.dart';
import '../entries/entry_model.dart';
import '../entries/message_parser.dart' show foldText;
import '../entries/offline_store.dart';
import 'customer_model.dart';

/// One row of the Khách hàng list: a roster customer (or a name only seen in old entries) with totals from its entries.
class CustomerSummary {
  CustomerSummary(this.name, this.customer);
  final String name;

  /// null = the name only appears in entries, it was never added to the roster.
  final Customer? customer;
  int count = 0;
  double vao = 0;
  double ra = 0;
  String? lastDate;

  double get chenhLech => vao - ra;

  /// Tiền (đồng), tính như Tính điểm: tiền khách gửi, tiền trúng, lợi nhuận trên các ngày đã có kết quả xổ số.
  double sent = 0;
  double won = 0;
  double settled = 0;
  double get profit => settled - won;
  String get phone => customer?.phone ?? '';
}

/// Builds the list (pure, tested): the roster first (a customer with no entries yet shows 0/0/0), then names only found in
/// entries; sorted by last entry date, newest first, customers without entries first.
List<CustomerSummary> summarizeCustomers(List<Customer> roster, List<Entry> entries) {
  final by = <String, CustomerSummary>{for (final c in roster) c.name: CustomerSummary(c.name, c)};
  for (final e in entries) {
    final name = e.customerName.isEmpty ? '(Không tên)' : e.customerName;
    final s = by.putIfAbsent(name, () => CustomerSummary(name, null));
    s.count += 1;
    s.vao += toNumber(e.score);
    s.ra += toNumber(e.result);
    if (s.lastDate == null || e.entryDate.compareTo(s.lastDate!) > 0) s.lastDate = e.entryDate;
  }
  final list = by.values.toList();
  list.sort((a, b) {
    if (a.lastDate == null && b.lastDate == null) return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    if (a.lastDate == null) return -1;
    if (b.lastDate == null) return 1;
    return b.lastDate!.compareTo(a.lastDate!);
  });
  return list;
}

List<CustomerSummary> searchCustomers(List<CustomerSummary> list, String query) {
  final q = foldText(query.trim());
  return q.isEmpty ? list : [for (final c in list) if (foldText(c.name).contains(q)) c];
}

/// Bộ lọc kết quả của khách (lãi / lỗ / chưa có số liệu) và miền của khách (Bắc / Nam-Trung); null = không lọc.
enum CustomerResultFilter { profit, loss, noData }

List<CustomerSummary> filterCustomers(List<CustomerSummary> list, {CustomerResultFilter? result, String? region}) {
  bool keep(CustomerSummary c) {
    switch (result) {
      case CustomerResultFilter.profit:
        if (!(c.count > 0 && c.profit > 0)) return false;
      case CustomerResultFilter.loss:
        if (!(c.count > 0 && c.profit < 0)) return false;
      case CustomerResultFilter.noData:
        if (c.count > 0) return false;
      case null:
        break;
    }
    return region == null || c.customer?.homeRegion == region;
  }

  return [for (final c in list) if (keep(c)) c];
}

/// Thứ tự danh sách khách. `recent` = mặc định (ngày nhập gần nhất trước).
enum CustomerSort {
  recent('Gần đây nhất'),
  sentDesc('Tiền vào nhiều nhất'),
  sentAsc('Tiền vào ít nhất'),
  wonDesc('Tiền ra nhiều nhất'),
  wonAsc('Tiền ra ít nhất'),
  profitDesc('Lợi nhuận nhiều nhất'),
  profitAsc('Lợi nhuận ít nhất'),
  nameAsc('Tên A → Z');

  const CustomerSort(this.label);
  final String label;
}

List<CustomerSummary> sortCustomers(List<CustomerSummary> list, CustomerSort sort) {
  if (sort == CustomerSort.recent) return list;
  int byName(CustomerSummary a, CustomerSummary b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
  final out = [...list];
  num key(CustomerSummary c) => switch (sort) {
        CustomerSort.sentDesc || CustomerSort.sentAsc => c.sent,
        CustomerSort.wonDesc || CustomerSort.wonAsc => c.won,
        CustomerSort.profitDesc || CustomerSort.profitAsc => c.profit,
        _ => 0,
      };
  final desc = sort == CustomerSort.sentDesc || sort == CustomerSort.wonDesc || sort == CustomerSort.profitDesc;
  if (sort == CustomerSort.nameAsc) {
    out.sort(byName);
  } else {
    out.sort((a, b) {
      final c = desc ? key(b).compareTo(key(a)) : key(a).compareTo(key(b));
      return c != 0 ? c : byName(a, b);
    });
  }
  return out;
}

class CustomersController extends ChangeNotifier {
  CustomersController({required this.api, required this.auth, this.store, this.stations});
  final ApiClient api;
  final AuthStore auth;
  OfflineStore? store;
  final LotteryStations? stations;

  /// Money per customer name, worked out in the background after the list shows; null until it is ready.
  Map<String, CustomerMoney>? money;

  List<Customer> roster = [];
  List<Entry> entries = [];
  RatesMap accountRates = {...defaultRates};
  bool loading = true;
  String error = '';
  bool fromCache = false;
  String query = '';
  bool _disposed = false;

  List<CustomerSummary>? _summaries;
  List<CustomerSummary> get summaries {
    final cached = _summaries;
    if (cached != null) return cached;
    final list = summarizeCustomers(roster, entries);
    final m = money;
    if (m != null) {
      for (final s in list) {
        final x = m[s.name];
        if (x == null) continue;
        s.sent = x.sent;
        s.won = x.won;
        s.settled = x.settled;
      }
    }
    return _summaries = list;
  }

  bool get moneyReady => money != null;
  CustomerResultFilter? resultFilter;
  String? regionFilter; // 'mb' | 'mn'
  CustomerSort sort = CustomerSort.recent;
  bool get hasFilter => resultFilter != null || regionFilter != null;

  /// Số mục đang áp dụng trong bộ lọc (kết quả, miền, thứ tự khác mặc định), hiện trên nút Bộ lọc.
  int get activeCount => (resultFilter != null ? 1 : 0) + (regionFilter != null ? 1 : 0) + (sort != CustomerSort.recent ? 1 : 0);
  List<CustomerSummary> get shown => sortCustomers(filterCustomers(searchCustomers(summaries, query), result: resultFilter, region: regionFilter), sort);

  void setSort(CustomerSort s) {
    sort = s;
    _notify();
  }

  void setResultFilter(CustomerResultFilter? f) {
    resultFilter = f;
    _notify();
  }

  void setRegionFilter(String? r) {
    regionFilter = r;
    _notify();
  }

  void clearFilters() {
    resultFilter = null;
    regionFilter = null;
    sort = CustomerSort.recent;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void invalidate() {
    _summaries = null;
    _notify();
  }

  void setQuery(String q) {
    query = q;
    _notify();
  }

  Future<void> load() async {
    store ??= await OfflineStore.open(api, auth);
    loading = entries.isEmpty && roster.isEmpty;
    error = '';
    _notify();
    try {
      final list = await store!.loadAllEntries();
      entries = list.entries;
      fromCache = list.fromCache;
    } on ApiError catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Không tải được số liệu';
    }
    try {
      roster = parseCustomers(await store!.cachedGet('/me/customers'));
    } catch (_) {/* non-fatal: the list still works from entries */}
    try {
      final res = await store!.cachedGet('/me/scoring-settings');
      final rates = res is Map ? res['rates'] : null;
      if (rates is Map && rates.isNotEmpty) accountRates = Map<String, dynamic>.from(rates);
    } catch (_) {/* keep the built-in fallback */}
    loading = false;
    _summaries = null;
    _notify();
    _loadMoney();
  }

  Future<void> _loadMoney() async {
    final st = stations;
    if (st == null) return;
    try {
      money = await loadCustomerMoney(api, st);
    } catch (_) {
      return; // the cards keep showing "..." instead of wrong numbers
    }
    _summaries = null;
    _notify();
  }

  void addLocal(Customer c) {
    roster = [...roster, c]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    invalidate();
  }

  /// Sets the phone number. Returns an error text or ''.
  Future<String> savePhone(Customer c, String phone) async {
    if (c.pending) return 'Khách hàng này đang chờ đồng bộ, hãy sửa sau khi có mạng và đồng bộ xong.';
    try {
      final res = await api.patch('/me/customers/${c.id}', {'phone': phone.trim()}) as Map;
      c.phone = (res['phone'] as String?) ?? '';
      invalidate();
      return '';
    } on ApiError catch (e) {
      return e.status == 0 ? 'Đang offline: sửa khách hàng cần có mạng, vui lòng thử lại khi kết nối lại.' : e.message;
    }
  }

  /// Sets the default đài. Returns an error text or ''.
  Future<String> saveStation(Customer c, String code) async {
    try {
      final res = await api.patch('/me/customers/${c.id}', {'defaultStation': code}) as Map;
      c.defaultStation = res['defaultStation'] as String?;
      invalidate();
      return '';
    } on ApiError catch (e) {
      return e.message;
    }
  }

  /// Sets the customer's own region ('mb' | 'mn' | null = not chosen). Returns an error text or ''.
  Future<String> saveHomeRegion(Customer c, String? region) async {
    try {
      final res = await api.patch('/me/customers/${c.id}', {'homeRegion': region ?? ''}) as Map;
      final v = res['homeRegion'];
      c.homeRegion = v == 'mb' || v == 'mn' ? v as String : null;
      invalidate();
      return '';
    } on ApiError catch (e) {
      return e.status == 0 ? 'Đang offline: sửa khách hàng cần có mạng, vui lòng thử lại khi kết nối lại.' : e.message;
    }
  }

  void customerConfigSaved(Customer c, RatesMap? map) {
    c.scoringRates = map;
    invalidate();
  }

  /// Removes the customer from the roster only (entries keep their name). Returns an error text or ''.
  Future<String> remove(Customer c) async {
    try {
      store ??= await OfflineStore.open(api, auth);
      if (c.pending) {
        await store!.queueCustomerDelete(c.id); // never reached the server: just forget it
      } else {
        try {
          await api.delete('/me/customers/${c.id}');
        } on ApiError catch (e) {
          if (e.status != 0) rethrow;
          await store!.queueCustomerDelete(c.id); // offline: removed here now, on the server when the network is back
        }
      }
      roster = roster.where((x) => x.id != c.id).toList();
      invalidate();
      return '';
    } on ApiError catch (e) {
      return e.message;
    }
  }
}
