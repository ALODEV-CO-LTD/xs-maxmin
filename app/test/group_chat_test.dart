import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/friends/chat_models.dart';
import 'package:mamba_app/features/friends/chat_service.dart';
import 'package:mamba_app/features/friends/chat_store.dart';
import 'package:mamba_app/features/friends/realtime_socket.dart';

/// Three devices, one in-memory relay: it hands `e2ee-msg` / `e2ee-ack` frames to the addressed service like the real server does
/// (the sender id is added by the relay), and knows nothing else - exactly what a group chat needs.
class _Relay {
  final Map<String, ChatService> services = {};
  final Map<String, Map<String, dynamic>> keys = {};
  final List<String> sentTo = [];
  final List<String> acks = [];
}

class _Sock extends RealtimeSocket {
  _Sock(this.relay, this.me) : super(tokenProvider: () => 't');
  final _Relay relay;
  final String me;
  @override
  bool get ready => true;
  @override
  void start() {}
  @override
  void send(Map<String, dynamic> frame) {
    final to = frame['to'];
    final target = relay.services[to];
    if (target == null) return;
    if (frame['type'] == 'e2ee-msg') {
      relay.sentTo.add('$me>$to');
      Future(() => target.onFrame({...frame, 'from': me, 'fromName': 'Tên $me'}));
    } else if (frame['type'] == 'e2ee-ack') {
      relay.acks.add('$me>$to:${frame['id']}');
      Future(() => target.onFrame({'type': 'e2ee-ack', 'id': frame['id'], 'from': me}));
    }
  }
}

ChatService _device(_Relay r, String me, List<String> friends) {
  final client = MockClient((req) async {
    final path = req.url.path.replaceFirst('/api', '');
    http.Response ok(Object o) => http.Response(jsonEncode(o), 200, headers: {'content-type': 'application/json'});
    if (path == '/me/e2ee-key' && req.method == 'GET') return ok({'publicKey': r.keys[me]});
    if (path == '/me/e2ee-key' && req.method == 'PUT') {
      r.keys[me] = (jsonDecode(req.body) as Map)['publicKey'] as Map<String, dynamic>;
      return ok({'ok': true});
    }
    if (path == '/me/friends') {
      return ok({
        'friends': [for (final f in friends) {'id': f, 'name': 'Tên $f', 'username': f, 'publicKey': r.keys[f]}],
      });
    }
    return http.Response('{}', 404);
  });
  final svc = ChatService(api: ApiClient(AuthStore(), client: client), userId: me, store: MemoryChatStore(), vault: MemoryKeyVault(), socket: _Sock(r, me), ackWait: const Duration(seconds: 30));
  r.services[me] = svc;
  return svc;
}

