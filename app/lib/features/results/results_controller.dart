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
ResultForm blankForm(List<Prize> structure) => {for (final p in structure) p.tier: List<String>.filled(p.count, '')};

/// A form for [structure] filled from a saved result / recognised column where the shapes fit.
ResultForm shapeForm(List<Prize> structure, Map<String, dynamic>? values) {
  final out = blankForm(structure);
  if (values == null) return out;
  for (final p in structure) {
    final v = values[p.tier];
    if (v is List && v.length == p.count) {
      out[p.tier] = [for (final x in v) '$x'];
    } else if (v is String && p.count == 1) {
      out[p.tier] = [v];
    }
  }
  return out;
}

int filledCount(ResultForm f) => f.values.expand((l) => l).where((v) => v.trim().isNotEmpty).length;

/// Request body of POST /lottery-results.
Map<String, dynamic> resultBody(String date, String station, List<Prize> structure, ResultForm f) {
  final body = <String, dynamic>{'drawDate': date, 'station': station};
  for (final p in structure) {
    final v = [for (final x in f[p.tier]!) x.trim()];
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

  // Miền Trung / Miền Nam: one column per station drawing that day
  final Map<String, ResultForm> board = {};
  final Set<String> boardSaved = {};
  final Set<String> boardRead = {}; // filled from a photo: empty cells are flagged
  final Set<String> boardEdit = {}; // saved / read column that was unlocked

  // photo
  bool ocrRunning = false;
  String? ocrError;
  String? ocrNote;
  List<String> ocrWarnings = [];

  int _dayToken = 0;
  bool _disposed = false;

  List<Prize> get structure => stations.regionOf(region).structure;
  int get totalBoxes => structure.fold(0, (n, p) => n + p.count);
  List<String> get boardStations => region == 'mb' ? const [] : stations.stationsOn(region, date);
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
      final r = await Future.wait([fetchAllEntries(api), fetchCustomers(api).catchError((_) => <CustomerRec>[]), fetchAccountRates(api)]);
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
      error = e.message;
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
      for (final st in boardStations) {
        board[st] = shapeForm(structure, dayResults[st]);
        if (dayResults[st] != null) boardSaved.add(st);
      }
    }
  }

  Future<void> setDate(String iso) async {
    if (iso == date || !isIsoDate(iso)) return;
    date = iso;
    ocrNote = null;
    ocrWarnings = [];
    mbForm = blankForm(structure);
    notifyListeners();
    await loadDay();
  }

  Future<void> shiftDay(int delta) => setDate(shiftIso(date, delta));

  Future<void> setRegion(String r) async {
    if (r == region) return;
    region = r;
    ocrNote = null;
    ocrWarnings = [];
    ocrError = null;
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
  bool cellBad(String st, Prize p, String v) {
    final t = v.trim();
    return t.isNotEmpty ? t.length != p.digits : boardRead.contains(st);
  }

  /// [station] null = the Miền Bắc form.
  void setCell(String? station, Prize p, int index, String value) {
    final form = station == null ? mbForm : board[station];
    final list = form?[p.tier];
    if (list == null || index >= list.length) return;
    list[index] = _digits(value, p.digits);
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
    ocrError = null;
    ocrNote = null;
    notifyListeners();
  }

  // ---- save / delete ----------------------------------------------------------------------------------------

  Future<void> save() => region == 'mb' ? _saveMb() : _saveBoard();

  Future<void> _saveMb() async {
    error = null;
    saveMsg = null;
    if (filledCount(mbForm) < totalBoxes) {
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
    final partial = todo.where((st) => boardFilled(st) < total).toList();
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

  /// Calculated "Điểm ra" of an entry (null = the day has no result for any of its stations yet).
  double? scoreOf(Entry e) => entryOutTotal(
        entry: e,
        stations: stations,
        accountRates: rates,
        customerRates: _customerRates(e.customerName),
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

  /// Stores the calculated value on every entry of the day (after a result was saved).
  Future<void> syncScores() async {
    syncMsg = null;
    syncError = null;
    try {
      entries = await fetchAllEntries(api);
    } catch (_) {/* score what is already loaded */}
    var ok = 0, failed = 0;
    for (final e in List<Entry>.of(entries)) {
      if (e.entryDate != date) continue;
      final v = scoreOf(e);
      if (v == null) continue;
      final s = numToString(v);
      if (s == (e.result ?? '')) continue;
      try {
        await (await _store()).updateEntry(
          stored.Entry.fromJson({'id': e.id, 'customerName': e.customerName, 'entryDate': e.entryDate, 'value': e.value}),
          {'result': s},
        );
        final i = entries.indexWhere((x) => x.id == e.id);
        if (i != -1) entries[i] = e.withResult(s);
        ok++;
      } catch (_) {
        failed++;
      }
    }
    if (ok > 0) syncMsg = 'Đã tính và lưu điểm ra cho $ok số liệu.';
    if (failed > 0) syncError = '$failed số liệu chưa lưu được điểm ra, lưu lại kết quả để thử lại.';
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
    notifyListeners();
  }

  void _applyNorth(OcrResult res) {
    final before = filledCount(mbForm);
    guessNorthForm(res.text, mbForm);
    mbLocked = true;
    if (filledCount(mbForm) == before) {
      ocrError = 'Không nhận ra số nào trong ảnh. Hãy chụp rõ cả bảng hoặc nhập tay.';
    } else {
      saveMsg = 'Đã điền từ ảnh. Kiểm tra lại các ô rồi bấm "Lưu kết quả".';
    }
  }

  Future<void> _applySouthCentral(OcrResult res) async {
    await stations.load(api);
    final parsed = parseColumns(res.words, stations);
    if (parsed.columns.isEmpty) {
      ocrError = 'Không nhận ra bảng kết quả (cần thấy giải đặc biệt 6 số của từng đài). Hãy chụp rõ cả bảng hoặc nhập tay.';
      return;
    }
    // Which region and day the photo is of: from its title ("XSMT ... 09/10/2026"), else what is selected now.
    final text = res.words.map((w) => w.text).join(' ').toLowerCase();
    final seenRegion = text.contains('xsmt') ? 'mt' : (text.contains('xsmn') ? 'mn' : region);
    final seenDate = parsed.date ?? date;
    assignStations(parsed.columns, stations.stationsOn(seenRegion, seenDate), stations);
    if (seenRegion != region || seenDate != date) {
      region = seenRegion;
      date = seenDate;
      ocrNote = 'Ảnh là kết quả ${stations.regionOf(seenRegion).name} ngày ${viDate(seenDate)}; đã chuyển sang miền và ngày này.';
    }
    await loadDay(keepMessages: true);
    // Every recognised column goes straight into the table under its station.
    for (final c in parsed.columns) {
      final st = c.station;
      if (st == null || !board.containsKey(st)) {
        ocrWarnings.add('Có một cột chưa xác định được đài, nên chưa điền vào bảng.');
        continue;
      }
      board[st] = shapeForm(structure, c.values);
      boardRead.add(st);
      boardEdit.remove(st);
      if (!c.complete) ocrWarnings.add('${stations.stationName(st)}: ${c.issues.join('; ')}');
    }
    saveMsg = 'Đã điền bảng từ ảnh. Kiểm tra các ô (ô đỏ là chưa đủ hoặc sai độ dài) rồi bấm "Lưu kết quả".';
  }
}
