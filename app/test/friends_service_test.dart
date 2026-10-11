import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/friends/chat_models.dart';
import 'package:mamba_app/features/friends/chat_service.dart';
import 'package:mamba_app/features/friends/chat_store.dart';
import 'package:mamba_app/features/friends/realtime_socket.dart';

/// Fake server: stores public keys and relays e2ee frames exactly like backend/routes/api/ws/calls.dart
/// (never stores anything, tells the sender when the receiver is offline).
class FakeServer {
  final Map<String, Map<String, dynamic>> keys = {};
  final Map<String, ChatService> online = {};
  final List<Map<String, dynamic>> relayed = [];

  http.Client clientFor(String me, String friend) => MockClient((req) async {
        final path = req.url.path;
        if (path.endsWith('/me/e2ee-key')) {
          if (req.method == 'PUT') keys[me] = (jsonDecode(req.body) as Map)['publicKey'] as Map<String, dynamic>;
          return _json({'publicKey': keys[me]});
        }
        if (path.endsWith('/me/friends')) {
          return _json({'friends': [{'id': friend, 'name': 'Bạn', 'username': 'ban', 'isAdmin': false, 'publicKey': keys[friend]}]});
        }
        return http.Response('{}', 404);
      });
}

http.Response _json(Object body) => http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json; charset=utf-8'});

class LoopSocket implements FrameSink {
  LoopSocket(this.server, this.me);
  final FakeServer server;
  final String me;
  @override
  bool ready = true;
  @override
  void send(Map<String, dynamic> f) {
    final to = f['to'] as String;
    final target = server.online[to];
    if (f['type'] == 'e2ee-ack') {
      target?.onFrame({'type': 'e2ee-ack', 'id': f['id'], 'from': me});
      return;
    }
    server.relayed.add(f);
    if (target == null) {
      server.online[me]?.onFrame({'type': 'e2ee-undelivered', 'id': f['id'], 'to': to, 'reason': 'offline'});
      return;
    }
    target.onFrame({'type': 'e2ee-msg', 'id': f['id'], 'from': me, 'fromName': 'Người $me', 'iv': f['iv'], 'ct': f['ct'], 'part': f['part'], 'parts': f['parts'], 'ts': f['ts']});
  }
}

