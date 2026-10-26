import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/lottery_stations.dart';
import '../../core/scoring_config.dart';
import '../entries/entry_model.dart' as stored;
import '../entries/offline_store.dart';
import '../scoring/entry_model.dart';
import '../scoring/scoring_data.dart';
import '../scoring/scoring_days.dart';
import '../scoring/scoring_logic.dart';
import 'lottery_columns.dart';
import 'ocr_service.dart';

/// tier -> numbers of one result form ('' = empty box). Every tier is a list (dacBiet / giaiNhat have one box).
typedef ResultForm = Map<String, List<String>>;

const singleTiers = ['dacBiet', 'giaiNhat']; // stored by the API as one string, every other group is a list

/// An empty form for [structure].
ResultForm blankForm(List<Prize> structure) => {for (final p in structure) p.tier: List<String>.filled(p.count, '', growable: true)};

/// A form for [structure] filled from a saved result / recognised column where the shapes fit.
ResultForm shapeForm(List<Prize> structure, Map<String, dynamic>? values) {
  final out = blankForm(structure);
  if (values == null) return out;
  for (final p in structure) {
    final v = values[p.tier];
    // a group may hold more numbers than the region's usual count (extra boxes): keep them all
    if (v is List && v.length >= p.count) {
      out[p.tier] = [for (final x in v) '$x'];
    } else if (v is String && p.count == 1) {
      out[p.tier] = [v];
    }
  }
  return out;
}

int filledCount(ResultForm f) => f.values.expand((l) => l).where((v) => v.trim().isNotEmpty).length;

/// How many boxes a group may have beyond the region's usual count (same limit as the API).
const maxExtraCells = 20;

/// The region's usual count of every group must be filled; boxes added beyond it are optional (empty ones are dropped on save).
bool requiredFilled(List<Prize> structure, ResultForm? f) {
  if (f == null) return false;
  return structure.every((p) {
    final v = f[p.tier];
    return v != null && v.length >= p.count && v.take(p.count).every((x) => x.trim().isNotEmpty);
  });
}

/// Numbers to save for [p]: the usual boxes plus the extra boxes that were filled in.
List<String> valuesOf(Prize p, List<String> v) => [
      for (var i = 0; i < v.length; i++)
        if (i < p.count || v[i].trim().isNotEmpty) v[i].trim(),
    ];

/// Request body of POST /lottery-results.
Map<String, dynamic> resultBody(String date, String station, List<Prize> structure, ResultForm f) {
  final body = <String, dynamic>{'drawDate': date, 'station': station};
  for (final p in structure) {
    final v = valuesOf(p, f[p.tier]!);
    body[p.tier] = singleTiers.contains(p.tier) ? v.first : v;
  }
  return body;
}

String _digits(String s, int max) {
  final d = s.replaceAll(RegExp(r'\D'), '');
  return d.length > max ? d.substring(0, max) : d;
}

/// State and logic of "Nhập kết quả": the result form (Miền Bắc) or the per-station table (Miền Trung / Miền Nam), reading
/// results from a photo, and the "Điểm ra" of the day that is calculated and stored after a save.
class ResultsController extends ChangeNotifier {
  ResultsController(this.api, this.stations, {OcrService? ocr, String? initialDate})
      : _ocr = ocr ?? OcrService(),
        date = isIsoDate(initialDate) ? initialDate! : todayIso();

  final ApiClient api;
  final LotteryStations stations;
  final OcrService _ocr;

  String date;
  String region = 'mb';

  // Điểm ra data
  List<Entry> entries = [];
  List<CustomerRec> customers = [];
  RatesMap rates = Map<String, dynamic>.from(defaultRates);
  Map<String, Map<String, dynamic>> dayResults = {};
  String customerFilter = '';

  bool entriesLoading = true;
  String? entriesError;
  bool dayLoading = false;
  String? error;
  String? saveMsg;
  String? syncMsg;
  String? syncError;
  bool saving = false;
  String deleting = ''; // station being deleted ('' = none)

