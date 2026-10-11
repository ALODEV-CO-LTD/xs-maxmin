import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/entries/entry_model.dart';
import 'package:mamba_app/features/entries/offline_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Fake {
  final List<http.Request> requests = [];
  bool offline = false;
  Map<String, http.Response Function(http.Request)> routes = {};

  http.Client client() => MockClient((req) async {
        requests.add(req);
        if (offline) throw http.ClientException('no network');
        final h = routes['${req.method} ${req.url.path}'];
        if (h == null) return http.Response('{"error":"missing route ${req.method} ${req.url.path}"}', 404);
        return h(req);
      });
}

http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> entryJson(String id, {String value = '12', String? score = '5', String updatedAt = 't1'}) =>
    {'id': id, 'customerName': 'An', 'entryDate': '2026-10-11', 'value': value, 'score': score, 'result': null, 'betType': 'de', 'station': 'mb', 'note': null, 'createdAt': 't0', 'updatedAt': updatedAt};

Future<(OfflineStore, Fake)> make({String user = 'u1', int idStart = 0}) async {
  SharedPreferences.setMockInitialValues({});
  return _build(user: user);
}

Future<(OfflineStore, Fake)> _build({String user = 'u1'}) async {
  final fake = Fake();
  var n = 0;
  final store = OfflineStore(
    api: ApiClient(AuthStore(), client: fake.client()),
    prefs: await SharedPreferences.getInstance(),
    userId: user,
    newId: () => 'id-${++n}-xxxxxxxx',
    now: () => DateTime.utc(2026, 10, 11, 8),
  );
  return (store, fake);
}