Future<void> _settle() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late _Relay relay;
  late ChatService a, b, c;

  setUp(() async {
    relay = _Relay();
    a = _device(relay, 'A', ['B', 'C', 'D']); // D joins some tests later (no key until then)
    b = _device(relay, 'B', ['A', 'C', 'D']);
    c = _device(relay, 'C', ['A', 'B', 'D']);
    for (final s in [a, b, c]) {
      await s.init(); // publishes its public key
    }
    for (final s in [a, b, c]) {
      await s.loadFriendKeys(); // now everybody's key is known
    }
  });

  test('creating a group tells every member; messages reach everybody with the writer named; nothing needs the server', () async {
    final g = await a.createGroup('Nhóm lô', 'An', [const GroupMember('B', 'Bình'), const GroupMember('C', 'Cường')]);
    await _settle();
    expect(isGroupId(g.id), isTrue);
    for (final s in [a, b, c]) {
      final got = s.groups[g.id];
      expect(got, isNotNull, reason: 'every member knows the group');
      expect(got!.name, 'Nhóm lô');
      expect(got.members.map((m) => m.id).toSet(), {'A', 'B', 'C'});
      expect(got.creatorId, 'A');
    }

    await a.send(g.id, 'chào cả nhóm');
    await _settle();
    for (final s in [b, c]) {
      final msgs = await s.messages(g.id);
      expect(msgs.single.text, 'chào cả nhóm');
      expect(msgs.single.fromId, 'A');
      expect(msgs.single.mine, isFalse);
      expect(s.unread[g.id], 1);
    }
    final mine = (await a.messages(g.id)).single;
    expect(mine.mine, isTrue);
    expect(mine.status, MsgStatus.delivered); // at least one member confirmed

    // a member answers: the other two get it, named after the writer
    await b.send(g.id, 'chào anh');
    await _settle();
    final atC = await c.messages(g.id);
    expect(atC.map((m) => (m.fromId, m.text)), [('A', 'chào cả nhóm'), ('B', 'chào anh')]);
    expect((await a.messages(g.id)).last.fromId, 'B');
    expect(b.memberName(b.groups[g.id]!, 'A'), 'An');
    expect(b.memberName(b.groups[g.id]!, 'B'), 'Bạn');
  });

  test('a message is encrypted once per member (never one copy for the group): the relay carries one frame per recipient', () async {
    final g = await a.createGroup('Nhóm', 'An', [const GroupMember('B', 'Bình'), const GroupMember('C', 'Cường')]);
    await _settle();
    relay.sentTo.clear();
    await a.send(g.id, 'x');
    await _settle();
    expect(relay.sentTo.toSet(), {'A>B', 'A>C'});
    expect(relay.sentTo.length, 2);
  });

  test('renaming reaches the members; leaving removes the person for the others and the group from their device', () async {
    final g = await a.createGroup('Tên cũ', 'An', [const GroupMember('B', 'Bình'), const GroupMember('C', 'Cường')]);
    await _settle();
    await a.renameGroup(g.id, 'Tên mới');
    await _settle();
    expect(b.groups[g.id]!.name, 'Tên mới');
    expect(c.groups[g.id]!.name, 'Tên mới');

    await c.send(g.id, 'tôi sắp rời');
    await _settle();
    await c.leaveGroup(g.id);
    await _settle();
    expect(c.groups.containsKey(g.id), isFalse);
    expect(await c.messages(g.id), isEmpty);
    expect(a.groups[g.id]!.members.map((m) => m.id).toSet(), {'A', 'B'});
    expect(b.groups[g.id]!.members.map((m) => m.id).toSet(), {'A', 'B'});
    expect((await a.messages(g.id)).single.text, 'tôi sắp rời'); // what was said stays for the others
  });

  test('a group needs a name and at least 2 friends', () async {
    expect(() => a.createGroup('  ', 'An', [const GroupMember('B', 'B'), const GroupMember('C', 'C')]), throwsException);
    expect(() => a.createGroup('Nhóm', 'An', [const GroupMember('B', 'B')]), throwsException);
    expect(() => a.createGroup('Nhóm', 'An', [const GroupMember('B', 'B'), const GroupMember('B', 'B')]), throwsException); // the same person twice is one
  });

  test('a stranger who is not a member cannot post into a group', () async {
    final g = await a.createGroup('Kín', 'An', [const GroupMember('B', 'Bình'), const GroupMember('C', 'Cường')]);
    await _settle();
    final d = _device(relay, 'D', ['B']); // not in the group
    await d.init();
    await d.loadFriendKeys();
    await b.loadFriendKeys();
    // D forges a message of group g (creator A) without being in its member list
    final forged = ChatGroup(id: g.id, name: 'Kín', members: const [GroupMember('A', 'An'), GroupMember('B', 'Bình')], creatorId: 'A', updatedAt: DateTime.now().millisecondsSinceEpoch + 1000);
    await d.debugSendGroupFrame(forged, 'B', 'xin chào, tôi chen vào');
    await _settle();
    expect((await b.messages(g.id)).where((m) => m.text.contains('chen vào')), isEmpty);
  });

  test('the creator adds a member: the newcomer learns the group, everybody lists them, old messages stay private', () async {
    final g = await a.createGroup('Nhóm', 'An', [const GroupMember('B', 'Bình'), const GroupMember('C', 'Cường')]);
    await _settle();
    await a.send(g.id, 'tin cũ');
    await _settle();
    final d = _device(relay, 'D', ['A', 'B', 'C']);
    await d.init();
    for (final s in [a, b, c, d]) {
      await s.loadFriendKeys();
    }
    await a.addGroupMembers(g.id, [const GroupMember('D', 'Dũng')]);
    await _settle();
    for (final s in [a, b, c, d]) {
      expect(s.groups[g.id]!.members.map((m) => m.id).toSet(), {'A', 'B', 'C', 'D'}, reason: 'everybody lists the new member');
    }
    expect(await d.messages(g.id), isEmpty); // what was said before is not given to the newcomer
    await a.send(g.id, 'chào Dũng');
    await _settle();
    expect((await d.messages(g.id)).single.text, 'chào Dũng');
  });

  test('the creator removes a member: they drop the group, the others list one person less; only the creator can', () async {
    final g = await a.createGroup('Nhóm', 'An', [const GroupMember('B', 'Bình'), const GroupMember('C', 'Cường')]);
    await _settle();
    await b.removeGroupMember(g.id, 'C'); // B is not the creator: nothing happens
    await _settle();
    expect(a.groups[g.id]!.members.length, 3);
    await a.removeGroupMember(g.id, 'C');
    await _settle();
    expect(c.groups.containsKey(g.id), isFalse, reason: 'the removed person drops the group');
    for (final s in [a, b]) {
      expect(s.groups[g.id]!.members.map((m) => m.id).toSet(), {'A', 'B'});
    }
  });

  test('a removed member cannot inject messages by declaring themselves in the header', () async {
    final g = await a.createGroup('Nhóm', 'An', [const GroupMember('B', 'Bình'), const GroupMember('C', 'Cường')]);
    await _settle();
    await a.removeGroupMember(g.id, 'C');
    await _settle();
    final forged = ChatGroup(id: g.id, name: 'Nhóm', members: const [GroupMember('A', 'An'), GroupMember('B', 'Bình'), GroupMember('C', 'Cường')], creatorId: 'A', updatedAt: 1);
    await c.debugSendGroupFrame(forged, 'B', 'tôi vẫn còn đây');
    await _settle();
    expect((await b.messages(g.id)).where((m) => m.text.contains('vẫn còn')), isEmpty);
  });

  test('group-left: the list must be exactly the old one minus the sender; a huge updatedAt does not freeze updates', () async {
    final g = await a.createGroup('Nhóm', 'An', [const GroupMember('B', 'Bình'), const GroupMember('C', 'Cường')]);
    await _settle();
    // B claims to leave but also drops C from the list
    final bad = ChatGroup(id: g.id, name: 'Nhóm', members: const [GroupMember('A', 'An'), GroupMember('X', 'X')], creatorId: 'A', updatedAt: DateTime.now().millisecondsSinceEpoch + 1000);
    await b.debugSendGroupFrame(bad, 'C', '', kind: 'group-left');
    await _settle();
    expect(c.groups[g.id]!.members.map((m) => m.id).toSet(), {'A', 'B', 'C'});
    // an honest leave with an absurd updatedAt is applied but clamped, so the creator's next update still wins
    final ok = ChatGroup(id: g.id, name: 'Nhóm', members: const [GroupMember('A', 'An'), GroupMember('C', 'Cường')], creatorId: 'A', updatedAt: 1 << 60);
    await b.debugSendGroupFrame(ok, 'C', '', kind: 'group-left');
    await _settle();
    expect(c.groups[g.id]!.members.map((m) => m.id).toSet(), {'A', 'C'});
    expect(c.groups[g.id]!.updatedAt, lessThan(DateTime.now().millisecondsSinceEpoch + 120000));
  });

  test('a duplicate is shown once but acknowledged again (the first ack may have been lost)', () async {
    final g = await a.createGroup('Nhóm', 'An', [const GroupMember('B', 'Bình'), const GroupMember('C', 'Cường')]);
    await _settle();
    await a.debugSendGroupFrame(g, 'B', 'một lần', id: 'dup-1');
    await _settle();
    await a.debugSendGroupFrame(g, 'B', 'một lần', id: 'dup-1');
    await _settle();
    expect((await b.messages(g.id)).where((m) => m.text == 'một lần').length, 1);
    expect(relay.acks.where((x) => x == 'B>A:dup-1').length, 2);
  });

  test('a hostile old timestamp cannot bury a message', () async {
    final g = await a.createGroup('Nhóm', 'An', [const GroupMember('B', 'Bình'), const GroupMember('C', 'Cường')]);
    await _settle();
    await a.debugSendGroupFrame(g, 'B', 'cổ xưa', ts: 1000);
    await _settle();
    final got = (await b.messages(g.id)).singleWhere((m) => m.text == 'cổ xưa');
    expect(got.createdAt, greaterThan(DateTime.now().millisecondsSinceEpoch - 10 * 60000));
  });

  test('a member who is not the creator cannot change the group by sending a forged newer header', () async {
    final g = await a.createGroup('Nhóm', 'An', [const GroupMember('B', 'Bình'), const GroupMember('C', 'Cường')]);
    await _settle();
    final forged = ChatGroup(id: g.id, name: 'Bị đổi tên', members: const [GroupMember('A', 'An'), GroupMember('B', 'Bình'), GroupMember('C', 'Cường')], creatorId: 'A', updatedAt: DateTime.now().millisecondsSinceEpoch + 5000);
    await b.debugSendGroupFrame(forged, 'C', 'tin của B kèm danh sách giả');
    await _settle();
    expect(c.groups[g.id]!.name, 'Nhóm');
    expect(c.groups[g.id]!.members.length, 3);
    expect((await c.messages(g.id)).single.text, 'tin của B kèm danh sách giả'); // the message itself is fine
  });
}