  // Miền Bắc
  ResultForm mbForm = blankForm(const []);
  bool mbSaved = false;
  bool mbLocked = false;

  // Miền Trung / Miền Nam: one form per station (the stations drawing that day, plus the ones added by hand); one is shown at a time
  final Map<String, ResultForm> board = {};
  List<String> extraStations = []; // not on the day's schedule: saved earlier that day, or added with "+ Đài khác"
  String activeStation = '';
  bool gridOpen = false; // the prize grid is folded behind "Nhập tay các giải" until there is something in it
  final Set<String> boardSaved = {};
  final Set<String> boardRead = {}; // filled from a photo: empty cells are flagged
  final Set<String> boardEdit = {}; // saved / read column that was unlocked

  // photo
  bool ocrRunning = false;
  String? photoPath; // the picture that was read (shown as a preview)
  String? ocrError;
  String? ocrNote;
  List<String> ocrWarnings = [];

  int _dayToken = 0;
  bool _disposed = false;

  List<Prize> get structure => stations.regionOf(region).structure;
  int get totalBoxes => structure.fold(0, (n, p) => n + p.count);
  List<String> get scheduledStations => region == 'mb' ? const [] : stations.stationsOn(region, date);
  /// After a photo was read: only the stations that are in it are shown (the other stations of the day are hidden until the day,
  /// the region or the table is changed). null = show the whole day.
  Set<String>? photoOnly;
  List<String> get boardStations {
    if (region == 'mb') return const [];
    final all = [...scheduledStations, ...extraStations.where((id) => !scheduledStations.contains(id))];
    final only = photoOnly;
    return only == null ? all : [for (final id in all) if (only.contains(id)) id];
  }

  /// Every other station of the region (the whole catalogue), to add with "+ Đài khác".
  List<({String value, String label})> get otherStations => region == 'mb'
      ? const []
      : [
          for (final id in stations.regionOf(region).stations.keys)
            if (!boardStations.contains(id)) (value: id, label: stations.stationName(id)),
        ];

  /// The station shown in the form ('mb' for Miền Bắc, '' when the region has none that day).
  String get curStation {
    if (region == 'mb') return 'mb';
    final all = boardStations;
    return all.contains(activeStation) ? activeStation : (all.isEmpty ? '' : all.first);
  }

  /// The form of [station] (null or 'mb' = the Miền Bắc form).
  ResultForm? formOf(String? station) => (station == null || station == 'mb') ? mbForm : board[station];

  bool lockedOf(String? station) => (station == null || station == 'mb') ? mbLocked : boardLocked(station);
  bool savedOf(String? station) => (station == null || station == 'mb') ? mbSaved : boardSaved.contains(station);
  int filledOf(String? station) => filledCount(formOf(station) ?? const {});
  String get regionName => stations.regionOf(region).name;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // ---- loading ----------------------------------------------------------------------------------------------

  Future<void> init() async {
    mbForm = blankForm(structure);
    await Future.wait([stations.load(api), loadEntryData()]);
    await loadDay();
  }

  Future<void> loadEntryData() async {
    entriesLoading = true;
    entriesError = null;
    notifyListeners();
    try {
      final r = await Future.wait([fetchAllEntries(api, overlay: true), fetchCustomers(api).catchError((_) => <CustomerRec>[]), fetchAccountRates(api)]);
      entries = r[0] as List<Entry>;
      customers = r[1] as List<CustomerRec>;
      rates = r[2] as RatesMap;
    } on ApiError catch (e) {
      entriesError = e.message;
    } catch (_) {
      entriesError = 'Không tải được số liệu';
    }
    entriesLoading = false;
    notifyListeners();
  }

