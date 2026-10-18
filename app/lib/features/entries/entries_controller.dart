import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/bet_types.dart';
import '../../core/format.dart';
import '../../core/lottery_stations.dart';
import '../../core/scoring_config.dart';
import '../customers/customer_model.dart';
import '../chat_calc/chat_prefill.dart';
import 'entry_model.dart';
import 'message_parser.dart';
import 'offline_store.dart';

const confirmCopyKey = 'xoso_confirm_copy';

/// One editable "hạng mục / số / điểm vào" line: the manual entry rows and the rows of a preview (paste / photo).
class RowDraft {
  RowDraft({required this.type, String value = '', String score = '', this.selected = false, this.reasons = const [], this.raw = ''})
      : uid = ++_seq,
        value = TextEditingController(text: value),
        score = TextEditingController(text: score);
  static int _seq = 0;
  final int uid;
  String type;
  final TextEditingController value;
  final TextEditingController score;
  bool selected;
  final List<String> reasons;
  final String raw;
  bool get uncertain => reasons.isNotEmpty;
  bool get isBlank => value.text.trim().isEmpty && score.text.trim().isEmpty;
  bool get isComplete => type.isNotEmpty && value.text.trim().isNotEmpty && score.text.trim().isNotEmpty;
  void dispose() {
    value.dispose();
    score.dispose();
  }
}

class SavedTemplate {
  SavedTemplate(this.id, this.customerName, this.config);
  final String id;
  final String customerName;
  final SyntaxTemplate config;
}

/// State of the Nhập số screen: customers, the entry list (with offline queue), the add form, filters and the importers.
class EntriesController extends ChangeNotifier {
  // ignore: prefer_initializing_formals
  EntriesController({required this.api, required this.auth, required this.stations, OfflineStore? store}) : _store = store;

  final ApiClient api;
  final AuthStore auth;
  final LotteryStations stations;
  OfflineStore? _store;
  Timer? _timer;
  bool _disposed = false;

  // ---- data ----
  List<Customer> customers = [];
  RatesMap accountRates = {'de': {}, 'lo': {}};
  List<SavedTemplate> templates = [];
  List<Entry> entries = [];
  bool? packageActive; // null = unknown yet
  bool loading = true;
  String loadError = '';
  bool fromCache = false;
  int pending = 0;
  String notice = '';

  /// "Đã thêm N số liệu cho (tên khách)" shown right above the add button for [addedMessageDuration] (web: flashAdded).
  String addedMessage = '';
  Timer? _addedTimer;
  static const addedMessageDuration = Duration(seconds: 7);
  final List<SyncConflict> conflicts = [];
  final List<SyncFailure> failures = [];

  // ---- add form ----
  String selectedName = '';
  String entryDate = todayIso();
  String station = 'mb';
  final TextEditingController note = TextEditingController();
  final List<RowDraft> rows = [];
  bool submitting = false;
  String formError = '';

  // ---- from the chat (Tính toán > Dùng cho Nhập số) ----
  /// Numbers came from a chat: when they are all saved the app moves on to Tính điểm (web: `fromChat`).
  bool fromChat = false;
  String? _boxPrefill;
  String? _forcedStation;
  final Completer<void> _ready = Completer<void>();

  // ---- list ----
  final EntryFilter filter = EntryFilter();

