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
          if (path == '/me/customers') return ok({'customers': [{'id': 'c1', 'name': 'An', 'phone': '', 'scoringRates': null}]});
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
}
