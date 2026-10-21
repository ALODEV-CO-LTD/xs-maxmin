import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/friends/call_service.dart';
import 'package:mamba_app/features/friends/chat_models.dart';
import 'package:mamba_app/features/friends/chat_service.dart';
import 'package:mamba_app/features/friends/chat_store.dart';
import 'package:mamba_app/features/friends/friends_controller.dart';
import 'package:mamba_app/features/friends/keep_alive.dart';
import 'package:mamba_app/features/friends/messaging_settings.dart';
import 'package:mamba_app/features/friends/notifications.dart';
import 'package:mamba_app/features/friends/realtime_socket.dart';
import 'package:mamba_app/features/friends/screenshot_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

const hubId = 'user-aaaa-1111';
const peerId = 'user-bbbb-2222';
const secret = 'mật khẩu ví là 123456';

class RecordingNotifier implements AppNotifier {
  final List<NoticeContent> shown = [];
  final List<int> cancelled = [];
  int cancelAllCount = 0;
  bool permission = true;
  @override
  Future<void> init({required void Function(String? payload) onTap}) async {}
  @override
  Future<bool> requestPermission() async => permission;
  @override
  Future<bool> get allowed async => permission;
  @override
  Future<void> show(NoticeContent c) async => shown.add(c);
  @override
  Future<void> cancel(int id) async => cancelled.add(id);
  @override
  Future<void> cancelAll() async => cancelAllCount++;
  @override
  Future<String?> launchPayload() async => null;
}

class FakeBackground implements BackgroundService {
  final List<ServiceMode> modes = [];
  @override
  Future<void> apply(ServiceMode mode) async => modes.add(mode);
}

/// A socket that never touches the network: frames the test pushes come out of [frames]; frames the hub sends are
/// handed to [onSend] (the "server").
class FakeSocket extends RealtimeSocket {
  FakeSocket() : super(tokenProvider: () => 't');
  final _in = StreamController<Map<String, dynamic>>.broadcast();
  void Function(Map<String, dynamic>)? onSend;
  final List<Map<String, dynamic>> sent = [];
  bool started = false;
  @override
  bool get ready => true;
  @override
  Stream<Map<String, dynamic>> get frames => _in.stream;
  void push(Map<String, dynamic> f) => _in.add(f);
  @override
  void start() => started = true;
  @override
  void reconnectNow() {}
  @override
  void send(Map<String, dynamic> frame) {
    sent.add(frame);
    onSend?.call(frame);
  }
}

class PeerSink implements FrameSink {
  PeerSink(this.hub);
  final FakeSocket hub;
  @override
  bool ready = true;
  @override
  void send(Map<String, dynamic> f) {
    if (f['type'] == 'e2ee-msg') {
      hub.push({'type': 'e2ee-msg', 'id': f['id'], 'from': peerId, 'fromName': 'Bình', 'iv': f['iv'], 'ct': f['ct'], 'part': f['part'], 'parts': f['parts'], 'ts': f['ts']});
    }
  }
}

http.Response _json(Object body) => http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json; charset=utf-8'});

class Net {
  final Map<String, Map<String, dynamic>> keys = {};
  int supportUnread = 0;
  Map<String, int> unseenMissed = {};
  final List<String> requests = [];

  http.Client client(String me, String friend, String friendName) => MockClient((req) async {
        final path = req.url.path;
        requests.add('${req.method} $path');
        if (path.endsWith('/me/e2ee-key')) {
          if (req.method == 'PUT') keys[me] = (jsonDecode(req.body) as Map)['publicKey'] as Map<String, dynamic>;
          return _json({'publicKey': keys[me]});
        }
        if (path.endsWith('/me/friends')) return _json({'friends': [{'id': friend, 'name': friendName, 'username': 'u', 'isAdmin': false, 'publicKey': keys[friend]}]});
        if (path.endsWith('/me/customer-codes')) return _json({'codes': []});
        if (path.endsWith('/me/calls') ) return _json({'calls': [], 'unseenMissed': unseenMissed});
        if (path.endsWith('/me/unread')) return _json({'support': supportUnread});
        if (path.endsWith('/me')) return _json({'id': me, 'name': 'An', 'role': 'user'});
        return http.Response('{}', 404);
      });
}

class Rig {
  Rig(this.net)
      : socket = FakeSocket(),
        notifier = RecordingNotifier(),
        background = FakeBackground() {
    hub = FriendsController(api: ApiClient(AuthStore(), client: net.client(hubId, peerId, 'Bình')), auth: AuthStore(), notifier: notifier, background: background, socket: socket)
      ..storeFactory = ((_) async => MemoryChatStore())
      ..vault = MemoryKeyVault();
  }
  final Net net;
  final FakeSocket socket;
  final RecordingNotifier notifier;
  final FakeBackground background;
  late final FriendsController hub;
  late ChatService peer;