Map<String, dynamic> bodyOf(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;

void main() {
  final payload = {'customerName': 'An', 'value': '12', 'entryDate': '2026-10-11', 'score': '5', 'betType': 'de', 'station': 'mb'};

  test('userIdFromToken reads the JWT sub', () {
    String part(Map m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
    expect(userIdFromToken('${part({'alg': 'x'})}.${part({'sub': 'abc'})}.sig'), 'abc');
    expect(userIdFromToken('garbage'), isNull);
    expect(userIdFromToken(null), isNull);
  });

  test('online create sends a clientId and is not queued', () async {
    final (store, fake) = await make();
    fake.routes['POST /api/me/entries'] = (r) => json({...entryJson(bodyOf(r)['clientId'] as String)}, 201);
    final res = await store.createEntry(payload);
    expect(res.queued, isFalse);
    expect(bodyOf(fake.requests.single)['clientId'], 'id-1-xxxxxxxx');
    expect(res.entry.id, 'id-1-xxxxxxxx');
    expect(await store.pendingCount(), 0);
  });

  test('a server error is thrown (not queued)', () async {
    final (store, fake) = await make();
    fake.routes['POST /api/me/entries'] = (_) => json({'error': 'Đã dùng hết số liệu của gói hiện tại'}, 403);
    expect(store.createEntry(payload), throwsA(isA<ApiError>().having((e) => e.status, 'status', 403)));
    await Future<void>.delayed(Duration.zero);
    expect(await store.pendingCount(), 0);
  });

  test('offline create is queued, shown as pending, and replayed with the same id', () async {
    final (store, fake) = await make();
    fake.offline = true;
    final res = await store.createEntry(payload);
    expect(res.queued, isTrue);
    expect(res.entry.pending, isTrue);
    expect(await store.pendingCount(), 1);

    // the list (no cache yet) still shows the queued entry
    final loaded = await store.loadAllEntries();
    expect(loaded.fromCache, isTrue);
    expect(loaded.entries.single.pending, isTrue);
    expect(loaded.entries.single.value, '12');

    // still offline: flush stops and keeps the queue
    final r1 = await store.flush();
    expect(r1.offline, isTrue);
    expect(await store.pendingCount(), 1);

    // network back
    fake.offline = false;
    fake.requests.clear();
    fake.routes['POST /api/me/entries'] = (r) => json(entryJson(bodyOf(r)['clientId'] as String), 201);
    final r2 = await store.flush();
    expect(r2.changed, isTrue);
    expect(bodyOf(fake.requests.single)['clientId'], res.entry.id);
    expect(await store.pendingCount(), 0);
  });

  test('the queue survives a new store instance and stays per account', () async {
    final (store, fake) = await make();
    fake.offline = true;
    await store.createEntry(payload);
    final again = OfflineStore(api: store.api, prefs: store.prefs, userId: 'u1');
    expect(await again.pendingCount(), 1);
    final other = OfflineStore(api: store.api, prefs: store.prefs, userId: 'u2');
    expect(await other.pendingCount(), 0);
  });

  test('operations are replayed in order', () async {
    final (store, fake) = await make();
    fake.offline = true;
    await store.createEntry({...payload, 'value': '11'});
    await store.createEntry({...payload, 'value': '22'});
    await store.createEntry({...payload, 'value': '33'});
    fake.offline = false;
    fake.requests.clear();
    fake.routes['POST /api/me/entries'] = (r) => json(entryJson(bodyOf(r)['clientId'] as String), 201);
    await store.flush();
    expect(fake.requests.map((r) => bodyOf(r)['value']), ['11', '22', '33']);
  });

  test('a refused operation is dropped and reported; the rest continues', () async {
    final (store, fake) = await make();
    fake.offline = true;
    await store.createEntry({...payload, 'value': '11'});
    await store.createEntry({...payload, 'value': '22'});
    fake.offline = false;
    fake.routes['POST /api/me/entries'] = (r) => bodyOf(r)['value'] == '11' ? json({'error': 'Đã dùng hết số liệu của gói hiện tại'}, 403) : json(entryJson(bodyOf(r)['clientId'] as String, value: '22'), 201);
    final res = await store.flush();
    expect(res.failures, hasLength(1));
    expect(res.failures.single.message, contains('11'));
    expect(await store.pendingCount(), 0);
  });

  test('a 5xx or 401 keeps the queue for a retry', () async {
    final (store, fake) = await make();
    fake.offline = true;
    await store.createEntry(payload);
    fake.offline = false;
    fake.routes['POST /api/me/entries'] = (_) => json({'error': 'boom'}, 503);
    final res = await store.flush();
    expect(res.failures, isEmpty);
    expect(await store.pendingCount(), 1);
  });

  test('editing a still-queued create just changes the queued payload', () async {
    final (store, fake) = await make();
    fake.offline = true;
    final created = await store.createEntry(payload);
    final edited = await store.updateEntry(created.entry, {'value': '99', 'score': '7'});
    expect(edited.queued, isTrue);
    expect(edited.entry.value, '99');
    final ops = await store.ops();
    expect(ops, hasLength(1));
    expect(ops.single.payload['value'], '99');
    expect(ops.single.payload['score'], '7');
  });

  test('online edit sends baseUpdatedAt; offline edits are queued and merged', () async {
    final (store, fake) = await make();
    final e = Entry.fromJson(entryJson('e1'));
    fake.routes['PATCH /api/me/entries/e1'] = (r) => json(entryJson('e1', value: bodyOf(r)['value'] as String, updatedAt: 't2'));
    final ok = await store.updateEntry(e, {'value': '55'});
    expect(ok.queued, isFalse);
    expect(bodyOf(fake.requests.single)['baseUpdatedAt'], 't1');
    expect(ok.entry.updatedAt, 't2');

    fake.offline = true;
    final q1 = await store.updateEntry(e, {'value': '66'});
    expect(q1.queued, isTrue);
    expect(q1.entry.pending, isTrue);
    await store.updateEntry(e, {'score': '9'});
    final ops = await store.ops();
    expect(ops, hasLength(1));
    expect(ops.single.type, 'patch');
    expect(ops.single.baseUpdatedAt, 't1');
    expect(ops.single.payload, {'value': '66', 'score': '9'});

    // laid over the server list
    final overlaid = await store.overlayPending([e]);
    expect(overlaid.single.value, '66');
    expect(overlaid.single.score, '9');
    expect(overlaid.single.pending, isTrue);
  });

  test('a 409 conflict is parked, not retried or dropped, and can be resolved', () async {
    final (store, fake) = await make();
    fake.offline = true;
    final e = Entry.fromJson(entryJson('e1'));
    await store.updateEntry(e, {'value': '66'});
    fake.offline = false;
    fake.routes['PATCH /api/me/entries/e1'] = (r) => bodyOf(r)['force'] == true
        ? json(entryJson('e1', value: '66', updatedAt: 't9'))
        : json({'error': 'Số liệu đã được sửa ở nơi khác', 'conflict': true, 'server': entryJson('e1', value: '77', updatedAt: 't5')}, 409);
    final res = await store.flush();
    expect(res.conflicts, hasLength(1));
    expect(res.conflicts.single.server['value'], '77');
    expect((await store.ops()).single.conflict, isTrue);

    // flushing again does not resend the parked op
    fake.requests.clear();
    await store.flush();
    expect(fake.requests, isEmpty);

    await store.resolveConflict(res.conflicts.single, keepMine: true);
    expect(bodyOf(fake.requests.single)['force'], isTrue);
    expect(await store.pendingCount(), 0);
  });

  test('loadAllEntries follows every page and caches for offline', () async {
    final (store, fake) = await make();
    fake.routes['GET /api/me/entries'] = (r) {
      final offset = int.parse(r.url.queryParameters['offset']!);
      return offset == 0
          ? json({'entries': [entryJson('a'), entryJson('b')], 'total': 3, 'offset': 0, 'hasMore': true})
          : json({'entries': [entryJson('c')], 'total': 3, 'offset': 2, 'hasMore': false});
    };
    final res = await store.loadAllEntries();
    expect(res.entries.map((e) => e.id), ['a', 'b', 'c']);
    expect(res.fromCache, isFalse);
    expect(fake.requests.map((r) => r.url.queryParameters['offset']), ['0', '2']);

    fake.offline = true;
    final cached = await store.loadAllEntries();
    expect(cached.fromCache, isTrue);
    expect(cached.noCache, isFalse);
    expect(cached.entries.map((e) => e.id), ['a', 'b', 'c']);
  });

  test('cachedGet falls back to the last answer offline, but not on a server error', () async {
    final (store, fake) = await make();
    fake.routes['GET /api/me/customers'] = (_) => json({'customers': []});
    await store.cachedGet('/me/customers');
    fake.offline = true;
    expect(await store.cachedGet('/me/customers'), {'customers': []});
    expect(store.cachedGet('/me/other'), throwsA(isA<ApiError>()));
  });
}