  /// Reloads what is saved for the chosen day and rebuilds the form / table from it.
  Future<void> loadDay({bool keepMessages = false}) async {
    final token = ++_dayToken;
    dayLoading = true;
    if (!keepMessages) {
      error = null;
      saveMsg = null;
    }
    notifyListeners();
    try {
      try {
        await (await _store()).flush();
      } catch (_) {/* sending later is fine */}
      final res = await fetchDayResults(api, date);
      if (token != _dayToken) return;
      dayResults = res;
      _rebuildForms();
    } on ApiError catch (e) {
      if (token != _dayToken) return;
      error = e.status == 0 ? 'Đang offline và chưa có kết quả đã lưu của ngày này. Bạn vẫn nhập và lưu được, kết quả sẽ tự gửi lên khi có mạng.' : e.message;
      dayResults = {};
      _rebuildForms();
    } catch (_) {
      if (token != _dayToken) return;
      error = 'Không tải được kết quả xổ số';
      dayResults = {};
      _rebuildForms();
    }
    if (token == _dayToken) {
      dayLoading = false;
      notifyListeners();
    }
  }

  void _rebuildForms() {
    boardSaved.clear();
    boardRead.clear();
    boardEdit.clear();
    board.clear();
    if (region == 'mb') {
      final saved = dayResults['mb'];
      mbForm = shapeForm(structure, saved);
      mbSaved = saved != null;
      mbLocked = saved != null;
    } else {
      // stations of this region with a saved result that day but not on the schedule (added by hand earlier)
      extraStations = [
        for (final id in dayResults.keys)
          if (id != 'mb' && stations.regionOf(id).id == region && !scheduledStations.contains(id)) id,
      ];
      for (final st in boardStations) {
        board[st] = shapeForm(structure, dayResults[st]);
        if (dayResults[st] != null) boardSaved.add(st);
      }
    }
    _autoOpenGrid();
  }

  /// The grid opens by itself as soon as there is anything in it (a saved result, a photo, typing).
  void _autoOpenGrid() {
    if (filledOf(curStation) > 0) gridOpen = true;
  }

  void toggleGrid() {
    gridOpen = !gridOpen;
    notifyListeners();
  }

  void selectStation(String st) {
    activeStation = st;
    _autoOpenGrid();
    notifyListeners();
  }

  /// "+ Đài khác": an out-of-schedule station of the region becomes one more choice and is selected.
  void addStation(String id) {
    if (id.isEmpty || region == 'mb') return;
    if (!extraStations.contains(id) && !scheduledStations.contains(id)) extraStations = [...extraStations, id];
    photoOnly = photoOnly == null ? null : {...photoOnly!, id};
    board[id] ??= blankForm(structure);
    activeStation = id;
    notifyListeners();
  }

  /// Adds one box to a group that has more numbers than usual ([station] null = Miền Bắc). Never beyond what the API accepts.
  void addCell(String? station, Prize p) {
    final list = formOf(station)?[p.tier];
    if (list == null || singleTiers.contains(p.tier) || list.length >= p.count + maxExtraCells) return;
    list.add('');
    notifyListeners();
  }

  /// Removes the last box added beyond the usual count.
  void removeCell(String? station, Prize p) {
    final list = formOf(station)?[p.tier];
    if (list == null || list.length <= p.count) return;
    list.removeLast();
    notifyListeners();
  }

  Future<void> setDate(String iso) async {
    if (iso == date || !isIsoDate(iso)) return;
    date = iso;
    photoOnly = null;
    ocrNote = null;
    ocrWarnings = [];
    photoPath = null;
    gridOpen = false;
    mbForm = blankForm(structure);
    notifyListeners();
    await loadDay();
  }

  Future<void> shiftDay(int delta) => setDate(shiftIso(date, delta));

  Future<void> setRegion(String r) async {
    if (r == region) return;
    region = r;
    photoOnly = null;
    ocrNote = null;
    ocrWarnings = [];
    ocrError = null;
    photoPath = null;
    gridOpen = false;
    extraStations = [];
    activeStation = '';
    mbForm = blankForm(structure);
    notifyListeners();
    await loadDay();
  }

  void setCustomerFilter(String name) {
    customerFilter = name;
    notifyListeners();
  }

