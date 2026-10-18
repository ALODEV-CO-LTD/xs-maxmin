import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/entries/entry_model.dart';
import 'package:mamba_app/features/entries/offline_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _jwt(String sub) {
  String part(Map m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${part({'alg': 'x'})}.${part({'sub': sub})}.sig';
}

http.Response _json(Object b, [int status = 200]) => http.Response.bytes(utf8.encode(jsonEncode(b)), status, headers: {'content-type': 'application/json; charset=utf-8'});

Future<OfflineStore> _store(Future<http.Response> Function(http.Request r) handler, {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final api = ApiClient(AuthStore()..token = _jwt('u1'), client: MockClient(handler));
  return OfflineStore(api: api, prefs: await SharedPreferences.getInstance(), userId: 'u1');
}

Map<String, dynamic> _payload(String score) => {'customerName': 'An', 'entryDate': '2026-10-07', 'value': '47', 'score': score, 'betType': 'lo', 'station': 'mb'};
Entry _entry(String id, [String score = '10']) => Entry.fromJson({..._payload(score), 'id': id, 'updatedAt': '2026-10-07T01:00:00Z'});

void main() {
  test('an edit made while the create is on the wire is not lost: it stays as a follow-up patch', () async {
    final gate = Completer<void>();
    final calls = <String>[];
    late OfflineStore s;
    s = await _store((r) async {
      calls.add('${r.method} ${r.url.path}');
      if (r.method == 'POST') {
        await gate.future;
        return _json({...(jsonDecode(r.body) as Map), 'id': 'e9', 'updatedAt': '2026-10-07T02:00:00Z'});
      }
      return _json({'id': 'e9', ..._payload('55'), 'updatedAt': '2026-10-07T03:00:00Z'});
    });
    await s.createEntryForTest('e9', _payload('10'));
    final flushing = s.flush();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await s.updateEntry(_entry('e9'), {'score': '55'}); // while POST is in flight
    gate.complete();
    final res = await flushing;
    expect(res.failures, isEmpty);
    expect(calls.where((c) => c.startsWith('PATCH')).length, 1, reason: 'the follow-up edit was sent in a later pass');
    expect(await s.ops(), isEmpty);
  });

  test('deleting an entry whose create is on the wire still deletes it on the server', () async {
    final gate = Completer<void>();
    final calls = <String>[];
    final s = await _store((r) async {
      calls.add('${r.method} ${r.url.path}');
      if (r.method == 'POST') {
        await gate.future;
        return _json({...(jsonDecode(r.body) as Map), 'id': 'e9', 'updatedAt': 'u'});
      }
      return _json({'ok': true});
    });
    await s.createEntryForTest('e9', _payload('10'));
    final flushing = s.flush();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(await s.deleteEntry('e9'), isTrue);
    gate.complete();
    await flushing;
    expect(calls.last, 'DELETE /api/me/entries/e9');
    expect(await s.ops(), isEmpty);
  });

  test('429 / 408 / 425 keep the op for a retry; a 400 is dropped for good', () async {
    for (final code in [408, 425, 429]) {
      final s = await _store((r) async => _json({'error': 'later'}, code));
      await s.createEntryForTest('e1', _payload('10'));
      final res = await s.flush();
      expect(res.failures, isEmpty, reason: '$code');
      expect((await s.ops()).length, 1, reason: '$code');
    }
    final s = await _store((r) async => _json({'error': 'bad'}, 400));
    await s.createEntryForTest('e1', _payload('10'));
    final res = await s.flush();
    expect(res.failures.length, 1);
    expect(await s.ops(), isEmpty);
  });

  test('cust-create: after a 409 on retry the station is still set', () async {
    final calls = <String>[];
    final s = await _store((r) async {
      calls.add('${r.method} ${r.url.path}');
      if (r.method == 'POST') return _json({'error': 'exists'}, 409);
      if (r.method == 'GET') {
        return _json({
          'customers': [
            {'id': 'srv7', 'name': 'Bình'}
          ]
        });
      }
      return _json({'id': 'srv7'});
    });
    await s.queueCustomerCreateForTest('Bình', 'mn');
    final res = await s.flush();
    expect(res.failures, isEmpty);
    expect(calls, contains('PATCH /api/me/customers/srv7'));
    expect(await s.ops(), isEmpty);
  });

  test('an entry whose edit is parked as a conflict cannot be edited further', () async {
    final s = await _store((r) async => _json({}));
    await s.createEntryForTest('e1', _payload('10'), type: 'patch', conflict: true);
    expect(() => s.updateEntry(_entry('e1'), {'score': '1'}), throwsA(isA<ApiError>()));
  });

  test('a corrupt queue is kept under .corrupt instead of being overwritten', () async {
    final s = await _store((r) async => _json({}), prefs: {'xoso_offline_queue': '{not json'});
    expect(await s.ops(), isEmpty);
    await s.queueCustomerDelete('x'); // a write after the failed read
    final p = await SharedPreferences.getInstance();
    expect(p.getString('xoso_offline_queue.corrupt'), '{not json');
  });

  test('a result saved again while its first send is in flight stays pending', () async {
    final gate = Completer<void>();
    final s = await _store((r) async {
      final body = jsonDecode(r.body) as Map;
      if (body['dacBiet'] == '1') await gate.future; // only the first send is slow
      return _json({'result': body});
    });
    final first = s.saveResult({'drawDate': '2026-10-07', 'station': 'mb', 'dacBiet': '1'});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await s.saveResult({'drawDate': '2026-10-07', 'station': 'mb', 'dacBiet': '2'});
    gate.complete();
    await first;
    // the late answer of the OLD content must not overwrite the newer save
    final stored = (await SharedPreferences.getInstance()).getString('xoso_results:u1')!;
    expect(stored, contains('"dacBiet":"2"'));
    expect(stored, isNot(contains('"dacBiet":"1"')));
  });
}

extension on OfflineStore {
  /// Puts an op straight into the queue (as if made offline).
  Future<void> createEntryForTest(String id, Map<String, dynamic> payload, {String type = 'create', bool conflict = false}) async {
    final p = prefs;
    final raw = p.getString('xoso_offline_queue');
    final list = raw == null ? <dynamic>[] : (jsonDecode(raw) as List? ?? <dynamic>[]);
    list.add(QueuedOp(opId: 'op-$id-${list.length}', seq: list.length + 1, userId: 'u1', type: type, entryId: id, payload: payload, createdAt: '2026-10-07T00:00:00Z', conflict: conflict).toJson());
    await p.setString('xoso_offline_queue', jsonEncode(list));
  }

  Future<void> queueCustomerCreateForTest(String name, String station) async {
    final p = prefs;
    await p.setString(
        'xoso_offline_queue',
        jsonEncode([
          QueuedOp(opId: 'c1', seq: 1, userId: 'u1', type: 'cust-create', entryId: 'loc1', payload: {'name': name, 'phone': '', 'defaultStation': station}, createdAt: '2026-10-07T00:00:00Z').toJson()
        ]));
  }
}
