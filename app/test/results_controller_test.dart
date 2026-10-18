import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/results/results_controller.dart';
import 'package:mamba_app/features/scoring/scoring_controller.dart';

import 'scoring_fixtures.dart';

const date = '2026-10-07';

class FakeServer {
  final saved = <String, Map<String, dynamic>>{}; // station -> result (as the server stores it)
  final posts = <Map<String, dynamic>>[];
  final patches = <String, String>{}; // entry id -> result
  final deletes = <String>[];
  var entries = <Map<String, dynamic>>[
    {'id': 'e1', 'customerName': 'An', 'entryDate': date, 'value': '47', 'score': '10', 'betType': 'lo', 'station': 'mn-dongnai', 'result': null},
    {'id': 'e2', 'customerName': 'An', 'entryDate': '2026-10-06', 'value': '47', 'score': '10', 'betType': 'lo', 'station': 'mn-dongnai', 'result': null},
    {'id': 'e3', 'customerName': 'Bình', 'entryDate': date, 'value': '56', 'score': '100000', 'betType': 'de', 'station': 'mn-cantho', 'result': null},
  ];

  Future<http.Response> handle(http.Request r) async {
    final path = r.url.path.replaceFirst('/api', '');
    final q = r.url.queryParameters;
    http.Response ok(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    if (path == '/lottery-results' && r.method == 'GET') {
      // results exist for `date` only
      final day = q['date'] == date ? saved : <String, Map<String, dynamic>>{};
      if (q['all'] == '1') return ok({'results': [for (final e in day.entries) {'drawDate': q['date'], 'station': e.key, ...e.value}]});
      return ok({'result': day[q['station']]});
    }
    if (path == '/lottery-results' && r.method == 'POST') {
      final b = jsonDecode(r.body) as Map<String, dynamic>;
      posts.add(b);
      saved[b['station'] as String] = {...b}..remove('drawDate')..remove('station');
      return ok({'result': b});
    }
    if (path == '/lottery-results' && r.method == 'DELETE') {
      deletes.add('${q['date']}|${q['station']}');
      saved.remove(q['station']);
      return ok({'ok': true});
    }
    if (path == '/me/entries' && r.method == 'GET') return ok({'entries': entries, 'total': entries.length, 'offset': 0, 'hasMore': false});
    if (path.startsWith('/me/entries/') && r.method == 'PATCH') {
      final id = path.split('/').last;
      patches[id] = (jsonDecode(r.body) as Map)['result'] as String;
      return ok({'id': id});
    }
    if (path == '/me/customers') {
      return ok({'customers': [{'id': 'c1', 'name': 'An', 'phone': '', 'scoringRates': null}, {'id': 'c2', 'name': 'Bình', 'phone': '', 'scoringRates': null}]});
    }
    if (path == '/me/scoring-settings') {
      return ok({'rates': {'lo': {'rate': 3.5, 'tiers': allBaseTiers, 'digits': 2}, 'de': {'rate': 70, 'tiers': ['dacBiet'], 'digits': 2}}});
    }
    return http.Response('{"error":"?"}', 404);
  }
}

ApiClient client(FakeServer f) => ApiClient(AuthStore(), client: MockClient(f.handle));

void fillColumn(ResultsController c, String st, {String tam = '11', String db = '123456'}) {
  for (final p in c.structure) {
    for (var k = 0; k < p.count; k++) {
      final v = p.tier == 'giaiTam' ? tam : (p.tier == 'dacBiet' ? db : '1' * p.digits);
      c.setCell(st, p, k, v);
    }
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('Miền Nam table: partly filled column is an error; full columns are saved and the day is scored', () async {
    final f = FakeServer();
    final c = ResultsController(client(f), testStations(), initialDate: date);
    await c.init();
    c.setRegion('mn');
    await Future<void>.delayed(Duration.zero);
    await c.loadDay();
    expect(c.boardStations, ['mn-dongnai', 'mn-cantho', 'mn-soctrang']);

    // typing keeps digits only and never more than the prize has
    final tam = c.structure.firstWhere((p) => p.tier == 'giaiTam');
    c.setCell('mn-dongnai', tam, 0, '4a7x9');
    expect(c.board['mn-dongnai']!['giaiTam'], ['47']);

    // a partly filled column is an error and nothing is sent
    await c.save();
    expect(c.error, contains('Đồng Nai'));
    expect(f.posts, isEmpty);

    fillColumn(c, 'mn-dongnai', tam: '47');
    fillColumn(c, 'mn-cantho', db: '999956');
    await c.save();
    expect(c.error, isNull);
    expect(f.posts.map((p) => p['station']), ['mn-dongnai', 'mn-cantho']);
    expect(f.posts.first['dacBiet'], '123456'); // single tiers go as strings
    expect(f.posts.first['giaiBa'], ['11111', '11111']);
    expect(c.boardSaved, {'mn-dongnai', 'mn-cantho'});
    expect(c.boardLocked('mn-dongnai'), isTrue);

    // Điểm ra only for the entries of the selected day: lô 10 x 3.5 = 35; đề 100.000 x 70 = 7.000.000
    expect(f.patches, {'e1': '35', 'e3': '7000000'});
    expect(f.patches.containsKey('e2'), isFalse);
    expect(c.syncMsg, contains('2'));

    // second sync with unchanged values writes nothing more
    f.patches.clear();
    f.entries = [
      {...f.entries[0], 'result': '35'},
      f.entries[1],
      {...f.entries[2], 'result': '7000000'},
    ];
    await c.syncScores();
    expect(f.patches, isEmpty);

    // unlock, then delete a saved column
    c.unlockColumn('mn-dongnai');
    expect(c.boardLocked('mn-dongnai'), isFalse);
    await c.deleteResult('mn-cantho');
    expect(f.deletes, ['$date|mn-cantho']);
    expect(c.boardSaved, {'mn-dongnai'});
    expect(filledCount(c.board['mn-cantho']!), 0);
  });

  test('automatic Điểm ra asks before overwriting a different value and can be undone', () async {
    final f = FakeServer();
    final c = ResultsController(client(f), testStations(), initialDate: date);
    await c.init();
    c.setRegion('mn');
    await Future<void>.delayed(Duration.zero);
    await c.loadDay();
    fillColumn(c, 'mn-dongnai', tam: '47');
    fillColumn(c, 'mn-cantho', db: '999956');
    // one entry already carries a different manual Điểm ra
    f.entries = [
      {...f.entries[0], 'result': '999'},
      f.entries[1],
      f.entries[2],
    ];
    var asked = 0;
    var answer = false;
    int? total, over;
    c.confirmOverwrite = (t, o) async {
      asked++;
      total = t;
      over = o;
      return answer;
    };
    await c.save();
    expect(asked, 1);
    expect([total, over], [2, 1]);
    expect(f.patches, isEmpty); // answered "no": nothing overwritten
    expect(c.syncMsg, contains('chưa cập nhật'));

    answer = true;
    await c.syncScores();
    expect(f.patches, {'e1': '35', 'e3': '7000000'});
    expect(c.undoItems, isNotNull);

    await c.undoScores();
    expect(f.patches['e1'], '999'); // the old value is back
    expect(f.patches['e3'], ''); // the empty one is cleared again
    expect(c.undoItems, isNull);
    expect(c.syncMsg, contains('hoàn tác'));
  });

  test('Miền Bắc form needs all 27 numbers and is read-only after saving', () async {
    final f = FakeServer();
    final c = ResultsController(client(f), testStations(), initialDate: date);
    await c.init();
    expect(c.totalBoxes, 27);
    await c.save();
    expect(c.error, 'Vui lòng nhập đủ 27 số trước khi lưu.');
    for (final p in c.structure) {
      for (var k = 0; k < p.count; k++) {
        c.setCell(null, p, k, '7' * p.digits);
      }
    }
    expect(c.mbLocked, isFalse);
    await c.save();
    expect(c.error, isNull);
    expect(f.posts.single['station'], 'mb');
    expect(f.posts.single['giaiBay'], ['77', '77', '77', '77']);
    expect(c.mbSaved && c.mbLocked, isTrue);
    c.unlockMb();
    expect(c.mbLocked, isFalse);
    c.clearForm();
    expect(filledCount(c.mbForm), 0);
  });

  test('saved results come back locked; day navigation reloads', () async {
    final f = FakeServer();
    f.saved['mn-dongnai'] = {'dacBiet': '123456', 'giaiNhat': '11111', 'giaiNhi': ['22222'], 'giaiBa': ['1', '2'].map((e) => '3333$e').toList(), 'giaiTu': List.filled(7, '44444'), 'giaiNam': ['5555'], 'giaiSau': List.filled(3, '6666'), 'giaiBay': ['777'], 'giaiTam': ['88']};
    final c = ResultsController(client(f), testStations(), initialDate: date);
    await c.init();
    await c.setRegion('mn');
    expect(c.boardSaved, {'mn-dongnai'});
    expect(c.boardLocked('mn-dongnai'), isTrue);
    expect(c.board['mn-dongnai']!['giaiTam'], ['88']);
    expect(c.boardLocked('mn-cantho'), isFalse);
    // the customer list shows only the chosen day and is calculated
    expect(c.dayEntries.map((e) => e.id), ['e1', 'e3']);
    expect(c.scoreOf(c.dayEntries.first), 0); // 47 is not among the prizes
    await c.shiftDay(-1);
    expect(c.date, '2026-10-06');
    expect(c.dayEntries.map((e) => e.id), ['e2']);
    expect(c.scoreOf(c.dayEntries.first), isNull);
  });

  test('ScoringController summarises one customer by day', () async {
    final f = FakeServer();
    f.saved['mn-dongnai'] = {'dacBiet': '123456', 'giaiNhat': '11111', 'giaiNhi': ['22222'], 'giaiBa': ['33331', '33332'], 'giaiTu': List.filled(7, '44444'), 'giaiNam': ['5555'], 'giaiSau': List.filled(3, '6666'), 'giaiBay': ['777'], 'giaiTam': ['47']};
    final c = ScoringController(client(f), testStations(), today: '2026-10-08');
    expect((c.preset, c.dateFrom, c.dateTo), ('today', '2026-10-08', '2026-10-08')); // opens on today
    await c.load();
    c.setPreset('all');
    c.selectCustomer('An');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    // 2026-10-07 has a result, 2026-10-06 does not
    expect(c.allDays.map((d) => d.date), ['2026-10-07', '2026-10-06']);
    expect(c.total.sentLots, 2);
    expect(c.total.wonMoney, 805000);
    expect(c.total.pendingLots, 1);
    expect(c.allDays.map((d) => d.lottery), ['yes', 'no']);
    c.setOnlyMissing(true);
    expect(c.days.map((d) => d.date), ['2026-10-06']);
    c.setOnlyMissing(false);
    c.setPreset('today');
    expect(c.dateFrom, '2026-10-08');
    expect(c.days, isEmpty);
    c.setPreset('7');
    expect(c.days.length, 2);
    c.setFrom('2026-10-07');
    expect(c.preset, 'custom');
    expect(c.days.length, 1);
    // the newest day is open and its entries were calculated + stored
    expect(c.isOpen('2026-10-07'), isTrue);
    expect(c.isOpen('2026-10-06'), isFalse);
    expect(f.patches['e1'], '35');
  });

  test('Tính điểm picks up a result saved AFTER it first looked (stale "no result" is forgotten when the tab is opened again)', () async {
    final f = FakeServer();
    final c = ScoringController(client(f), testStations(), today: '2026-10-08');
    await c.load();
    c.selectCustomer('An');
    c.setDay('2026-10-07');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    // nothing saved yet: the day shows "no result" and that is remembered in memory
    expect(c.allDays.single.lottery, 'no');
    // the result is saved in the Kết quả tab
    f.saved['mn-dongnai'] = {'dacBiet': '123456', 'giaiNhat': '11111', 'giaiNhi': ['22222'], 'giaiBa': ['33331', '33332'], 'giaiTu': List.filled(7, '44444'), 'giaiNam': ['5555'], 'giaiSau': List.filled(3, '6666'), 'giaiBay': ['777'], 'giaiTam': ['47']};
    // before the fix the cached "no result" stayed until nobody knows when
    await c.syncFrom(customer: 'An', date: '2026-10-07');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(c.allDays.single.lottery, 'yes');
    expect(c.total.wonMoney, greaterThan(0));
  });
}