  Future<void> up() async {
    peer = ChatService(api: ApiClient(AuthStore(), client: net.client(peerId, hubId, 'An')), userId: peerId, store: MemoryChatStore(), vault: MemoryKeyVault(), socket: PeerSink(socket));
    await peer.init();
    await hub.start();
    await peer.loadFriendKeys();
    socket.onSend = (f) {
      if (f['type'] == 'e2ee-msg') peer.onFrame({'type': 'e2ee-msg', 'id': f['id'], 'from': hubId, 'iv': f['iv'], 'ct': f['ct'], 'part': f['part'], 'parts': f['parts'], 'ts': f['ts']});
    };
  }
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 80));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Net net;
  late Rig rig;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    net = Net();
    rig = Rig(net);
  });
  tearDown(() => rig.hub.dispose());

  group('notification text never reveals a message', () {
    test('payload builders only know the sender name', () {
      final n = messageNotice('f1', 'Bình');
      expect(n.title, 'MAMBA');
      expect(n.body, 'Tin nhắn mới từ Bình');
      expect(n.payload, 'chat:f1');
      expect(incomingCallNotice('f1', 'Bình').body, 'Bình đang gọi cho bạn');
      expect(missedCallNotice('f1', 'Bình').body, 'Cuộc gọi nhỡ từ Bình');
      expect(supportNotice().body, 'Có phản hồi mới từ Admin');
      expect(messageNotice('f1', '  ').body, 'Tin nhắn mới từ bạn bè');
      expect(messageNotice('f1', 'x' * 200).body.length, lessThan(70));
    });

    test('a real incoming encrypted message in the background raises a notification without its text', () async {
      await rig.up();
      rig.hub.setForeground(false);
      await rig.peer.send(hubId, secret);
      await settle();
      expect(rig.hub.chat!.unread[peerId], 1); // it was received and stored...
      expect((await rig.hub.chat!.messages(peerId)).single.text, secret);
      expect(rig.notifier.shown, hasLength(1)); // ...but the notification is generic
      final n = rig.notifier.shown.single;
      expect('${n.title}|${n.body}|${n.payload}', isNot(contains('123456')));
      expect('${n.title}|${n.body}|${n.payload}', isNot(contains('mật khẩu')));
      expect(n.body, 'Tin nhắn mới từ Bình');
      expect(rig.hub.banner, isNull);
    });

    test('screenshot notice also uses the generic text', () async {
      await rig.up();
      rig.hub.setForeground(false);
      await rig.peer.notifyScreenshot(hubId);
      await settle();
      expect(rig.notifier.shown.single.body, 'Tin nhắn mới từ Bình');
    });
  });

  group('where a new message is announced', () {
    test('foreground, other screen: in-app banner (with preview), no OS notification, badge counts', () async {
      await rig.up();
      await rig.peer.send(hubId, 'xin chào');
      await settle();
      expect(rig.notifier.shown, isEmpty);
      expect(rig.hub.banner!.title, 'Bình');
      expect(rig.hub.banner!.body, 'xin chào');
      expect(rig.hub.banner!.route, '/friends/chat/$peerId');
      expect(rig.hub.unreadTotal, 1);
    });

    test('foreground and that chat open: nothing at all and no unread', () async {
      await rig.up();
      rig.hub.chat!.openPeer = peerId;
      await rig.peer.send(hubId, 'đang xem');
      await settle();
      expect(rig.notifier.shown, isEmpty);
      expect(rig.hub.banner, isNull);
      expect(rig.hub.unreadTotal, 0);
    });

    test('chat open but the app is in the background: notification and unread both happen', () async {
      await rig.up();
      rig.hub.chat!.openPeer = peerId;
      rig.hub.setForeground(false);
      await rig.peer.send(hubId, 'ở nền');
      await settle();
      expect(rig.notifier.shown, hasLength(1));
      expect(rig.hub.chat!.unread[peerId], 1);
      rig.hub.setForeground(true); // back on screen with the chat open: read
      await settle();
      expect(rig.hub.chat!.unread[peerId], isNull);
    });

    test('alertForMessage table', () {
      expect(alertForMessage(foreground: true, openPeer: 'a', friendId: 'a'), MessageAlert.none);
      expect(alertForMessage(foreground: true, openPeer: 'b', friendId: 'a'), MessageAlert.banner);
      expect(alertForMessage(foreground: true, openPeer: null, friendId: 'a'), MessageAlert.banner);
      expect(alertForMessage(foreground: false, openPeer: 'a', friendId: 'a'), MessageAlert.notification);
    });
  });

  group('unread badge', () {
    test('unreadBadgeCount counts conversations (chat or missed call once each) + admin replies and ignores junk', () {
      expect(unreadBadgeCount(), 0);
      expect(unreadBadgeCount(chat: {'a': 2, 'b': 3}, missed: {'a': 1}, support: 4), 3); // chats a and b (a's missed call is the same chat) + the Admin reply
      expect(unreadBadgeCount(chat: {'a': 9}, missed: {'c': 1}), 2);
      expect(unreadBadgeCount(chat: {'a': -5, 'b': 0}, support: -1), 0);
    });

    test('hub total follows messages, missed calls from the server and the support poll', () async {
      net.supportUnread = 2;
      net.unseenMissed = {peerId: 1};
      await rig.up();
      await settle();
      expect(rig.hub.supportUnread, 2);
      expect(rig.hub.unseenMissed, {peerId: 1});
      expect(rig.hub.unreadTotal, 2); // the chat with a missed call (1) + the Admin reply (1)
      await rig.peer.send(hubId, 'a');
      await rig.peer.send(hubId, 'b');
      await settle();
      expect(rig.hub.unreadTotal, 2); // same chat: two more messages are still one chat
      rig.hub.markChatSeen(peerId);
      await settle();
      expect(rig.hub.unreadTotal, 2); // the missed call is still unseen
      expect(rig.notifier.cancelled, contains(noticeIdFor('msg:$peerId')));
    });

    test('support push (new-message) refreshes the counter and notifies in the background', () async {
      await rig.up();
      net.supportUnread = 1;
      rig.hub.setForeground(false);
      rig.socket.push({'type': 'new-message', 'source': 'support', 'from': 'admin1', 'fromName': 'Admin', 'preview': 'nội dung riêng'});
      await settle();
      expect(rig.hub.supportUnread, 1);
      expect(rig.notifier.shown.single.kind, NoticeKind.support);
      expect(rig.notifier.shown.single.body, isNot(contains('riêng')));
    });
  });

  group('calls around the hub', () {
    test('incoming call in the background: ringing notification, cancelled when answered/ended; missed call notice', () async {
      await rig.up();
      rig.hub.setForeground(false);
      rig.socket.push({'type': 'call-invite', 'from': peerId, 'fromName': 'Bình'});
      await settle();
      expect(rig.notifier.shown.single.kind, NoticeKind.incomingCall);
      expect(rig.notifier.shown.single.inApp, isFalse);
      rig.socket.push({'type': 'call-end', 'from': peerId});
      await settle();
      expect(rig.notifier.cancelled, contains(incomingCallNoticeId));
      expect(rig.notifier.shown.map((n) => n.kind), [NoticeKind.incomingCall, NoticeKind.missedCall]);
      expect(rig.notifier.shown.last.body, 'Cuộc gọi nhỡ từ Bình');
    });

    test('incoming call in the foreground uses the quiet in-app ring variant, and switches when the app is left', () async {
      await rig.up();
      rig.socket.push({'type': 'call-invite', 'from': peerId, 'fromName': 'Bình'});
      await settle();
      expect(rig.notifier.shown.single.inApp, isTrue);
      rig.hub.setForeground(false);
      await settle();
      expect(rig.notifier.shown.last.inApp, isFalse);
      rig.hub.call!.reject();
      await settle();
      expect(rig.notifier.cancelled, contains(incomingCallNoticeId));
    });

    test('a call keeps the app unlockable-safe (busy) and runs the microphone foreground service', () async {
      await rig.up();
      expect(rig.hub.callBusy, isFalse);
      rig.hub.call!.debugSetStatus(CallStatus.connected, withPeer: const CallPeer(peerId, 'Bình'));
      expect(rig.hub.callBusy, isTrue);
      await settle();
      expect(rig.background.modes.last, ServiceMode.call);
      rig.hub.call!.hangUp();
      await settle();
      expect(rig.hub.callBusy, isFalse);
      expect(rig.background.modes.last, ServiceMode.off);
    });

    test('second caller while busy is rejected with busy and shows as a missed call', () async {
      await rig.up();
      rig.socket.push({'type': 'call-invite', 'from': peerId, 'fromName': 'Bình'});
      await settle();
      rig.socket.push({'type': 'call-invite', 'from': 'user-cccc-3333', 'fromName': 'Chi'});
      await settle();
      expect(rig.socket.sent.last, {'type': 'call-reject', 'to': 'user-cccc-3333', 'reason': 'busy'});
      expect(rig.hub.banner!.body, contains('Chi'));
    });
  });

  group('keep-alive setting (default off)', () {
    test('desiredServiceMode', () {
      expect(desiredServiceMode(keepAlive: false, inCall: false), ServiceMode.off);
      expect(desiredServiceMode(keepAlive: true, inCall: false), ServiceMode.keepAlive);
      expect(desiredServiceMode(keepAlive: false, inCall: true), ServiceMode.call);
      expect(desiredServiceMode(keepAlive: true, inCall: true), ServiceMode.call);
    });

    test('off by default, persisted when switched on, restored at the next start', () async {
      await rig.up();
      expect(rig.hub.keepAlive, isFalse);
      expect(rig.background.modes, isEmpty);
      await rig.hub.setKeepAlive(true);
      expect(rig.background.modes.last, ServiceMode.keepAlive);
      expect(await KeepAliveSettings.load(), isTrue);

      final again = Rig(net);
      addTearDown(again.hub.dispose);
      await again.up();
      expect(again.hub.keepAlive, isTrue);
      expect(again.background.modes.last, ServiceMode.keepAlive);
      await again.hub.setKeepAlive(false);
      expect(again.background.modes.last, ServiceMode.off);
    });

    test('the UI text is honest about battery use', () {
      expect(keepAliveExplain, contains('TỐN PIN'));
      expect(keepAliveTitle, 'Giữ kết nối để nhận tin nhắn và cuộc gọi khi thoát app');
    });
  });

  group('notification taps', () {
    test('payloads parse and map to go_router locations', () {
      expect(routeForTarget(parseNoticePayload('chat:abc')!), '/friends/chat/abc');
      expect(routeForTarget(parseNoticePayload('missed:abc')!), '/friends/chat/abc');
      expect(routeForTarget(parseNoticePayload('support')!), '/support');
      expect(routeForTarget(parseNoticePayload('call:abc')!), isNull);
      expect(parseNoticePayload(null), isNull);
      expect(parseNoticePayload('chat:'), isNull);
      expect(parseNoticePayload('evil:abc'), isNull);
      expect(routeForTarget(const NoticeTarget(NoticeKind.message, 'a/b c')), '/friends/chat/a%2Fb%20c');
    });

    test('ids are stable and per friend', () {
      expect(noticeIdFor('msg:x'), noticeIdFor('msg:x'));
      expect(noticeIdFor('msg:x'), isNot(noticeIdFor('msg:y')));
      expect(noticeIdFor('msg:x'), isNot(incomingCallNoticeId));
    });
  });

  group('screenshot notice wiring', () {
    test('a screenshot report with a chat open sends the encrypted notice to that friend', () async {
      await rig.up();
      rig.hub.chat!.openPeer = peerId;
      await rig.hub.screenshots.handle(const MethodCall('screenshot'));
      await settle();
      expect(rig.hub.screenshots.sent, 1);
      final got = (await rig.peer.messages(hubId)).single;
      expect(got.sys, SysKind.screenshot);
      // the relay only ever carried ciphertext
      expect(rig.socket.sent.where((f) => f['type'] == 'e2ee-msg'), hasLength(1));
      expect(jsonEncode(rig.socket.sent), isNot(contains('screenshot')));
    });

    test('no chat open, or app in the background, or another method: nothing is sent', () async {
      await rig.up();
      await rig.hub.screenshots.handle(const MethodCall('screenshot'));
      rig.hub.chat!.openPeer = peerId;
      rig.hub.setForeground(false);
      await rig.hub.screenshots.handle(const MethodCall('screenshot'));
      rig.hub.setForeground(true);
      await rig.hub.screenshots.handle(const MethodCall('other'));
      await settle();
      expect(rig.hub.screenshots.sent, 0);
      expect(await rig.peer.messages(hubId), isEmpty);
    });

    test('the app-scope listener is registered on the mamba/screenshot channel and removed on dispose', () async {
      await rig.up();
      rig.hub.chat!.openPeer = peerId;
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Future<void> fire() => messenger.handlePlatformMessage(screenshotChannel.name, const StandardMethodCodec().encodeMethodCall(const MethodCall('screenshot')), (_) {});
      await fire();
      await settle();
      expect(rig.hub.screenshots.sent, 1);
      rig.hub.screenshots.detach();
      await fire();
      await settle();
      expect(rig.hub.screenshots.sent, 1);
    });
  });

  test('dispose wipes: socket is not restarted, notifications cancelled, service stopped, session keys dropped', () async {
    await rig.up();
    final chat = rig.hub.chat!;
    expect(chat.ready, isTrue);
    rig.hub.dispose();
    expect(rig.notifier.cancelAllCount, greaterThan(0));
    expect(rig.background.modes.last, ServiceMode.off);
    expect(chat.ready, isFalse);
    expect(chat.friendKeys, isEmpty);
  });
}