  // ---- editing ----------------------------------------------------------------------------------------------

  bool boardLocked(String st) => (boardSaved.contains(st) || boardRead.contains(st)) && !boardEdit.contains(st);

  int boardFilled(String st) => filledCount(board[st] ?? const {});

  /// A cell is wrong when it has digits of the wrong length, or is empty in a column read from a photo.
  /// (An extra box beyond the usual count may stay empty.)
  bool cellBad(String st, Prize p, String v, [int index = 0]) {
    final t = v.trim();
    return t.isNotEmpty ? t.length != p.digits : (boardRead.contains(st) && index < p.count);
  }

  /// [station] null = the Miền Bắc form.
  void setCell(String? station, Prize p, int index, String value) {
    final form = station == null ? mbForm : board[station];
    final list = form?[p.tier];
    if (list == null || index >= list.length) return;
    list[index] = _digits(value, p.digits);
    _autoOpenGrid();
    notifyListeners();
  }

  void unlockMb() {
    mbLocked = false;
    notifyListeners();
  }

  void unlockColumn(String st) {
    boardEdit.add(st);
    notifyListeners();
  }

  void unlockAllColumns() {
    boardEdit.addAll(boardStations);
    notifyListeners();
  }

  void clearForm() {
    if (region != 'mb') {
      for (final st in boardStations) {
        board[st] = blankForm(structure);
        boardRead.remove(st);
        boardEdit.add(st);
      }
      ocrWarnings = [];
    } else {
      mbForm = blankForm(structure);
      mbLocked = false;
    }
    photoPath = null;
    photoOnly = null;
    for (final st in boardStations) {
      board[st] ??= blankForm(structure);
    }
    ocrError = null;
    ocrNote = null;
    notifyListeners();
  }

  // ---- save / delete ----------------------------------------------------------------------------------------

  Future<void> save() => region == 'mb' ? _saveMb() : _saveBoard();