  Future<void> init() async {
    _store ??= await OfflineStore.open(api, auth);
    try {
      (await SharedPreferences.getInstance()).remove(confirmCopyKey); // "Hỏi trước khi sao chép" was removed: forget the old setting
    } catch (_) {}
    rows.add(RowDraft(type: 'de'));
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (pending > 0) sync();
    });
    await reload();
    if (!_ready.isCompleted) _ready.complete();
    // the lottery catalog drives the station picker; it is cached by LotteryStations
    unawaited(stations.load(api).then((_) => _notify()));
  }

  OfflineStore get store => _store!;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _addedTimer?.cancel();
    if (!_ready.isCompleted) _ready.complete();
    note.dispose();
    for (final r in rows) {
      r.dispose();
    }
    super.dispose();
  }

  // ---- loading ----------------------------------------------------------------------------------------------------

  Future<void> reload() async {
    loading = entries.isEmpty;
    loadError = '';
    _notify();
    try {
      await sync(quiet: true);
      final results = await Future.wait<Object?>([
        store.loadAllEntries(),
        _loadCustomers(),
        _loadRates(),
        _loadTemplates(),
        _loadMe(),
      ]);
      final list = results[0] as LoadedEntries;
      entries = list.entries;
      fromCache = list.fromCache;
      pending = await store.pendingCount();
      _applyDefaultStation();
    } on ApiError catch (e) {
      loadError = e.message;
    } catch (_) {
      loadError = 'Không tải được dữ liệu';
    }
    loading = false;
    _notify();
  }

  Future<void> _loadCustomers() async {
    try {
      customers = parseCustomers(await store.cachedGet('/me/customers'));
    } catch (_) {/* the picker is just empty */}
  }

  Future<void> _loadRates() async {
    try {
      final res = await store.cachedGet('/me/scoring-settings');
      final rates = res is Map ? res['rates'] : null;
      if (rates is Map && rates.isNotEmpty) accountRates = Map<String, dynamic>.from(rates);
    } catch (_) {/* keep the {de, lo} fallback */}
  }

  Future<void> _loadTemplates() async {
    try {
      final res = await store.cachedGet('/me/syntax-templates');
      final list = res is Map ? res['templates'] : null;
      if (list is List) {
        templates = [
          for (final t in list)
            if (t is Map) SavedTemplate('${t['id']}', (t['customerName'] as String?) ?? '', SyntaxTemplate.fromJson(t['config'])),
        ];
      }
    } catch (_) {/* parsing still works with the defaults */}
  }

  Future<void> _loadMe() async {
    try {
      final me = await store.cachedGet('/me');
      final p = me is Map ? me['package'] : null;
      if (p is Map) packageActive = p['isActive'] == true;
    } catch (_) {}
  }

  /// Replays the offline queue; reloads the list afterwards when something was sent.
  Future<void> sync({bool quiet = false}) async {
    final res = await store.flush();
    if (res.skipped) return;
    for (final c in res.conflicts) {
      if (!conflicts.any((x) => x.opId == c.opId)) conflicts.add(c);
    }
    failures.addAll(res.failures);
    pending = await store.pendingCount();
    if (res.changed && !quiet) {
      final list = await store.loadAllEntries();
      entries = list.entries;
      fromCache = list.fromCache;
    }
    _notify();
  }

  Future<void> resolveConflict(SyncConflict c, {required bool keepMine}) async {
    await store.resolveConflict(c, keepMine: keepMine);
    conflicts.remove(c);
    final list = await store.loadAllEntries();
    entries = list.entries;
    pending = await store.pendingCount();
    _notify();
  }

  void dismissFailure(SyncFailure f) {
    failures.remove(f);
    _notify();
  }

  /// Confirms [count] new entries for the selected customer; [queued] of them are waiting for the network.
  void flashAdded(int count, {int queued = 0}) {
    if (count <= 0) return;
    addedMessage = 'Đã thêm $count số liệu cho ${selectedName.trim()}${queued > 0 ? ' (đang offline, sẽ tự đồng bộ)' : ''}.';
    _addedTimer?.cancel();
    _addedTimer = Timer(addedMessageDuration, () {
      addedMessage = '';
      _notify();
    });
    _notify();
  }

  void clearAdded() {
    _addedTimer?.cancel();
    addedMessage = '';
    _notify();
  }

  void clearNotice() {
    notice = '';
    _notify();
  }

  // ---- customer, bet types, station ---------------------------------------------------------------------------------

  Customer? get customer {
    for (final c in customers) {
      if (c.name == selectedName) return c;
    }
    return null;
  }

  int entryCount(String name) => entries.where((e) => e.customerName == name).length;

  bool get canAdd => packageActive != false;

  String get regionId => stations.regionOf(station).id;

  /// Account types minus the ones switched off for this customer in the chosen đài's region, plus the customer's own.
  List<String> get betTypes {
    final list = customerBetTypes(accountRates, customer?.scoringRates, regionId);
    return list.isNotEmpty ? list : (typesOf(accountRates).isNotEmpty ? typesOf(accountRates) : ['de', 'lo']);
  }

  void selectCustomer(String name) {
    selectedName = name;
    _applyDefaultStation();
    _fixRowTypes();
    _notify();
  }

  void _applyDefaultStation() {
    // the đài chosen in the chat wins over the customer's default, once (web: forcedStation)
    station = _forcedStation ?? customer?.stationCode ?? 'mb';
    _forcedStation = null;
    _fixRowTypes();
  }

  /// "Dùng cho Nhập số" from the chat: customer, date and đài as chosen there, the text goes into the quick box (which
  /// analyses it). Waits for the first load so the customer list and the account's types are known.
  Future<void> applyChatPrefill(ChatPrefill p) async {
    await _ready.future;
    if (_disposed) return;
    fromChat = true;
    if (p.customer.isNotEmpty) selectedName = p.customer;
    if (p.date.isNotEmpty) entryDate = p.date;
    _forcedStation = p.station.isNotEmpty ? p.station : null;
    _applyDefaultStation();
    _boxPrefill = p.text;
    _notify();
  }

  /// The text waiting for the quick box (once).
  String? takeBoxPrefill() {
    final t = _boxPrefill;
    _boxPrefill = null;
    return t;
  }

  void setStation(String s) {
    station = s;
    _fixRowTypes();
    _notify();
  }

  void setDate(String iso) {
    entryDate = iso;
    _notify();
  }

  /// Keeps every row on a type this customer can use in the chosen region.
  void _fixRowTypes() {
    final types = betTypes;
    for (final r in rows) {
      if (!types.contains(r.type)) r.type = types.first;
    }
  }

  void addCustomerLocal(Customer c) {
    customers = [...customers, c]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    selectCustomer(c.name);
  }

  // ---- manual rows ---------------------------------------------------------------------------------------------------

  RowDraft blankRow([String? type]) => RowDraft(type: type ?? betTypes.first);

  void addRow() {
    rows.add(blankRow(rows.isEmpty ? null : rows.last.type));
    _notify();
  }

  void removeRow(RowDraft r) {
    rows.remove(r);
    r.dispose();
    if (rows.isEmpty) rows.add(blankRow());
    _notify();
  }

  void touchRows() => _notify();

  bool get allRowsSelected => rows.isNotEmpty && rows.every((r) => r.selected);
  int get selectedRowCount => rows.where((r) => r.selected).length;

  void toggleAllRows() {
    final to = !allRowsSelected;
    for (final r in rows) {
      r.selected = to;
    }
    _notify();
  }

  void deleteSelectedRows() {
    for (final r in rows.where((r) => r.selected).toList()) {
      rows.remove(r);
      r.dispose();
    }
    if (rows.isEmpty) rows.add(blankRow());
    _notify();
  }

  void applyBulk({String? type, String? score}) {
    for (final r in rows.where((r) => r.selected)) {
      if (type != null && type.isNotEmpty) r.type = type;
      if (score != null && score.trim().isNotEmpty) r.score.text = score.trim();
    }
    _notify();
  }

  /// Adds [fresh] rows (from a preview) to the manual rows; blank rows are replaced.
  void addRowsFromDrafts(Iterable<RowDraft> fresh) {
    final list = [for (final d in fresh) RowDraft(type: d.type, value: d.value.text.trim(), score: d.score.text.trim())];
    if (rows.every((r) => r.isBlank)) {
      for (final r in rows) {
        r.dispose();
      }
      rows.clear();
    }
    rows.addAll(list);
    if (rows.isEmpty) rows.add(blankRow());
    _fixRowTypes();
    _notify();
  }

  // ---- saving new entries -------------------------------------------------------------------------------------------

  Map<String, dynamic> _payload(String type, String value, String score) => {
        'customerName': selectedName.trim(),
        'value': value.trim(),
        'entryDate': entryDate,
        'score': score.trim().isEmpty ? null : score.trim(),
        'betType': type,
        'station': station,
        'note': note.text.trim().isEmpty ? null : note.text.trim(),
      }..removeWhere((k, v) => v == null);

  /// Saves every complete row of the form as its own entry. A half-filled row blocks the whole submit.
  Future<void> submit() async {
    formError = '';
    final started = rows.where((r) => !r.isBlank).toList();
    if (selectedName.isEmpty || started.isEmpty) {
      formError = 'Nhập ít nhất một số';
      _notify();
      return;
    }
    if (!started.every((r) => r.isComplete)) {
      formError = 'Nhập đủ Hạng mục, Số và Điểm vào';
      _notify();
      return;
    }
    submitting = true;
    _notify();
    final failed = <String>[];
    var queued = 0;
    var saved = 0;
    for (final r in started) {
      try {
        final res = await store.createEntry(_payload(r.type, r.value.text, r.score.text));
        entries.insert(0, res.entry);
        if (res.queued) queued++;
        saved++;
        rows.remove(r);
        r.dispose();
      } on ApiError catch (e) {
        failed.add('${betTypeLabel(r.type)} "${r.value.text}": ${e.message}');
      } catch (_) {
        failed.add('${betTypeLabel(r.type)} "${r.value.text}": lỗi không rõ');
      }
    }
    if (rows.isEmpty) rows.add(blankRow());
    if (failed.isNotEmpty) formError = failed.join(' · ');
    if (queued > 0) notice = 'Đang offline: $queued số liệu đã lưu trên máy, sẽ tự đồng bộ khi có mạng.';
    if (saved > 0) note.clear();
    flashAdded(saved, queued: queued);
    pending = await store.pendingCount();
    submitting = false;
    _notify();
  }

  /// Saves the ticked preview rows (paste / photo). Returns the error text, or '' when all went well.
  Future<String> saveDrafts(List<RowDraft> picked, {required void Function(RowDraft) onSaved}) async {
    final failed = <String>[];
    var queued = 0;
    var saved = 0;
    for (final r in picked) {
      try {
        final res = await store.createEntry(_payload(r.type, r.value.text, r.score.text));
        entries.insert(0, res.entry);
        if (res.queued) queued++;
        saved++;
        onSaved(r);
      } on ApiError catch (e) {
        failed.add('${betTypeLabel(r.type)} "${r.value.text}": ${e.message}');
      } catch (_) {
        failed.add('${betTypeLabel(r.type)} "${r.value.text}": lỗi không rõ');
      }
    }
    if (queued > 0) notice = 'Đang offline: $queued số liệu đã lưu trên máy, sẽ tự đồng bộ khi có mạng.';
    flashAdded(saved, queued: queued);
    pending = await store.pendingCount();
    _notify();
    return failed.join(' · ');
  }

  // ---- edit / delete --------------------------------------------------------------------------------------------------

  /// Returns an error text, or '' on success (also when it was queued or became a conflict).
  Future<String> saveEdit(Entry base, {required String value, required String score, required String note}) async {
    if (value.trim().isEmpty) return 'Vui lòng nhập số liệu';
    final changes = <String, dynamic>{
      'customerName': base.customerName,
      'value': value.trim(),
      'entryDate': base.entryDate,
      'score': score.trim(),
      'betType': base.type,
      'note': note.trim(),
    };
    try {
      final res = await store.updateEntry(base, changes);
      final i = entries.indexWhere((e) => e.id == base.id);
      if (i != -1) entries[i] = res.entry;
      if (res.queued) {
        notice = 'Đang offline: thay đổi đã lưu trên máy, sẽ tự đồng bộ khi có mạng.';
        pending = await store.pendingCount();
      }
      _notify();
      return '';
    } on ApiError catch (e) {
      if (e.status == 409 && e.data?['conflict'] == true) {
        conflicts.add(SyncConflict(opId: null, entryId: base.id, mine: changes, server: Map<String, dynamic>.from(e.data!['server'] as Map)));
        _notify();
        return '';
      }
      return e.message;
    }
  }

  /// Deletes one entry (also offline: it is queued). Returns an error text or ''.
  Future<String> deleteEntry(Entry e) async {
    try {
      await store.deleteEntry(e.id); // offline: queued and hidden at once; an entry never sent is just forgotten
      entries.removeWhere((x) => x.id == e.id);
      pending = await store.pendingCount();
      _notify();
      return '';
    } on ApiError catch (err) {
      return err.message;
    }
  }

  /// One DELETE per entry (the password-protected bulk endpoint is a different feature). Returns the number that failed.
  Future<int> deleteMany(List<Entry> list) async {
    var failed = 0;
    for (final e in list) {
      try {
        await store.deleteEntry(e.id);
        entries.removeWhere((x) => x.id == e.id);
      } catch (_) {
        failed++;
      }
    }
    pending = await store.pendingCount();
    _notify();
    return failed;
  }

  // ---- list --------------------------------------------------------------------------------------------------------

  List<Entry> get customerEntries => selectedName.isEmpty ? const [] : [for (final e in entries) if (e.customerName == selectedName) e];

  /// The day the list shows: the one picked in its own filter, else the day being entered in the form ('' = every day).
  String get listDate => filter.anyDate ? '' : (filter.date.isNotEmpty ? filter.date : entryDate);

  /// True while the list simply follows the form (the day and, for one customer, the đài chosen above it).
  bool get followsForm => !filter.anyDate && filter.date.isEmpty;

  /// What the list shows: the chosen customer's entries of the chosen day and đài (not every day), until "Mọi ngày" is picked.
  List<Entry> filtered({required bool masked}) {
    final byDay = EntryFilter(q: filter.q, type: filter.type, all: filter.all, date: listDate);
    final list = filterEntries(entries, byDay, customerName: selectedName, masked: masked);
    if (!followsForm || filter.all || station.isEmpty) return list;
    return [for (final e in list) if ((e.station ?? '').isEmpty ? station == 'mb' : e.station == station) e];
  }

  void touchFilter() => _notify();


  // ---- syntax templates (paste importer) ----------------------------------------------------------------------------

  SavedTemplate? get savedTemplate {
    for (final t in templates) {
      if (t.customerName == selectedName) return t;
    }
    return null;
  }

  Future<String> saveTemplate(SyntaxTemplate cfg) async {
    if (selectedName.isEmpty) return '';
    try {
      final res = await api.post('/me/syntax-templates', {'customerName': selectedName, 'config': cfg.toJson()});
      final saved = SavedTemplate('${res['id']}', selectedName, SyntaxTemplate.fromJson(res['config']));
      templates = [...templates.where((t) => t.customerName != selectedName), saved];
      _notify();
      return 'Đã lưu mẫu cho khách này.';
    } on ApiError catch (e) {
      return e.message;
    }
  }

  Future<String> deleteTemplate() async {
    final t = savedTemplate;
    if (t == null) return '';
    try {
      await api.delete('/me/syntax-templates/${t.id}');
      templates = templates.where((x) => x.id != t.id).toList();
      _notify();
      return 'Đã xoá mẫu.';
    } on ApiError catch (e) {
      return e.message;
    }
  }
}
