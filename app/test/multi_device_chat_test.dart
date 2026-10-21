import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/friends/chat_models.dart';
import 'package:mamba_app/features/friends/chat_service.dart';
import 'package:mamba_app/features/friends/chat_store.dart';
import 'package:mamba_app/features/friends/e2ee_crypto.dart';
import 'package:mamba_app/features/friends/realtime_socket.dart';

const ana = 'user-ana-1111';
const huong = 'user-huong-2222';

/// A relay with one key PER DEVICE, like backend/routes/api/ws/calls.dart: a frame goes to the device it is addressed to.
class Net {
  final Map<String, Map<String, Map<String, dynamic>>> devices = {}; // user -> device -> public key
  final Map<String, ChatService> online = {}; // 'user|device' -> service

  http.Client clientFor(String me, String friend) => MockClient((req) async {
        final path = req.url.path;
        final m = RegExp(r'/me/e2ee-devices/([^/]+)$').firstMatch(path);
        if (m != null && req.method == 'PUT') {
          devices.putIfAbsent(me, () => {})[m.group(1)!] = (jsonDecode(req.body) as Map)['publicKey'] as Map<String, dynamic>;
          return _json({'ok': true});
        }
        if (path.endsWith('/me/friends')) {
          final list = [for (final e in (devices[friend] ?? {}).entries) {'id': e.key, 'publicKey': e.value}];
          return _json({
            'friends': [
              {'id': friend, 'name': 'Bạn', 'username': 'ban', 'isAdmin': false, 'publicKey': list.isEmpty ? null : list.last['publicKey'], 'devices': list},
            ],
          });
        }
        return http.Response('{}', 404);
      });
}

http.Response _json(Object body) => http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json; charset=utf-8'});

class Sock implements FrameSink {
  Sock(this.net, this.me);
  final Net net;
  final String me;
  late ChatService self;
  @override
  bool ready = true;
  final List<Map<String, dynamic>> sent = [];

  @override
  void send(Map<String, dynamic> f) {
    sent.add(f);
    final to = f['to'] as String;
    final dev = f['toDevice'] as String?;
    final targets = [for (final e in net.online.entries) if (e.key.startsWith('$to|') && (dev == null || e.key == '$to|$dev')) e.value];
    if (f['type'] == 'e2ee-ack') {
      for (final t in targets) {
        t.onFrame({'type': 'e2ee-ack', 'id': f['id'], 'from': me, 'fromDevice': self.myDeviceId});
      }
      return;
    }
    if (targets.isEmpty) {
      self.onFrame({'type': 'e2ee-undelivered', 'id': f['id'], 'to': to, 'toDevice': dev, 'reason': 'offline'});
      return;
    }
    for (final t in targets) {
      t.onFrame({'type': 'e2ee-msg', 'id': f['id'], 'from': me, 'fromDevice': self.myDeviceId, 'fromName': 'Người $me', 'iv': f['iv'], 'ct': f['ct'], 'part': f['part'], 'parts': f['parts'], 'ts': f['ts']});
    }
  }
}

Future<ChatService> device(Net net, String me, String friend, {bool online = true, MemoryKeyVault? vault}) async {
  final sock = Sock(net, me);
  final svc = ChatService(
    api: ApiClient(AuthStore(), client: net.clientFor(me, friend)),
    userId: me,
    store: MemoryChatStore(),
    vault: vault ?? MemoryKeyVault(),
    socket: sock,
    ackWait: const Duration(seconds: 15),
  );
  sock.self = svc;
  await svc.init();
  if (online) net.online['$me|${svc.myDeviceId}'] = svc;
  return svc;
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 80));

