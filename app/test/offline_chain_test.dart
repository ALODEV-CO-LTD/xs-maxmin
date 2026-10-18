import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/entries/offline_store.dart';
import 'package:mamba_app/features/results/results_controller.dart';
import 'package:mamba_app/features/scoring/scoring_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'scoring_fixtures.dart';

// End to end "calculate without a network": the day is opened online once, then the network goes away and the person keeps
// typing numbers, saving the lottery result and reading the points; when the network is back everything reaches the server.
const day = '2026-10-07';

String _jwt(String sub) {
  String part(Map m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${part({'alg': 'x'})}.${part({'sub': sub})}.sig';
}

class _Server {
  bool offline = false;
  final entries = <Map<String, dynamic>>[
    {'id': 'e1', 'customerName': 'An', 'entryDate': day, 'value': '47', 'score': '10', 'betType': 'lo', 'station': 'mb', 'result': null},
    {'id': 'e2', 'customerName': 'An', 'entryDate': day, 'value': '56', 'score': '100000', 'betType': 'de', 'station': 'mb', 'result': null},
  ];
  final posted = <Map<String, dynamic>>[];
  final deletedEntries = <String>[];
  final customers = <Map<String, dynamic>>[{'id': 'c1', 'name': 'An', 'phone': '', 'scoringRates': null}];
  final deletedCustomers = <String>[];
  final patched = <String, String>{};
  Map<String, dynamic>? result; // saved MB result of `day`

  ApiClient api() => ApiClient(
        AuthStore()..token = _jwt('u1'),
        client: MockClient((r) async {
          if (offline) throw http.ClientException('no network');
          final path = r.url.path.replaceFirst('/api', '');
          http.Response ok(Object b) => http.Response(jsonEncode(b), 200, headers: {'content-type': 'application/json; charset=utf-8'});
          if (path == '/me/entries' && r.method == 'GET') return ok({'entries': entries, 'total': entries.length, 'hasMore': false});
          if (path == '/me/entries' && r.method == 'POST') {
            final b = jsonDecode(r.body) as Map<String, dynamic>;
            posted.add(b);
            entries.add({...b, 'id': b['clientId'] ?? 'new${posted.length}'});
            return ok(entries.last);
          }
          if (path.startsWith('/me/entries/') && r.method == 'PATCH') {
            final id = path.split('/').last;
            patched[id] = (jsonDecode(r.body) as Map)['result'] as String;
            return ok({'id': id});
          }
          if (path == '/me/customers' && r.method == 'GET') return ok({'customers': customers});
          if (path == '/me/customers' && r.method == 'POST') {
            final b = jsonDecode(r.body) as Map<String, dynamic>;
            if (customers.any((c) => c['name'] == b['name'])) return http.Response.bytes(utf8.encode('{"error":"Tên khách hàng đã tồn tại"}'), 409, headers: {'content-type': 'application/json; charset=utf-8'});
            customers.add({'id': 'srv${customers.length + 1}', 'name': b['name'], 'phone': b['phone'] ?? '', 'scoringRates': null});
            return ok(customers.last);
          }
          if (path.startsWith('/me/customers/') && r.method == 'PATCH') return ok({'id': path.split('/').last});
          if (path.startsWith('/me/customers/') && r.method == 'DELETE') {
            final id = path.split('/').last;
            deletedCustomers.add(id);
            customers.removeWhere((c) => c['id'] == id);
            return ok({'ok': true});
          }
          if (path.startsWith('/me/entries/') && r.method == 'DELETE') {
            final id = path.split('/').last;
            deletedEntries.add(id);
            entries.removeWhere((e) => e['id'] == id);
            return ok({'ok': true});
          }
          if (path == '/me/scoring-settings') {
            return ok({'rates': {'lo': {'rate': 3.5, 'tiers': allBaseTiers, 'digits': 2}, 'de': {'rate': 70, 'tiers': ['dacBiet'], 'digits': 2}}});
          }
          if (path == '/lottery-results' && r.method == 'GET') {
            final all = r.url.queryParameters['all'] == '1';
            if (all) return ok({'results': [if (result != null) {'drawDate': day, 'station': 'mb', ...result!}]});
            return ok({'result': result});
          }
          if (path == '/lottery-results' && r.method == 'POST') {
            final b = jsonDecode(r.body) as Map<String, dynamic>;
            result = {...b}..remove('drawDate')..remove('station');
            return ok({'result': b});
          }
          return http.Response('{"error":"?"}', 404);
        }),
      );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('open the day online, go offline: type, save the result, read the points; back online everything is sent', () async {
    final s = _Server();
    final api = s.api();

    // 1) online: both screens open the day once (this fills the copy kept on the phone)
    final online = ResultsController(api, testStations(), initialDate: day);
    await online.init();
    expect(online.entries.length, 2);
    await ScoringController(api, testStations(), today: day).load();

    // 2) the network goes away
    s.offline = true;

    // 3) a number typed offline is kept on the phone (queued)
    final store = await OfflineStore.open(api, api.auth);
    final saved = await store.createEntry({'customerName': 'An', 'entryDate': day, 'value': '88', 'score': '20', 'betType': 'lo', 'station': 'mb'});
    expect(saved.queued, isTrue);

    // 4) the points screen sees it at once (and says it is offline)
    final scoring = ScoringController(api, testStations(), today: day);
    await scoring.load();
    expect(scoring.loadError, isNull);
    expect(scoring.entries.length, 3);

    // 5) the results screen also sees the number typed offline, so its Điểm ra can be worked out
    final results = ResultsController(api, testStations(), initialDate: day);
    await results.init();
    expect(results.entries.length, 3, reason: 'a number typed offline must be in the results screen too');

    // 6) the result is typed and saved offline: kept on the phone, Điểm ra worked out for ALL numbers of the day
    for (final p in results.structure) {
      for (var k = 0; k < p.count; k++) {
        results.setCell(null, p, k, p.tier == 'dacBiet' ? '12356' : '1' * p.digits);
      }
    }
    await results.save();
    expect(results.error, isNull);
    expect(s.result, isNull, reason: 'nothing can reach the server while offline');
    expect(results.syncMsg, isNotNull);
    expect(results.entries.where((e) => e.entryDate == day).every((e) => (e.result ?? '').isNotEmpty), isTrue, reason: 'every number of the day has its Điểm ra');

    // 7) back online: the queued number, the result and the Điểm ra reach the server
    s.offline = false;
    final flush = await store.flush();
    expect(flush.changed, isTrue);
    expect(flush.failures, isEmpty);
    expect(s.posted.map((b) => b['value']), contains('88'));
    // the server now has all three numbers, each with its Điểm ra (sent with the number, or as a later edit)
    expect(s.entries.length, 3);
    final res = {for (final e in s.entries) e['id'] as String: (s.patched[e['id']] ?? e['result'] ?? '').toString()};
    expect(res.values.every((v) => v.isNotEmpty), isTrue, reason: res.toString());
    final result = s.result;
    expect(result, isNotNull, reason: 'the result saved offline reached the server');
    expect(result!['dacBiet'], '12356');
  });

  test('customers added and numbers deleted offline disappear / appear at once and reach the server later', () async {
    final s = _Server();
    final api = s.api();
    final store = await OfflineStore.open(api, api.auth);
    await store.cachedGet('/me/customers'); // opened once online
    await store.loadAllEntries();
    s.offline = true;

    // add a customer offline: shown at once (flagged), a duplicate name is refused
    final made = await store.queueCustomerCreate(name: 'Bình', phone: '0901234567');
    expect(made['pending'], isTrue);
    final shown = await store.cachedGet('/me/customers') as Map;
    expect([for (final c in shown['customers'] as List) (c as Map)['name']], ['An', 'Bình']);
    await expectLater(store.queueCustomerCreate(name: 'Sai', phone: '090'), throwsA(isA<ApiError>().having((e) => e.status, 'status', 400))); // a phone the server would refuse is not queued
    await expectLater(store.queueCustomerCreate(name: ' bình '), throwsA(isA<ApiError>().having((e) => e.status, 'status', 409)));

    // delete a number that is on the server: hidden at once, queued
    expect(await store.deleteEntry('e1'), isTrue);
    expect((await store.loadAllEntries()).entries.map((e) => e.id), ['e2']);
    // delete a number that never reached the server: simply forgotten
    final typed = await store.createEntry({'customerName': 'An', 'entryDate': day, 'value': '99', 'score': '5', 'betType': 'lo', 'station': 'mb'});
    expect(await store.deleteEntry(typed.entry.id), isTrue);
    expect((await store.loadAllEntries()).entries.map((e) => e.id), ['e2']);
    // remove a customer: the one added offline is forgotten, the server one is queued
    await store.queueCustomerDelete(made['id'] as String);
    await store.queueCustomerDelete('c1');
    expect(((await store.cachedGet('/me/customers')) as Map)['customers'], isEmpty);
    expect(await store.pendingCount(), 2); // delete e1 + delete customer c1

    // back online: the queue is sent, the server ends with exactly what the person sees
    s.offline = false;
    final r = await store.flush();
    expect(r.failures, isEmpty);
    expect(s.deletedEntries, ['e1']);
    expect(s.deletedCustomers, ['c1']);
    expect(s.posted, isEmpty);
    expect(await store.pendingCount(), 0);
    expect(s.customers, isEmpty);
    expect(s.entries.map((e) => e['id']), ['e2']);
  });

  test('a customer added offline is created on the server when the network is back (a name that already exists is not an error)', () async {
    final s = _Server();
    final api = s.api();
    final store = await OfflineStore.open(api, api.auth);
    await store.cachedGet('/me/customers');
    s.offline = true;
    await store.queueCustomerCreate(name: 'Cường', phone: '0911234567', defaultStation: 'mn');
    await store.queueCustomerCreate(name: 'Dũng');
    s.customers.add({'id': 'srvD', 'name': 'Dũng', 'phone': '', 'scoringRates': null}); // meanwhile created on another device
    s.offline = false;
    final r = await store.flush();
    expect(r.failures, isEmpty);
    expect(s.customers.map((c) => c['name']), ['An', 'Dũng', 'Cường']);
    expect(await store.pendingCount(), 0);
  });
}
