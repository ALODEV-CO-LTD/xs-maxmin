import 'dart:async';
import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/apns.dart';
import 'package:server/src/call_signaling.dart';
import 'package:server/src/data_wipe.dart';
import 'package:server/src/friend_requests.dart';
import 'package:server/src/push_message.dart';
import 'package:server/src/push_notify.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../routes/api/me/friend-requests/[id]/accept.dart' as accept;
import '../routes/api/me/friend-requests/[id]/decline.dart' as decline;
import '../routes/api/me/friend-requests/[id]/index.dart' as cancel;
import '../routes/api/me/friend-requests/index.dart' as list;
import '../routes/api/me/friends/index.dart' as friends;
import '../routes/api/me/friends/search.dart' as search;
import '../routes/api/me/unread/index.dart' as unread;
import 'support.dart';

class _Sink implements WebSocketSink {
  final sent = <Map<String, dynamic>>[];
  @override
  void add(Object? data) => sent.add(jsonDecode(data as String) as Map<String, dynamic>);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Chan extends StreamChannelMixin<dynamic> implements WebSocketChannel {
  _Chan() : sink = _Sink();
  @override
  final _Sink sink;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Fake implements PushSender {
  final sent = <(String, PushMessage)>[];
  @override
  Future<void> send(String userId, PushMessage message) async => sent.add((userId, message));
}

late Database db;

Future<Response> add(String me, Map<String, Object?> body) => callRoute(friends.onRequest, db, userId: me, body: body);
Future<Response> getList(String me) => callRoute(list.onRequest, db, userId: me, method: HttpMethod.get);
Future<Response> act(Function h, String me, String id, {HttpMethod method = HttpMethod.post}) =>
    callRoute((c) => (h as dynamic)(c, id) as Response, db, userId: me, method: method);
Future<Response> doAccept(String me, String id) => act(accept.onRequest, me, id);
Future<Response> doDecline(String me, String id) => act(decline.onRequest, me, id);
Future<Response> doCancel(String me, String id) => act(cancel.onRequest, me, id, method: HttpMethod.delete);

int friendRows(String a, String b) =>
    db.select('SELECT 1 FROM friendships WHERE (user_id=? AND friend_id=?) OR (user_id=? AND friend_id=?)', [a, b, b, a]).length;
int reqRows() => db.select('SELECT 1 FROM friend_requests').length;
String status(String id) => db.select('SELECT status FROM friend_requests WHERE id=?', [id]).first['status'] as String;

void main() {
  late _Fake push;
  setUp(() {
    db = testDb();
    db.execute('ALTER TABLE users ADD COLUMN e2ee_public_key TEXT'); // added by a migration in prod
    db.execute(
      "INSERT INTO users (id, username, name, password_hash, role, data_used, created_at) VALUES ('u3','nameu3','U u3','x','user',0,'2026-01-01')",
    );
    push = _Fake();
    pushSender = push;
    pushThrottle = PushThrottle();
  });
  tearDown(() => pushSender = null);

  group('POST /me/friends', () {
    test('by userId creates a pending request, no friendship; 201 shape', () async {
      final r = await add('u1', {'userId': 'u2'});
      expect(r.statusCode, 201);
      final b = await jsonBody(r);
      expect(b['status'], 'pending');
      final req = b['request'] as Map<String, dynamic>;
      expect(req.keys.toSet(), {'id', 'toId', 'toName', 'toUsername', 'createdAt'});
      expect(req['toId'], 'u2');
      expect(req['toName'], 'U u2');
      expect(friendRows('u1', 'u2'), 0);
    });

    test('by code creates a request too', () async {
      db.execute("INSERT INTO customer_codes (id, user_id, code, created_at) VALUES ('c','u2','123456','2026-01-01')");
      final r = await add('u1', {'code': '123456'});
      expect(r.statusCode, 201);
      expect(friendRows('u1', 'u2'), 0);
      expect(reqRows(), 1);
    });

    test('idempotent: second call returns 200 pending with the same request', () async {
      final first = (await jsonBody(await add('u1', {'userId': 'u2'})))['request'] as Map;
      final r = await add('u1', {'userId': 'u2'});
      expect(r.statusCode, 200);
      final b = await jsonBody(r);
      expect(b['status'], 'pending');
      expect((b['request'] as Map)['id'], first['id']);
      expect(reqRows(), 1);
    });

    test('already friends -> 200 friends + list row', () async {
      db.execute("INSERT INTO friendships (id,user_id,friend_id,created_at) VALUES ('a','u1','u2','x'),('b','u2','u1','x')");
      final r = await add('u1', {'userId': 'u2'});
      expect(r.statusCode, 200);
      final b = await jsonBody(r);
      expect(b['status'], 'friends');
      expect((b['friend'] as Map).keys.toSet(), {'id', 'name', 'username', 'isAdmin', 'publicKey'});
      expect(reqRows(), 0);
    });

    test('they already asked me -> becomes friends, request accepted, requester notified', () async {
      final rid = ((await jsonBody(await add('u2', {'userId': 'u1'})))['request'] as Map)['id'] as String;
      final ch = _Chan();
      CallSignalingRegistry.instance.register('u2', ch);
      addTearDown(() => CallSignalingRegistry.instance.unregister('u2', ch));
      final r = await add('u1', {'userId': 'u2'});
      expect(r.statusCode, 200);
      final b = await jsonBody(r);
      expect(b['status'], 'friends');
      expect((b['friend'] as Map)['id'], 'u2');
      expect(friendRows('u1', 'u2'), 2);
      expect(status(rid), 'accepted');
      expect(ch.sink.sent.single, {'type': 'friend-accepted', 'friendId': 'u1', 'name': 'U u1'});
    });

    test('declined within 24h -> 200 pending without a row; after 24h a new request is created', () async {
      final rid = ((await jsonBody(await add('u1', {'userId': 'u2'})))['request'] as Map)['id'] as String;
      await doDecline('u2', rid);
      final r = await add('u1', {'userId': 'u2'});
      expect(r.statusCode, 200);
      final b = await jsonBody(r);
      expect(b['status'], 'pending');
      expect(b.containsKey('request'), false);
      expect(reqRows(), 1);
      final old = DateTime.now().toUtc().subtract(const Duration(hours: 25)).toIso8601String();
      db.execute('UPDATE friend_requests SET decided_at = ?', [old]);
      expect((await add('u1', {'userId': 'u2'})).statusCode, 201);
      expect(reqRows(), 2);
    });

    test('limit of 30 pending outgoing -> 429', () async {
      for (var i = 0; i < 30; i++) {
        db.execute("INSERT INTO users (id, username, name, password_hash, role, data_used, created_at) VALUES ('x$i','x$i','X','x','user',0,'2026-01-01')");
        expect((await add('u1', {'userId': 'x$i'})).statusCode, 201);
      }
      final r = await add('u1', {'userId': 'u2'});
      expect(r.statusCode, 429);
      expect((await jsonBody(r))['error'], isNotEmpty);
    });

    test('target with 200 pending incoming -> success pending, nothing created', () async {
      for (var i = 0; i < 200; i++) {
        db.execute("INSERT INTO users (id, username, name, password_hash, role, data_used, created_at) VALUES ('y$i','y$i','Y','x','user',0,'2026-01-01')");
        db.execute("INSERT INTO friend_requests (id, from_user_id, to_user_id, status, created_at) VALUES ('r$i','y$i','u2','pending','2026-01-01')");
      }
      final r = await add('u1', {'userId': 'u2'});
      expect(r.statusCode, 200);
      expect((await jsonBody(r))['status'], 'pending');
      expect(db.select("SELECT 1 FROM friend_requests WHERE from_user_id='u1'"), isEmpty);
    });

    test('validation: self, admin, unknown id/code, bad types, admin caller', () async {
      expect((await add('u1', {'userId': 'u1'})).statusCode, 400);
      expect((await add('u1', {'userId': 'adm'})).statusCode, 400);
      expect((await add('u1', {'userId': 'nope'})).statusCode, 404);
      expect((await add('u1', {'code': '000000'})).statusCode, 404);
      expect((await add('u1', {'userId': 5})).statusCode, 400);
      expect((await add('u1', {})).statusCode, 400);
      expect((await callRoute(friends.onRequest, db, userId: 'adm', role: 'admin', body: {'userId': 'u2'})).statusCode, 403);
      expect(reqRows(), 0);
    });

    test('oversized body rejected', () async {
      final r = await callRoute(friends.onRequest, db, body: {'userId': 'a' * 300000}, headers: {'content-length': '300030'});
      expect(r.statusCode, anyOf(400, 413));
    });
  });

  group('realtime and push', () {
    test('online recipient gets friend-request over the socket, no push', () async {
      final ch = _Chan();
      CallSignalingRegistry.instance.register('u2', ch);
      addTearDown(() => CallSignalingRegistry.instance.unregister('u2', ch));
      final rid = ((await jsonBody(await add('u1', {'userId': 'u2'})))['request'] as Map)['id'];
      expect(ch.sink.sent.single, {'type': 'friend-request', 'requestId': rid, 'fromId': 'u1', 'fromName': 'U u1'});
      await Future<void>.delayed(Duration.zero);
      expect(push.sent, isEmpty);
    });

    test('offline recipient gets one throttled push with only the name', () async {
      await add('u1', {'userId': 'u2'});
      await Future<void>.delayed(Duration.zero);
      expect(push.sent, hasLength(1));
      expect(push.sent.single.$1, 'u2');
      final m = push.sent.single.$2;
      expect(m.kind, PushKind.friendRequest);
      expect(m.title, 'Lời mời kết bạn');
      expect(m.body, 'U u1 muốn kết bạn với bạn');
      expect(m.toPayload()['kind'], 'friendRequest');
      expect(m.toPayload()['friendId'], 'u1');
      // cancel + re-request inside 60 s: no second push
      final rid = (await jsonBody(await getList('u1')))['outgoing'][0]['id'] as String;
      await doCancel('u1', rid);
      await add('u1', {'userId': 'u2'});
      await Future<void>.delayed(Duration.zero);
      expect(push.sent, hasLength(1));
    });

    test('accept notifies the requester with friend-accepted', () async {
      final rid = ((await jsonBody(await add('u1', {'userId': 'u2'})))['request'] as Map)['id'] as String;
      final ch = _Chan();
      CallSignalingRegistry.instance.register('u1', ch);
      addTearDown(() => CallSignalingRegistry.instance.unregister('u1', ch));
      await doAccept('u2', rid);
      expect(ch.sink.sent.single, {'type': 'friend-accepted', 'friendId': 'u2', 'name': 'U u2'});
    });

    test('APNs and FCM handle the new kind like a message (no crash, normal expiry)', () {
      const m = PushMessage(kind: PushKind.friendRequest, title: 'Lời mời kết bạn', body: 'An muốn kết bạn với bạn', friendId: 'f');
      expect((m.toPayload()['aps'] as Map)['alert'], {'title': 'Lời mời kết bạn', 'body': 'An muốn kết bạn với bạn'});
      expect(m.toPayload().keys.toSet(), {'aps', 'friendId', 'kind'});
    });
  });

  group('GET /me/friend-requests and decisions', () {
    test('lists pending only, newest first, per direction', () async {
      final a = ((await jsonBody(await add('u1', {'userId': 'u2'})))['request'] as Map)['id'] as String;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await add('u3', {'userId': 'u2'});
      await add('u2', {'userId': 'u3'}); // accepts u3's request instead of creating
      final inc = await jsonBody(await getList('u2'));
      expect((inc['incoming'] as List).map((e) => (e as Map)['fromId']), ['u1']);
      expect((inc['incoming'] as List).first.keys.toSet(), {'id', 'fromId', 'fromName', 'fromUsername', 'createdAt'});
      expect(inc['outgoing'], isEmpty);
      final out = await jsonBody(await getList('u1'));
      expect((out['outgoing'] as List).single['id'], a);
      expect((out['outgoing'] as List).single.keys.toSet(), {'id', 'toId', 'toName', 'toUsername', 'createdAt'});
      expect(out['incoming'], isEmpty);
    });

    test('newest first and max 100', () async {
      for (var i = 0; i < 105; i++) {
        db.execute("INSERT INTO users (id, username, name, password_hash, role, data_used, created_at) VALUES ('z$i','z$i','Z','x','user',0,'2026-01-01')");
        db.execute("INSERT INTO friend_requests (id, from_user_id, to_user_id, status, created_at) VALUES ('q$i','z$i','u1','pending','2026-01-01T00:00:${(i % 60).toString().padLeft(2, '0')}.${i.toString().padLeft(3, '0')}Z')");
      }
      final inc = (await jsonBody(await getList('u1')))['incoming'] as List;
      expect(inc, hasLength(100));
      final times = [for (final e in inc) (e as Map)['createdAt'] as String];
      expect(times, [...times]..sort((a, b) => b.compareTo(a)));
    });

    test('accept: recipient only, creates both rows, idempotent, then 200 again', () async {
      final rid = ((await jsonBody(await add('u1', {'userId': 'u2'})))['request'] as Map)['id'] as String;
      expect((await doAccept('u1', rid)).statusCode, 404); // sender
      expect((await doAccept('u3', rid)).statusCode, 404); // stranger
      expect((await doAccept('u2', 'nope')).statusCode, 404);
      expect(friendRows('u1', 'u2'), 0);
      final r = await doAccept('u2', rid);
      expect(r.statusCode, 200);
      final b = await jsonBody(r);
      expect(b.keys.toSet(), {'friend'});
      expect((b['friend'] as Map)['id'], 'u1');
      expect(friendRows('u1', 'u2'), 2);
      expect(status(rid), 'accepted');
      final again = await doAccept('u2', rid);
      expect(again.statusCode, 200);
      expect((await jsonBody(again))['friend']['id'], 'u1');
      expect(friendRows('u1', 'u2'), 2);
    });

    test('accept declined/cancelled -> 409', () async {
      final a = ((await jsonBody(await add('u1', {'userId': 'u2'})))['request'] as Map)['id'] as String;
      await doDecline('u2', a);
      final r = await doAccept('u2', a);
      expect(r.statusCode, 409);
      expect((await jsonBody(r))['error'], isNotEmpty);
      final c = ((await jsonBody(await add('u3', {'userId': 'u2'})))['request'] as Map)['id'] as String;
      await doCancel('u3', c);
      expect((await doAccept('u2', c)).statusCode, 409);
      expect(friendRows('u1', 'u2'), 0);
    });

    test('decline: recipient only', () async {
      final rid = ((await jsonBody(await add('u1', {'userId': 'u2'})))['request'] as Map)['id'] as String;
      expect((await doDecline('u1', rid)).statusCode, 404);
      expect((await doDecline('u3', rid)).statusCode, 404);
      final r = await doDecline('u2', rid);
      expect(r.statusCode, 200);
      expect(await jsonBody(r), {'ok': true});
      expect(status(rid), 'declined');
      expect(db.select('SELECT decided_at FROM friend_requests').first['decided_at'], isNotNull);
    });

    test('cancel: sender only, pending only', () async {
      final rid = ((await jsonBody(await add('u1', {'userId': 'u2'})))['request'] as Map)['id'] as String;
      expect((await doCancel('u2', rid)).statusCode, 404);
      expect((await doCancel('u3', rid)).statusCode, 404);
      final r = await doCancel('u1', rid);
      expect(r.statusCode, 200);
      expect(await jsonBody(r), {'ok': true});
      expect(status(rid), 'cancelled');
      // decided requests cannot be cancelled
      final r2 = ((await jsonBody(await add('u1', {'userId': 'u3'})))['request'] as Map)['id'] as String;
      await doAccept('u3', r2);
      expect((await doCancel('u1', r2)).statusCode, 409);
      expect(status(r2), 'accepted');
      // a cancelled request can be re-sent
      expect((await add('u1', {'userId': 'u2'})).statusCode, 201);
    });

    test('auth, method and admin guards', () async {
      final rid = ((await jsonBody(await add('u1', {'userId': 'u2'})))['request'] as Map)['id'] as String;
      expect((await callRoute(list.onRequest, db, method: HttpMethod.post)).statusCode, 405);
      expect((await callRoute(list.onRequest, db, userId: 'adm', role: 'admin', method: HttpMethod.get)).statusCode, 403);
      expect((await callRoute((c) => accept.onRequest(c, rid), db, userId: 'adm', role: 'admin')).statusCode, 403);
      expect((await callRoute((c) => accept.onRequest(c, rid), db, userId: 'u2', method: HttpMethod.get)).statusCode, 405);
    });
  });

  group('search, unread, wipe', () {
    test('search requestState none / outgoing / incoming', () async {
      await add('u1', {'userId': 'u2'});
      await add('u3', {'userId': 'u1'});
      final r = await callRoute(search.onRequest, db, method: HttpMethod.get, path: '/api/me/friends/search?q=name');
      final res = (await jsonBody(r))['results'] as List;
      String st(String id) => res.firstWhere((e) => (e as Map)['id'] == id)['requestState'] as String;
      expect(st('u2'), 'outgoing');
      expect(st('u3'), 'incoming');
      expect(res.every((e) => (e as Map).containsKey('isFriend')), isTrue);
      db.execute("INSERT INTO users (id, username, name, password_hash, role, data_used, created_at) VALUES ('u4','nameu4','U u4','x','user',0,'2026-01-01')");
      final r2 = await callRoute(search.onRequest, db, method: HttpMethod.get, path: '/api/me/friends/search?q=nameu4');
      expect((await jsonBody(r2))['results'][0]['requestState'], 'none');
    });

    test('unread has friendRequests = pending incoming, old keys stay', () async {
      await add('u1', {'userId': 'u2'});
      await add('u3', {'userId': 'u2'});
      final r = await callRoute(unread.onRequest, db, userId: 'u2', method: HttpMethod.get);
      final b = await jsonBody(r);
      expect(b['friendRequests'], 2);
      expect(b.keys.toSet(), containsAll({'friends', 'support', 'supportByUser', 'total', 'friendRequests'}));
      await doDecline('u2', (await jsonBody(await getList('u2')))['incoming'][0]['id'] as String);
      expect((await jsonBody(await callRoute(unread.onRequest, db, userId: 'u2', method: HttpMethod.get)))['friendRequests'], 1);
    });

    test('data wipe deletes requests in both directions, keeps friendships', () async {
      await add('u1', {'userId': 'u2'});
      await add('u3', {'userId': 'u1'});
      db.execute("INSERT INTO friendships (id,user_id,friend_id,created_at) VALUES ('a','u1','u2','x'),('b','u2','u1','x')");
      final counts = wipeUserData(db, 'u1');
      expect(counts['friend_requests'], 2);
      expect(reqRows(), 0);
      expect(friendRows('u1', 'u2'), 2);
    });
  });

  group('schema', () {
    test('pending pair is unique, status is checked', () {
      db.execute("INSERT INTO friend_requests (id, from_user_id, to_user_id, status, created_at) VALUES ('1','u1','u2','pending','x')");
      expect(
        () => db.execute("INSERT INTO friend_requests (id, from_user_id, to_user_id, status, created_at) VALUES ('2','u1','u2','pending','x')"),
        throwsA(isA<SqliteException>()),
      );
      db.execute("INSERT INTO friend_requests (id, from_user_id, to_user_id, status, created_at) VALUES ('3','u1','u2','declined','x')");
      expect(
        () => db.execute("INSERT INTO friend_requests (id, from_user_id, to_user_id, status, created_at) VALUES ('4','u1','u3','weird','x')"),
        throwsA(isA<SqliteException>()),
      );
    });

    test('migration is idempotent and works on an existing DB that has users/friendships but no table', () {
      final old = sqlite3.openInMemory();
      old.execute('PRAGMA foreign_keys = ON');
      old.execute('CREATE TABLE users (id TEXT PRIMARY KEY)');
      old.execute('CREATE TABLE friendships (id TEXT PRIMARY KEY, user_id TEXT, friend_id TEXT)');
      old.execute("INSERT INTO users (id) VALUES ('a'), ('b')");
      old.execute("INSERT INTO friendships VALUES ('f','a','b')");
      ensureFriendRequestsTable(old);
      ensureFriendRequestsTable(old);
      old.execute("INSERT INTO friend_requests (id, from_user_id, to_user_id, status, created_at) VALUES ('1','a','b','pending','x')");
      expect(old.select('SELECT * FROM friendships'), hasLength(1));
      expect(old.select("SELECT name FROM sqlite_master WHERE name LIKE 'idx_friend_requests%'"), hasLength(3));
      old.execute("DELETE FROM users WHERE id = 'a'");
      expect(old.select('SELECT * FROM friend_requests'), isEmpty); // ON DELETE CASCADE
    });
  });
}