  Future<void> _saveMb() async {
    error = null;
    saveMsg = null;
    if (!requiredFilled(structure, mbForm)) {
      error = 'Vui lòng nhập đủ $totalBoxes số trước khi lưu.';
      notifyListeners();
      return;
    }
    saving = true;
    notifyListeners();
    try {
      final queued = await (await _store()).saveResult(resultBody(date, 'mb', structure, mbForm));
      saveMsg = 'Đã lưu kết quả xổ số Miền Bắc ngày ${viDate(date)}.${queued ? _offlineNote : ''}';
      mbSaved = true;
      mbLocked = true;
      await _afterSave();
    } on ApiError catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Không lưu được kết quả xổ số';
    }
    saving = false;
    notifyListeners();
  }

  Future<void> _saveBoard() async {
    error = null;
    saveMsg = null;
    final todo = boardStations.where((st) => boardFilled(st) > 0).toList();
    if (todo.isEmpty) {
      error = 'Chưa có số nào để lưu.';
      notifyListeners();
      return;
    }
    final total = totalBoxes;
    final partial = todo.where((st) => !requiredFilled(structure, board[st])).toList();
    if (partial.isNotEmpty) {
      error = '${partial.map(stations.stationName).join(', ')}: chưa nhập đủ $total số. Điền đủ hoặc xoá hết cột đó rồi lưu lại.';
      notifyListeners();
      return;
    }
    saving = true;
    notifyListeners();
    try {
      var queued = false;
      for (final st in todo) {
        queued = await (await _store()).saveResult(resultBody(date, st, structure, board[st]!)) || queued;
        boardSaved.add(st);
        boardRead.remove(st);
        boardEdit.remove(st);
      }
      saveMsg = 'Đã lưu kết quả ${todo.map(stations.stationName).join(', ')} ngày ${viDate(date)}.${queued ? _offlineNote : ''}';
      await _afterSave();
    } on ApiError catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Không lưu được kết quả xổ số';
    }
    saving = false;
    notifyListeners();
  }

  OfflineStore? _offline;
  Future<OfflineStore> _store() async => _offline ??= await OfflineStore.open(api, api.auth);
  static const _offlineNote = ' Đang offline: kết quả được lưu trên máy và sẽ tự gửi lên khi có mạng.';

  Future<void> _afterSave() async {
    try {
      dayResults = await fetchDayResults(api, date);
    } catch (_) {/* the sync below simply uses what is known */}
    await syncScores();
  }

  /// Deletes the saved result of [station] ('mb' for Miền Bắc).
  Future<void> deleteResult(String station) async {
    error = null;
    saveMsg = null;
    deleting = station;
    notifyListeners();
    try {
      final waiting = await (await _store()).forgetResult(date, station);
      try {
        await api.delete('/lottery-results?date=$date&station=${Uri.encodeQueryComponent(station)}');
      } on ApiError catch (e) {
        if (e.status != 0 || !waiting) rethrow; // only a result that never reached the server can be dropped offline
      }
      if (station == 'mb') {
        mbForm = blankForm(structure);
        mbSaved = false;
        mbLocked = false;
      } else {
        board[station] = blankForm(structure);
        boardSaved.remove(station);
        boardRead.remove(station);
        boardEdit.remove(station);
      }
      dayResults.remove(station);
      saveMsg = 'Đã xoá kết quả xổ số ${stations.stationName(station)} ngày ${viDate(date)}.';
    } on ApiError catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Không xoá được';
    }
    deleting = '';
    notifyListeners();
  }

  // ---- Điểm ra ----------------------------------------------------------------------------------------------

  RatesMap? _customerRates(String name) {
    for (final c in customers) {
      if (c.name == name) return c.scoringRates;
    }
    return null;
  }

  String? _customerRegion(String name) {
    for (final c in customers) {
      if (c.name == name) return c.homeRegion;
    }
    return null;
  }

  /// Calculated "Điểm ra" of an entry (null = the day has no result for any of its stations yet).
  double? scoreOf(Entry e) => entryOutTotal(
        entry: e,
        stations: stations,
        accountRates: rates,
        customerRates: _customerRates(e.customerName),
        customerRegion: _customerRegion(e.customerName),
        resultOf: (st) => dayResults[st],
      );

  List<Entry> get dayEntries => [
        for (final e in entries)
          if (e.entryDate == date && (customerFilter.isEmpty || (e.customerName.isEmpty ? noCustomerName : e.customerName) == customerFilter)) e,
      ];

  /// Entries of the chosen day grouped by customer (sorted by name).
  List<({String name, List<Entry> entries})> get groups {
    final by = <String, List<Entry>>{};
    for (final e in dayEntries) {
      by.putIfAbsent(e.customerName.isEmpty ? noCustomerName : e.customerName, () => []).add(e);
    }
    final names = by.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [for (final n in names) (name: n, entries: by[n]!)];
  }

  /// Asked before an automatic update would OVERWRITE an "Điểm ra" that is already there with a different number
  /// (a misread result would otherwise silently change every customer's money that day). null = no question.
  Future<bool> Function(int total, int overwrites)? confirmOverwrite;

  /// What the last automatic update replaced, so [undoScores] can put it back (null = nothing to undo).
  List<({String id, String prev})>? undoItems;
  bool undoing = false;

  static bool _isOverwrite(String prev, String next) {
    if (prev.isEmpty) return false;
    double? n(String t) => double.tryParse(t.replaceAll(RegExp(r'[^\d.-]'), ''));
    final a = n(prev), b = n(next);
    return a == null || b == null || a != b;
  }

  Future<void> _writeResult(Entry e, String value) async {
    await (await _store()).updateEntry(
      stored.Entry.fromJson({'id': e.id, 'customerName': e.customerName, 'entryDate': e.entryDate, 'value': e.value, 'updatedAt': e.updatedAt}),
      {'result': value},
    );
    final i = entries.indexWhere((x) => x.id == e.id);
    if (i != -1) entries[i] = e.withResult(value);
  }

  /// Stores the calculated value on every entry of the day (after a result was saved).
  Future<void> syncScores() async {
    syncMsg = null;
    syncError = null;
    undoItems = null;
    try {
      entries = await fetchAllEntries(api, overlay: true);
    } catch (_) {/* score what is already loaded */}
    final changes = <({Entry e, String value, String prev})>[];
    for (final e in List<Entry>.of(entries)) {
      if (e.entryDate != date) continue;
      final v = scoreOf(e);
      if (v == null) continue;
      final s = numToString(v);
      if (s == (e.result ?? '')) continue;
      changes.add((e: e, value: s, prev: e.result ?? ''));
    }
    if (changes.isEmpty) return;
    final overwrites = changes.where((c) => _isOverwrite(c.prev, c.value)).length;
    if (overwrites > 0 && confirmOverwrite != null) {
      final ok = await confirmOverwrite!(changes.length, overwrites);
      if (!ok) {
        syncMsg = 'Đã lưu kết quả xổ số, chưa cập nhật Điểm ra (bạn chọn không ghi đè).';
        return;
      }
    }
    final done = <({String id, String prev})>[];
    var failed = 0;
    for (final c in changes) {
      try {
        await _writeResult(c.e, c.value);
        done.add((id: c.e.id, prev: c.prev));
      } catch (_) {
        failed++;
      }
    }
    if (done.isNotEmpty) {
      undoItems = done;
      syncMsg = 'Đã tính và lưu điểm ra cho ${done.length} số liệu.';
    }
    if (failed > 0) syncError = '$failed số liệu chưa lưu được điểm ra, lưu lại kết quả để thử lại.';
  }

  /// Puts back the "Điểm ra" values the last automatic update replaced.
  Future<void> undoScores() async {
    final items = undoItems;
    if (items == null || undoing) return;
    undoing = true;
    syncError = null;
    notifyListeners();
    var back = 0, failed = 0;
    for (final it in items) {
      final i = entries.indexWhere((x) => x.id == it.id);
      if (i == -1) continue;
      try {
        await _writeResult(entries[i], it.prev);
        back++;
      } catch (_) {
        failed++;
      }
    }
    undoItems = null;
    undoing = false;
    syncMsg = 'Đã hoàn tác Điểm ra của $back số liệu.';
    if (failed > 0) syncError = '$failed số liệu chưa hoàn tác được.';
    notifyListeners();
  }

  // ---- photo ------------------------------------------------------------------------------------------------

  /// Takes / picks a photo and fills the form (Miền Bắc) or the table (Miền Trung / Miền Nam). Nothing is saved.
  Future<void> readPhoto({required bool camera}) async {
    if (ocrRunning) return;
    ocrError = null;
    ocrNote = null;
    ocrWarnings = [];
    String? path;
    try {
      path = await _ocr.pick(camera: camera);
    } catch (e) {
      ocrError = describeOcrError(e);
      notifyListeners();
      return;
    }
    if (path == null) return;
    ocrRunning = true;
    photoPath = path;
    notifyListeners();
    try {
      final res = await _ocr.read(path);
      if (region == 'mb') {
        _applyNorth(res);
      } else {
        await _applySouthCentral(res);
      }
    } catch (e) {
      ocrError = describeOcrError(e);
    }
    ocrRunning = false;
    gridOpen = true; // show what was read
    notifyListeners();
  }

  void _applyNorth(OcrResult res) {
    // Rows from the word positions (the plain text order of the reader can run down the columns).
    final ordered = orderedDigitText(uprightWords(repairDigitWords(res.words), lengthsDecreaseDownward: true));
    // Read into empty boxes, then put the numbers found over the old ones: a photo read again (or over typed numbers) must
    // replace them, not be reported as "nothing recognised" because every box was already filled.
    final fresh = {for (final e in mbForm.entries) e.key: List<String>.filled(e.value.length, '')};
    guessNorthForm(ordered.isEmpty ? res.text : ordered, fresh);
    for (final e in fresh.entries) {
      for (var i = 0; i < e.value.length; i++) {
        if (e.value[i].isNotEmpty) mbForm[e.key]![i] = e.value[i];
      }
    }
    mbLocked = true;
    if (filledCount(fresh) == 0) {
      ocrError = 'Không nhận ra số nào trong ảnh. Hãy chụp rõ cả bảng hoặc nhập tay.';
    } else {
      saveMsg = 'Đã điền từ ảnh. Kiểm tra lại các ô rồi bấm "Lưu kết quả".';
    }
  }

  Future<void> _applySouthCentral(OcrResult res) async {
    await stations.load(api);
    final upright = uprightWords(res.words, lengthsDecreaseDownward: false);
    final parsed = parseColumns(upright, stations);
    if (parsed.columns.isEmpty) {
      ocrError = 'Không nhận ra bảng kết quả (cần thấy giải đặc biệt 6 số của từng đài). Hãy chụp rõ cả bảng hoặc nhập tay.';
      return;
    }
    // Which region and day the photo is of: from its title ("XSMT ... 09/10/2026"), else what is selected now.
    // The region: the title ("XSMN", "Miền Nam"), else the one the station names in the headers belong to, else the selected one.
    final titleRegion = regionFromTitle(res.words);
    final headerRegion = regionFromColumns(parsed.columns, stations);
    final seenRegion = titleRegion == 'mt' || titleRegion == 'mn' ? titleRegion! : (headerRegion ?? (region == 'mb' ? 'mn' : region));
    // The day: the date printed in the photo; when it cannot be read, the recent day on which the stations named in the
    // headers all draw; else the selected day.
    // (order: the printed date; the weekday word "Thứ hai"; the stations named; the selected day)
    var seenDate = parsed.date ?? date;
    if (parsed.date == null) {
      final weekday = weekdayFromWords(res.words);
      final named = [for (final c in parsed.columns) if (c.station != null) c.station!];
      seenDate = weekday != null ? dateOfWeekdayOnOrBefore(weekday, date) : (inferDateFromStations(seenRegion, named, date, stations, columnCount: parsed.columns.length) ?? date);
    }
    final regionStations = stations.regionOf(seenRegion).stations.keys.where((id) => id != 'mb').toList();
    assignStations(parsed.columns, stations.stationsOn(seenRegion, seenDate), stations, others: regionStations);
    if (seenRegion != region || seenDate != date) {
      region = seenRegion;
      date = seenDate;
      ocrNote = 'Ảnh là kết quả ${stations.regionOf(seenRegion).name} ngày ${viDate(seenDate)}; đã chuyển sang miền và ngày này.';
    }
    photoOnly = {for (final c in parsed.columns) if (c.station != null) c.station!};
    await loadDay(keepMessages: true);
    // Every recognised column goes straight into the table under its station.
    var firstSet = false;
    for (final c in parsed.columns) {
      final st = c.station;
      if (st != null && !board.containsKey(st)) {
        // named in the photo but not on this day's schedule: it becomes one more choice, like "+ Đài khác"
        extraStations = [...extraStations, st];
        board[st] = blankForm(structure);
      }
      if (st == null || !board.containsKey(st)) {
        ocrWarnings.add('Có một cột chưa xác định được đài, nên chưa điền vào bảng.');
        continue;
      }
      board[st] = shapeForm(structure, c.values);
      if (!firstSet) {
        activeStation = st;
        firstSet = true;
      }
      boardRead.add(st);
      boardEdit.remove(st);
      if (!c.complete) ocrWarnings.add('${stations.stationName(st)}: ${c.issues.join('; ')}');
    }
    saveMsg = 'Đã điền bảng từ ảnh. Kiểm tra các ô (ô đỏ là chưa đủ hoặc sai độ dài) rồi bấm "Lưu kết quả".';
  }
}
