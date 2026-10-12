import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/core/scoring_config.dart';
import 'package:mamba_app/features/scoring/scoring_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _jwt(String sub) {
  String part(Map m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${part({'alg': 'x'})}.${part({'sub': sub})}.sig';
}

class _Net {
  bool offline = false;
  int calls = 0;
  final Map<String, Object> routes = {};
  ApiClient api(String sub) {
    final auth = AuthStore()..token = _jwt(sub);
    return ApiClient(
      auth,
      client: MockClient((req) async {
        calls++;
        if (offline) throw http.ClientException('no network');
        final body = routes[req.url.path + (req.url.hasQuery ? '?${req.url.query}' : '')] ?? routes[req.url.path];
        if (body == null) return http.Response('{"error":"missing"}', 404);
        return http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );
  }
}

Map<String, dynamic> _entry(String id) => {'id': id, 'customerName': 'An', 'entryDate': '2026-10-11', 'value': '12', 'score': '5', 'result': null, 'betType': 'de', 'station': 'mb', 'note': null, 'createdAt': 't0', 'updatedAt': 't1'};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('every figure the calculation needs is saved on the phone and read back offline', () async {
    final net = _Net()
      ..routes['/api/me/entries'] = {'entries': [_entry('e1'), _entry('e2')], 'hasMore': false}
      ..routes['/api/me/customers'] = {'customers': [{'id': 'c1', 'name': 'An', 'phone': '09', 'scoringRates': null, 'defaultStation': null}]}
      ..routes['/api/me/scoring-settings'] = {'rates': {'de': {'rate': 80, 'tiers': ['dacBiet'], 'digits': 2}}}
      ..routes['/api/lottery-results'] = {'result': {'drawDate': '2026-10-11', 'station': 'mb', 'dacBiet': '12345', 'giaiNhat': '11111', 'giaiNhi': ['22222', '33333'], 'giaiBa': ['1', '2', '3', '4', '5', '6'], 'giaiTu': ['1', '2', '3', '4'], 'giaiNam': ['1', '2', '3', '4', '5', '6'], 'giaiSau': ['1', '2', '3'], 'giaiBay': ['1', '2', '3', '4']}};
    final api = net.api('u1');

    // online: reads the server and saves
    expect((await fetchAllEntries(api)).length, 2);
    expect(DataSource.fromCache, isFalse);
    final custOnline = await fetchCustomers(api);
    final ratesOnline = await fetchAccountRates(api);
    final resOnline = await fetchLotteryResult(api, '2026-10-11', 'mb');
    expect(custOnline.single.name, 'An');
    expect(ratesOnline['de']['rate'], 80);
    expect(resOnline, isNotNull);

    // offline: the same answers come from the saved copy and the flag says so
    net.offline = true;
    expect((await fetchAllEntries(api)).length, 2);
    expect(DataSource.fromCache, isTrue);
    expect((await fetchCustomers(api)).single.name, 'An');
    expect((await fetchAccountRates(api))['de']['rate'], 80);
    expect(await fetchLotteryResult(api, '2026-10-11', 'mb'), isNotNull);

    // the offline copy is per account
    final other = net.api('u2');
    await expectLater(fetchAllEntries(other), throwsA(isA<ApiError>()));
  });

  test('offline with nothing saved: a clear error, not an empty list', () async {
    final net = _Net()..offline = true;
    await expectLater(fetchAllEntries(net.api('u1')), throwsA(isA<ApiError>().having((e) => e.status, 'status', 0)));
  });

  test('a day never opened online has no saved result offline (it is not mistaken for "no result")', () async {
    final net = _Net()..offline = true;
    await expectLater(fetchLotteryResult(net.api('u1'), '2026-10-05', 'mb'), throwsA(isA<ApiError>()));
  });

  test('the calculation itself is pure: same numbers with and without a network', () {
    // 10 điểm lô, ratio 3.5 hits -> 805.000đ at 23.000đ per điểm (hand-checked in scoring_logic_test)
    expect(toMoney('lo', {'unit': 'point', 'pointValue': 23000}, 35), 805000);
  });
}