Future<ChatService> make(FakeServer s, String me, String friend, {MemoryChatStore? store, MemoryKeyVault? vault, Duration ackWait = const Duration(seconds: 15), bool online = true}) async {
  final svc = ChatService(
    api: ApiClient(AuthStore(), client: s.clientFor(me, friend)),
    userId: me,
    store: store ?? MemoryChatStore(),
    vault: vault ?? MemoryKeyVault(),
    socket: LoopSocket(s, me),
    ackWait: ackWait,
  );
  await svc.init();
  if (online) s.online[me] = svc;
  return svc;
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  late FakeServer server;
  setUp(() => server = FakeServer());

  test('init publishes the public key once and exposes a fingerprint', () async {
    final a = await make(server, 'user-aaaa-1111', 'user-bbbb-2222');
    expect(a.ready, isTrue);
    expect(server.keys['user-aaaa-1111'], isNotNull);
    expect(a.myFingerprint, matches(RegExp(r'^[0-9A-F]{5}(-[0-9A-F]{5}){3}$')));
  });

  test('both online: text is encrypted, delivered, acked and stored on both sides', () async {
    final a = await make(server, 'user-aaaa-1111', 'user-bbbb-2222');
    final b = await make(server, 'user-bbbb-2222', 'user-aaaa-1111');
    await a.loadFriendKeys();
    await a.send('user-bbbb-2222', 'Xin chào Bình');
    await settle();
    // the server only ever saw ciphertext
    expect(jsonEncode(server.relayed), isNot(contains('Xin chào')));
    final sent = (await a.messages('user-bbbb-2222')).single;
    expect(sent.status, MsgStatus.delivered);
    final got = (await b.messages('user-aaaa-1111')).single;
    expect(got.text, 'Xin chào Bình');
    expect(got.mine, isFalse);
    expect(b.unread['user-aaaa-1111'], 1);
    // both sides show the same security codes
    expect(a.peerInfo['user-bbbb-2222']!.fingerprint, b.myFingerprint);
  });

  test('offline friend: message fails with the offline reason and can be retried', () async {
    final a = await make(server, 'user-aaaa-1111', 'user-bbbb-2222');
    final b = await make(server, 'user-bbbb-2222', 'user-aaaa-1111', online: false);
    await a.loadFriendKeys();
    final m = await a.send('user-bbbb-2222', 'ai đó ở đó không?');
    await settle();
    final failed = (await a.messages('user-bbbb-2222')).single;
    expect(failed.status, MsgStatus.failed);
    expect(failed.reason, 'offline');
    server.online['user-bbbb-2222'] = b;
    await a.retry(m.id);
    await settle();
    expect((await a.messages('user-bbbb-2222')).single.status, MsgStatus.delivered);
    expect((await b.messages('user-aaaa-1111')).single.text, 'ai đó ở đó không?');
  });

  test('friend without a published key: fails with no-key', () async {
    final a = await make(server, 'user-aaaa-1111', 'user-bbbb-2222');
    await a.loadFriendKeys();
    await a.send('user-bbbb-2222', 'hi');
    expect((await a.messages('user-bbbb-2222')).single.reason, 'no-key');
  });

  test('missing ack turns into a timeout failure', () async {
    final svc = ChatService(
      api: ApiClient(AuthStore(), client: server.clientFor('user-aaaa-1111', 'user-bbbb-2222')),
      userId: 'user-aaaa-1111',
      store: MemoryChatStore(),
      vault: MemoryKeyVault(),
      socket: _Swallow(),
      ackWait: const Duration(milliseconds: 30),
    );
    await svc.init();
    await make(server, 'user-bbbb-2222', 'user-aaaa-1111'); // publishes B's key
    await svc.loadFriendKeys();
    await svc.send('user-bbbb-2222', 'hello');
    expect((await svc.messages('user-bbbb-2222')).single.status, MsgStatus.sent);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect((await svc.messages('user-bbbb-2222')).single.reason, 'timeout');
  });

  test('a large image is split into several relay parts and arrives intact', () async {
    final a = await make(server, 'user-aaaa-1111', 'user-bbbb-2222');
    final b = await make(server, 'user-bbbb-2222', 'user-aaaa-1111');
    await a.loadFriendKeys();
    final bytes = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, ...List<int>.generate(900000, (i) => i % 256)]);
    await a.send('user-bbbb-2222', 'ảnh', image: OutgoingImage(bytes, 'image/png'));
    for (var i = 0; i < 200 && (await b.messages('user-aaaa-1111')).isEmpty; i++) {
      await settle();
    }
    await settle();
    expect(server.relayed.length, 2);
    expect(server.relayed.every((f) => f['parts'] == 2), isTrue);
    final got = (await b.messages('user-aaaa-1111')).single;
    expect(got.att!.type, 'image/png');
    expect(got.att!.name, matches(RegExp(r'^anh-[0-9a-f]{10}\.png$')));
    expect(await b.store.readFile(got.att!.path!), bytes);
    expect((await a.messages('user-bbbb-2222')).single.status, MsgStatus.delivered);
  });

  test('non-image attachments are refused when sending', () async {
    final a = await make(server, 'user-aaaa-1111', 'user-bbbb-2222');
    expect(a.send('user-bbbb-2222', '', image: OutgoingImage(Uint8List(10), 'application/pdf')), throwsException);
  });

  test('screenshot notice is relayed encrypted and shown as a system line on both sides', () async {
    final a = await make(server, 'user-aaaa-1111', 'user-bbbb-2222');
    final b = await make(server, 'user-bbbb-2222', 'user-aaaa-1111');
    await a.loadFriendKeys();
    await a.notifyScreenshot('user-bbbb-2222');
    await a.notifyScreenshot('user-bbbb-2222'); // throttled: only one in 20 s
    await settle();
    final mine = await a.messages('user-bbbb-2222');
    expect(mine.length, 1);
    expect(mine.single.sys, SysKind.screenshotSent);
    expect(mine.single.status, MsgStatus.delivered);
    expect((await b.messages('user-aaaa-1111')).single.sys, SysKind.screenshot);
  });

  test('unread counters persist and are not bumped while the conversation is open', () async {
    final a = await make(server, 'user-aaaa-1111', 'user-bbbb-2222');
    final store = MemoryChatStore();
    final b = await make(server, 'user-bbbb-2222', 'user-aaaa-1111', store: store);
    await a.loadFriendKeys();
    await a.send('user-bbbb-2222', 'một');
    await settle();
    expect(b.unread['user-aaaa-1111'], 1);
    b.openPeer = 'user-aaaa-1111';
    await a.send('user-bbbb-2222', 'hai');
    await settle();
    expect(b.unread['user-aaaa-1111'], 1);
    final b2 = await make(server, 'user-bbbb-2222', 'user-aaaa-1111', store: store, vault: MemoryKeyVault()..data.addAll((b.vault as MemoryKeyVault).data));
    expect(b2.unread['user-aaaa-1111'], 1); // restored from the store
    await b2.markRead('user-aaaa-1111');
    expect(b2.unread, isEmpty);
  });

  test('the same device key is reused across restarts; a new device key is flagged to the friend', () async {
    final vault = MemoryKeyVault();
    final a1 = await make(server, 'user-aaaa-1111', 'user-bbbb-2222', vault: vault);
    final a2 = await make(server, 'user-aaaa-1111', 'user-bbbb-2222', vault: vault);
    expect(a2.myFingerprint, a1.myFingerprint);

    final bStore = MemoryChatStore();
    final b = await make(server, 'user-bbbb-2222', 'user-aaaa-1111', store: bStore);
    expect(b.peerInfo['user-aaaa-1111']!.changed, isFalse);
    // A reinstalls (empty vault): new key published, B notices on the next friend refresh
    final fresh = await make(server, 'user-aaaa-1111', 'user-bbbb-2222', vault: MemoryKeyVault());
    expect(fresh.myFingerprint, isNot(a1.myFingerprint));
    await b.loadFriendKeys();
    expect(b.peerInfo['user-aaaa-1111']!.changed, isTrue);
    await b.acceptKeyChange('user-aaaa-1111');
    expect(b.peerInfo['user-aaaa-1111']!.changed, isFalse);
  });

  test('a frame encrypted for someone else or tampered with is dropped silently', () async {
    final a = await make(server, 'user-aaaa-1111', 'user-bbbb-2222');
    final b = await make(server, 'user-bbbb-2222', 'user-aaaa-1111');
    await a.loadFriendKeys();
    await a.send('user-bbbb-2222', 'thật');
    await settle();
    final real = server.relayed.single;
    // replay under another message id: AAD mismatch
    await b.onFrame({'type': 'e2ee-msg', 'id': 'forged-id-123456', 'from': 'user-aaaa-1111', 'iv': real['iv'], 'ct': real['ct'], 'part': 0, 'parts': 1});
    // replay of the real id is a duplicate
    await b.onFrame({'type': 'e2ee-msg', 'id': real['id'], 'from': 'user-aaaa-1111', 'iv': real['iv'], 'ct': real['ct'], 'part': 0, 'parts': 1});
    expect((await b.messages('user-aaaa-1111')).length, 1);
  });

  test('retention rule deletes old messages (and their files) on this device', () async {
    final store = MemoryChatStore();
    final a = await make(server, 'user-aaaa-1111', 'user-bbbb-2222', store: store);
    final now = DateTime.now().millisecondsSinceEpoch;
    final path = await store.writeFile('old1', Uint8List(3), 'png');
    await store.putMessage(ChatMessage(id: 'old1', peerId: 'user-bbbb-2222', mine: false, text: '', createdAt: now - 2 * 86400000, status: MsgStatus.delivered, att: ChatAttachment(name: 'a.png', type: 'image/png', size: 3, path: path)));
    await store.putMessage(ChatMessage(id: 'old2', peerId: 'user-bbbb-2222', mine: false, text: 'cũ', createdAt: now - 2 * 86400000, status: MsgStatus.delivered));
    await store.putMessage(ChatMessage(id: 'new1', peerId: 'user-bbbb-2222', mine: false, text: 'mới', createdAt: now, status: MsgStatus.delivered));
    await a.setRetention('user-bbbb-2222', const RetentionRule(86400, 'images'));
    expect((await store.messagesOf('user-bbbb-2222')).map((m) => m.id), ['old2', 'new1']);
    expect(store.files, isEmpty);
    await a.setRetention('user-bbbb-2222', const RetentionRule(86400, 'all'));
    expect((await store.messagesOf('user-bbbb-2222')).map((m) => m.id), ['new1']);
    await a.setRetention('user-bbbb-2222', null);
    expect(await a.retentionOf('user-bbbb-2222'), isNull);
  });
}

class _Swallow implements FrameSink {
  @override
  bool get ready => true;
  @override
  void send(Map<String, dynamic> frame) {}
}