void main() {
  late Net net;
  setUp(() => net = Net());

  test('each device registers its own key: the second device does not replace the first', () async {
    final phone = await device(net, huong, ana);
    final tablet = await device(net, huong, ana);
    expect(phone.myDeviceId, isNot(tablet.myDeviceId));
    expect(net.devices[huong]!.length, 2);
    expect(net.devices[huong]![phone.myDeviceId], isNot(net.devices[huong]![tablet.myDeviceId]));
  });

  test('a message reaches every device of the friend, each encrypted with that device\'s own key', () async {
    final phone = await device(net, huong, ana);
    final tablet = await device(net, huong, ana);
    final a = await device(net, ana, huong);
    await a.loadFriendKeys();
    expect(a.friendDevices[huong]!.length, 2);

    await a.send(huong, 'Chào Hương');
    await settle();
    expect((await phone.messages(ana)).single.text, 'Chào Hương');
    expect((await tablet.messages(ana)).single.text, 'Chào Hương');
    // two copies, two different ciphertexts
    final frames = (a.socket as Sock).sent.where((f) => f['type'] == 'e2ee-msg').toList();
    expect(frames.length, 2);
    expect(frames[0]['ct'], isNot(frames[1]['ct']));
    expect({for (final f in frames) f['toDevice']}, {phone.myDeviceId, tablet.myDeviceId});
    expect((await a.messages(huong)).single.status, MsgStatus.delivered);
  });

  test('one device offline: the message is delivered through the other and does not show as failed', () async {
    final phone = await device(net, huong, ana);
    await device(net, huong, ana, online: false); // tablet: registered, not connected
    final a = await device(net, ana, huong);
    await a.loadFriendKeys();
    await a.send(huong, 'Còn ai không?');
    await settle();
    expect((await phone.messages(ana)).single.text, 'Còn ai không?');
    expect((await a.messages(huong)).single.status, MsgStatus.delivered);
  });

  test('every device offline: failed with the reason "offline"', () async {
    await device(net, huong, ana, online: false);
    await device(net, huong, ana, online: false);
    final a = await device(net, ana, huong);
    await a.loadFriendKeys();
    await a.send(huong, 'Alo');
    await settle();
    final m = (await a.messages(huong)).single;
    expect(m.status, MsgStatus.failed);
    expect(m.reason, 'offline');
  });

  test('a reply from one device is read with THAT device\'s key and acked back to it', () async {
    final phone = await device(net, huong, ana);
    await device(net, huong, ana); // tablet
    final a = await device(net, ana, huong);
    await a.loadFriendKeys();
    await phone.loadFriendKeys();
    await phone.send(ana, 'Từ điện thoại');
    await settle();
    expect((await a.messages(huong)).single.text, 'Từ điện thoại');
    expect((await phone.messages(ana)).single.status, MsgStatus.delivered);
  });

  test('a friend adding a device is not a "key changed" warning; a changed key of a known device is', () async {
    final a = await device(net, ana, huong);
    final phone = await device(net, huong, ana);
    await a.loadFriendKeys();
    expect(a.peerInfo[huong]!.changed, isFalse);

    await device(net, huong, ana); // a second device appears
    await a.loadFriendKeys();
    expect(a.peerInfo[huong]!.changed, isFalse);
    expect(a.peerInfo[huong]!.devices, 2);

    // the same device id with a different key (app data cleared and the id re-made with the same value is not possible, the server
    // would show a new key for that id)
    net.devices[huong]![phone.myDeviceId!] = E2eeIdentity.generate().publicJwk;
    await a.loadFriendKeys();
    expect(a.peerInfo[huong]!.changed, isTrue);
    await a.acceptKeyChange(huong);
    await a.loadFriendKeys();
    expect(a.peerInfo[huong]!.changed, isFalse);
  });

  test('the device id is kept between launches (so a restart does not add a new device)', () async {
    final vault = MemoryKeyVault();
    final first = await device(net, huong, ana, vault: vault);
    final again = await device(net, huong, ana, vault: vault);
    expect(again.myDeviceId, first.myDeviceId);
    expect(net.devices[huong]!.length, 1);
  });
}
