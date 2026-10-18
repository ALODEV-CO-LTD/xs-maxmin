// Runs on a phone / emulator against a REAL backend (the real HTTP contract and the real on-device storage); only the
// network loss is simulated, by a client wrapper that refuses to talk while "offline".
//
//   flutter test integration_test/offline_real_test.dart -d <device> --dart-define=API_BASE=http://localhost:8291
// (emulator: `adb reverse tcp:8291 tcp:8291` with a throw-away backend on that port)
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/core/config.dart';
import 'package:mamba_app/features/entries/offline_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Flaky extends http.BaseClient {
  _Flaky(this.inner);
  final http.Client inner;
  bool offline = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (offline) throw http.ClientException('no network');
    return inner.send(request);
  }
}

Future<Map<String, dynamic>> _post(String path, Map body, {String? token}) async {
  final r = await http.post(Uri.parse('${AppConfig.api}$path'), headers: {'content-type': 'application/json', if (token != null) 'authorization': 'Bearer $token'}, body: jsonEncode(body));
  return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real backend: customers and numbers added / deleted offline are sent when the network is back', (t) async {
    SharedPreferences.setMockInitialValues({}); // fresh storage for this account
    final user = 'off${DateTime.now().millisecondsSinceEpoch % 100000000}';
    final reg = await _post('/auth/register', {'name': 'Offline Test', 'username': user, 'password': 'Smoke#Test123', 'secondPassword': '2468'});
    final s2 = await _post('/auth/step2', {'pendingToken': reg['pendingToken'], 'password': '2468'});
    final token = s2['token'] as String;

    final net = _Flaky(http.Client());
    final auth = AuthStore()..token = token;
    final api = ApiClient(auth, client: net);
    final store = await OfflineStore.open(api, auth);
    const day = '2026-10-07';

    // online: one customer, two numbers, opened once so the phone has a copy
    await api.post('/me/customers', {'name': 'An', 'phone': ''});
    final e1 = (await store.createEntry({'customerName': 'An', 'entryDate': day, 'value': '47', 'score': '10', 'betType': 'lo', 'station': 'mb'})).entry;
    final e2 = (await store.createEntry({'customerName': 'An', 'entryDate': day, 'value': '56', 'score': '20', 'betType': 'de', 'station': 'mb'})).entry;
    await store.cachedGet('/me/customers');
    expect((await store.loadAllEntries()).entries.length, 2);

    // the network goes away
    net.offline = true;
    await expectLater(store.queueCustomerCreate(name: 'Sai', phone: '090'), throwsA(isA<ApiError>().having((e) => e.status, 'status', 400)));
    final made = await store.queueCustomerCreate(name: 'Bình', phone: '0901234567', defaultStation: 'mt');
    expect(made['pending'], isTrue);
    expect(await store.deleteEntry(e1.id), isTrue); // a number on the server
    final typed = await store.createEntry({'customerName': 'Bình', 'entryDate': day, 'value': '88', 'score': '5', 'betType': 'lo', 'station': 'mb'});
    expect(typed.queued, isTrue);
    final extra = await store.createEntry({'customerName': 'Bình', 'entryDate': day, 'value': '99', 'score': '5', 'betType': 'lo', 'station': 'mb'});
    expect(await store.deleteEntry(extra.entry.id), isTrue); // typed offline then deleted: never sent
    final shown = (await store.loadAllEntries()).entries.map((e) => e.value).toList()..sort();
    expect(shown, ['56', '88']);
    expect([for (final c in ((await store.cachedGet('/me/customers')) as Map)['customers'] as List) (c as Map)['name']], ['An', 'Bình']);

    // the network is back
    net.offline = false;
    final r = await store.flush();
    expect(r.failures, isEmpty, reason: r.failures.map((f) => f.message).join(' | '));
    expect(await store.pendingCount(), 0);

    // what the SERVER holds now
    final entries = (await api.get('/me/entries?limit=100') as Map)['entries'] as List;
    expect(entries.map((e) => (e as Map)['value']).toList()..sort(), ['56', '88']);
    final custs = (await api.get('/me/customers') as Map)['customers'] as List;
    final bin = custs.cast<Map>().firstWhere((c) => c['name'] == 'Bình');
    expect(bin['phone'], '0901234567');
    expect(bin['defaultStation'], 'mt');
    expect(e2.id, isNotEmpty);
  });
}
