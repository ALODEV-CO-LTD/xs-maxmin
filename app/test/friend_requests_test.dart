import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/friends/chat_service.dart';
import 'package:mamba_app/features/friends/chat_store.dart';
import 'package:mamba_app/features/friends/fcm_push_port.dart';
import 'package:mamba_app/features/friends/friends_controller.dart';
import 'package:mamba_app/features/friends/friends_screen.dart';
import 'package:mamba_app/features/friends/messaging_host.dart';
import 'package:mamba_app/features/friends/notifications.dart';
import 'package:mamba_app/features/friends/push_registrar.dart';
import 'package:mamba_app/features/friends/realtime_socket.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Notifier implements AppNotifier {
  final List<NoticeContent> shown = [];
  @override
  Future<void> init({required void Function(String? payload) onTap}) async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<bool> get allowed async => true;
  @override
  Future<void> show(NoticeContent c) async => shown.add(c);
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<void> cancelAll() async {}
  @override
  Future<String?> launchPayload() async => null;
}

class _Sock extends RealtimeSocket {
  _Sock() : super(tokenProvider: () => 't');
  final _in = StreamController<Map<String, dynamic>>.broadcast();
  @override
  bool get ready => true;
  @override
  Stream<Map<String, dynamic>> get frames => _in.stream;
  void push(Map<String, dynamic> f) => _in.add(f);
  @override
  void start() {}
  @override
  void reconnectNow() {}
  @override
  void send(Map<String, dynamic> frame) {}
}

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic> _row(String id, String name, String username) => {
  'id': id,
  'name': name,
  'username': username,
  'isAdmin': false,
  'publicKey': null,
};

/// The backend contract of friend requests, in memory.
class Server {
  final List<Map<String, dynamic>> friends = [];
  final List<Map<String, dynamic>> incoming = [];
  final List<Map<String, dynamic>> outgoing = [];
  List<Map<String, dynamic>> searchResults = [];
  Map<String, dynamic>? addAnswer;
  int? addStatus;
  final List<String> log = [];

  int get unread => incoming.length;

  http.Client client() => MockClient((req) async {
    final path = req.url.path.replaceFirst('/api', '');
    log.add('${req.method} $path');
    if (path == '/me/e2ee-key') return _json({'publicKey': null});
    if (path == '/me/friends' && req.method == 'GET') {
      return _json({'friends': friends});
    }
    if (path == '/me/friends' && req.method == 'POST') {
      if (addStatus != null) {
        return _json({'error': 'Không thêm được'}, addStatus!);
      }
      return _json(addAnswer!);
    }
    if (path == '/me/friends/search') return _json({'results': searchResults});
    if (path == '/me/customer-codes') return _json({'codes': []});
    if (path == '/me/calls') return _json({'calls': [], 'unseenMissed': {}});
    if (path == '/me/unread') {
      return _json({'support': 0, 'friendRequests': unread});
    }
    if (path == '/me/friend-requests') {
      return _json({'incoming': incoming, 'outgoing': outgoing});
    }
    final m = RegExp(r'^/me/friend-requests/([^/]+)(/accept|/decline)?$')
        .firstMatch(path);
    if (m != null) {
      final id = m.group(1)!;
      if (req.method == 'POST' && m.group(2) == '/accept') {
        final r = incoming.where((x) => x['id'] == id).firstOrNull;
        if (r == null) return _json({'error': 'Lời mời không còn'}, 404);
        incoming.remove(r);
        final f = _row(
          r['fromId'] as String,
          r['fromName'] as String,
          r['fromUsername'] as String,
        );
        friends.add(f);
        return _json({'friend': f});
      }
      if (req.method == 'POST' && m.group(2) == '/decline') {
        incoming.removeWhere((x) => x['id'] == id);
        return _json({'ok': true});
      }
      if (req.method == 'DELETE') {
        outgoing.removeWhere((x) => x['id'] == id);
        return _json({'ok': true});
      }
    }
    if (path == '/me') return _json({'id': 'me', 'name': 'An', 'role': 'user'});
    return http.Response('{}', 404);
  });
}

Map<String, dynamic> _inReq(String id, String from, String name, String user) =>
    {
      'id': id,
      'fromId': from,
      'fromName': name,
      'fromUsername': user,
      'createdAt': 1,
    };
Map<String, dynamic> _outReq(String id, String to, String name, String user) =>
    {'id': id, 'toId': to, 'toName': name, 'toUsername': user, 'createdAt': 1};

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 60));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Server server;
  late _Sock sock;
  late _Notifier notifier;
  late FriendsController hub;

  Future<void> boot() async {
    sock = _Sock();
    notifier = _Notifier();
    hub =
        FriendsController(
            api: ApiClient(AuthStore(), client: server.client()),
            auth: AuthStore(),
            notifier: notifier,
            socket: sock,
          )
          ..storeFactory = ((_) async => MemoryChatStore())
          ..vault = MemoryKeyVault();
    await hub.start();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    server = Server();
  });

  group('wire helpers', () {
    test('badge total counts pending incoming requests', () {
      expect(
        unreadBadgeCount(chat: {'a': 2}, support: 1, friendRequests: 3),
        6,
      );
      expect(unreadBadgeCount(friendRequests: -2), 0);
    });

    test('request notices: text, payload, tap route; old kinds untouched', () {
      final n = friendRequestNotice('u9', 'Bình');
      expect(n.title, 'Lời mời kết bạn');
      expect(n.body, 'Bình muốn kết bạn với bạn');
      expect(n.payload, 'freq:u9');
      final t = parseNoticePayload(n.payload)!;
      expect(t.kind, NoticeKind.friendRequest);
      expect(routeForTarget(t), '/friends');
      expect(
        friendAcceptedNotice('u9', 'Bình').body,
        'Bình đã chấp nhận lời mời',
      );
      expect(routeForTarget(parseNoticePayload('facc:u9')!), '/friends');
      expect(parseNoticePayload('chat:f1')!.kind, NoticeKind.message);
      expect(parseNoticePayload('missed:f1')!.kind, NoticeKind.missedCall);
      expect(parseNoticePayload('support')!.kind, NoticeKind.support);
      expect(parseNoticePayload('freq:'), isNull);
    });

    test('push kind: friendRequest is recognised, anything unknown stays a message', () {
      expect(pushKindOf('friendRequest'), 'friendRequest');
      expect(pushKindOf('call'), 'call');
      expect(pushKindOf('weird'), 'message');
      expect(pushKindOf(null), 'message');
      expect(
        FcmPushPort.openedFromData({'friendId': 'u1', 'kind': 'friendRequest'})!
            .kind,
        'friendRequest',
      );
      expect(
        FcmPushPort.openedFromData({'friendId': 'u1', 'kind': 'friendRequest'})!
            .friendId,
        'u1',
      );
      expect(FcmPushPort.openedFromData({'friendId': 'u1'})!.kind, 'message');
    });

    test('FriendRequest parsing', () {
      final i = FriendRequest.incomingFrom(_inReq('r1', 'u1', 'Bình', 'binh'));
      expect(
        (i.id, i.userId, i.name, i.username, i.incoming),
        ('r1', 'u1', 'Bình', 'binh', true),
      );
      final o = FriendRequest.outgoingTo(_outReq('r2', 'u2', 'Cúc', 'cuc'));
      expect(
        (o.id, o.userId, o.name, o.username, o.incoming),
        ('r2', 'u2', 'Cúc', 'cuc', false),
      );
    });
  });

  group('controller', () {
    tearDown(() => hub.dispose());

    test(
      'start loads the requests; the badge is the pending incoming count',
      () async {
        server.incoming.add(_inReq('r1', 'u1', 'Bình', 'binh'));
        server.outgoing.add(_outReq('r2', 'u2', 'Cúc', 'cuc'));
        await boot();
        expect(hub.incomingRequests.single.name, 'Bình');
        expect(hub.outgoingRequests.single.name, 'Cúc');
        expect(hub.pendingIncoming, 1);
        expect(hub.unreadTotal, 1);
      },
    );

    test(
      '/me/unread friendRequests refreshes the badge and the list',
      () async {
        await boot();
        expect(hub.unreadTotal, 0);
        server.incoming.add(_inReq('r1', 'u1', 'Bình', 'binh'));
        await hub.pollUnread();
        await settle();
        expect(hub.pendingIncoming, 1);
        expect(hub.incomingRequests, hasLength(1));
      },
    );

    test('search results carry requestState', () async {
      server.searchResults = [
        {
          'id': 'u1',
          'name': 'A',
          'username': 'a',
          'isFriend': false,
          'requestState': 'outgoing',
        },
        {
          'id': 'u2',
          'name': 'B',
          'username': 'b',
          'isFriend': false,
          'requestState': 'incoming',
        },
        {'id': 'u3', 'name': 'C', 'username': 'c', 'isFriend': false},
      ];
      await boot();
      hub.setSearch('a');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(hub.results.map((r) => r.requestState), [
        'outgoing',
        'incoming',
        'none',
      ]);
    });

    test('adding someone sends a request: notice, outgoing state, NOT added to the list', () async {
      server.addAnswer = {
        'status': 'pending',
        'request': _outReq('r5', 'u5', 'Dũng', 'dung'),
      };
      await boot();
      final r = SearchResult(
        id: 'u5',
        name: 'Dũng',
        username: 'dung',
        isFriend: false,
      );
      server.outgoing.add(_outReq('r5', 'u5', 'Dũng', 'dung'));
      await hub.addFriend(r);
      await settle();
      expect(
        hub.addNotice,
        'Đã gửi lời mời kết bạn tới Dũng. Họ cần chấp nhận.',
      );
      expect(r.requestState, 'outgoing');
      expect(r.isFriend, isFalse);
      expect(hub.friends, isEmpty);
      expect(hub.outgoingRequests.single.id, 'r5');
    });

    test('pending answer without a request object (200 repeat) still counts as sent', () async {
      server.addAnswer = {'status': 'pending'};
      await boot();
      final r = SearchResult(
        id: 'u5',
        name: 'Dũng',
        username: 'dung',
        isFriend: false,
      );
      await hub.addFriend(r);
      expect(r.requestState, 'outgoing');
      expect(hub.addNotice, contains('Dũng'));
    });

    test(
      'status friends (they had asked me) adds the friend as before',
      () async {
        server.incoming.add(_inReq('r1', 'u1', 'Bình', 'binh'));
        server.addAnswer = {
          'status': 'friends',
          'friend': _row('u1', 'Bình', 'binh'),
        };
        await boot();
        final r = SearchResult(
          id: 'u1',
          name: 'Bình',
          username: 'binh',
          isFriend: false,
          requestState: 'incoming',
        );
        await hub.addFriend(r);
        expect(r.isFriend, isTrue);
        expect(hub.friends.single.id, 'u1');
        expect(hub.addNotice, '');
        expect(hub.incomingRequests, isEmpty);
        expect(hub.pendingIncoming, 0);
      },
    );

    test('add errors show the server message', () async {
      server.addStatus = 429;
      await boot();
      await hub.addFriend(
        SearchResult(id: 'u1', name: 'A', username: 'a', isFriend: false),
      );
      expect(hub.searchError, 'Không thêm được');
      expect(hub.addNotice, '');
    });

    test(
      'accept: the friend appears with the returned row and the request goes',
      () async {
        server.incoming.add(_inReq('r1', 'u1', 'Bình', 'binh'));
        await boot();
        expect(await hub.acceptRequest(hub.incomingRequests.single), isNull);
        expect(hub.friends.map((f) => f.id), ['u1']);
        expect(hub.incomingRequests, isEmpty);
        expect(hub.pendingIncoming, 0);
        expect(server.log, contains('POST /me/friend-requests/r1/accept'));
      },
    );

    test(
      'accept of a request that is gone returns the server error and reloads',
      () async {
        server.incoming.add(_inReq('r1', 'u1', 'Bình', 'binh'));
        await boot();
        final r = hub.incomingRequests.single;
        server.incoming.clear();
        expect(await hub.acceptRequest(r), 'Lời mời không còn');
        await settle();
        expect(hub.incomingRequests, isEmpty);
        expect(hub.friends, isEmpty);
      },
    );

    test('decline and cancel call their endpoints and drop the row', () async {
      server.incoming.add(_inReq('r1', 'u1', 'Bình', 'binh'));
      server.outgoing.add(_outReq('r2', 'u2', 'Cúc', 'cuc'));
      await boot();
      expect(await hub.declineRequest(hub.incomingRequests.single), isNull);
      expect(await hub.cancelRequest(hub.outgoingRequests.single), isNull);
      expect(hub.incomingRequests, isEmpty);
      expect(hub.outgoingRequests, isEmpty);
      expect(
        server.log,
        containsAll([
          'POST /me/friend-requests/r1/decline',
          'DELETE /me/friend-requests/r2',
        ]),
      );
    });

    test('friend-request event in the foreground: banner, badge up at once, list refreshed', () async {
      await boot();
      server.incoming.add(_inReq('r7', 'u7', 'Giang', 'giang'));
      sock.push({
        'type': 'friend-request',
        'requestId': 'r7',
        'fromId': 'u7',
        'fromName': 'Giang',
      });
      await settle();
      expect(hub.banner!.body, 'Giang gửi lời mời kết bạn');
      expect(hub.banner!.route, '/friends');
      expect(
        hub.pendingIncoming,
        1,
      ); // not 2: the refreshed list replaces the optimistic bump
      expect(hub.incomingRequests.single.name, 'Giang');
      expect(notifier.shown, isEmpty);
    });

    test('friend-request event in the background: an OS notification that opens the friends screen', () async {
      await boot();
      hub.setForeground(false);
      sock.push({
        'type': 'friend-request',
        'requestId': 'r7',
        'fromId': 'u7',
        'fromName': 'Giang',
      });
      await settle();
      expect(hub.banner, isNull);
      expect(notifier.shown.single.body, 'Giang muốn kết bạn với bạn');
      expect(
        routeForTarget(parseNoticePayload(notifier.shown.single.payload)!),
        '/friends',
      );
    });

    test(
      'friend-accepted event: toast and the friend list is reloaded',
      () async {
        server.outgoing.add(_outReq('r2', 'u2', 'Cúc', 'cuc'));
        await boot();
        expect(hub.friends, isEmpty);
        server.outgoing.clear();
        server.friends.add(_row('u2', 'Cúc', 'cuc'));
        sock.push({'type': 'friend-accepted', 'friendId': 'u2', 'name': 'Cúc'});
        await settle();
        expect(hub.banner!.body, 'Cúc đã chấp nhận lời mời');
        expect(hub.friends.map((f) => f.id), ['u2']);
        expect(hub.outgoingRequests, isEmpty);
      },
    );

    test('friend-accepted in the background raises a notification', () async {
      await boot();
      hub.setForeground(false);
      sock.push({'type': 'friend-accepted', 'friendId': 'u2', 'name': 'Cúc'});
      await settle();
      expect(notifier.shown.single.body, 'Cúc đã chấp nhận lời mời');
    });
  });

  group('screen', () {
    tearDown(() => hub.dispose());

    Widget host() => MaterialApp(
      home: MessagingScope(hub: hub, child: const FriendsScreen()),
    );

    Future<void> open(WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(360, 740));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.runAsync(boot);
      await t.pumpWidget(host());
      await t.pumpAndSettle();
      if (find.text('Để sau').evaluate().isNotEmpty) {
        await t.tap(find.text('Để sau'));
      }
      await t.runAsync(settle);
      await t.pumpAndSettle();
    }

    testWidgets('block hidden when there are no requests', (t) async {
      await open(t);
      expect(find.byKey(const Key('requests-block')), findsNothing);
      expect(find.text('Lời mời kết bạn'), findsNothing);
    });

    testWidgets(
      'block shows incoming and outgoing rows at 360dp without overflow',
      (t) async {
        server.incoming.add(
          _inReq(
            'r1',
            'u1',
            'Nguyễn Văn Bình Rất Dài Tên Để Thử Tràn',
            'binh_username_dai',
          ),
        );
        server.outgoing.add(_outReq('r2', 'u2', 'Cúc', 'cuc'));
        await open(t);
        expect(find.text('Lời mời kết bạn'), findsOneWidget);
        expect(find.text('Chấp nhận'), findsOneWidget);
        expect(find.text('Từ chối'), findsOneWidget);
        expect(find.text('Đã gửi lời mời, chờ chấp nhận'), findsOneWidget);
        expect(find.text('Huỷ lời mời'), findsOneWidget);
        expect(find.text('@cuc'), findsOneWidget);
        expect(find.text('1'), findsOneWidget); // red count on the block
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'Chấp nhận moves the person into the list and hides the block',
      (t) async {
        server.incoming.add(_inReq('r1', 'u1', 'Bình', 'binh'));
        await open(t);
        await t.tap(find.text('Chấp nhận'));
        await t.runAsync(settle);
        await t.pumpAndSettle();
        expect(find.byKey(const Key('requests-block')), findsNothing);
        expect(find.text('Bình'), findsOneWidget); // now a conversation row
        expect(hub.friends.single.id, 'u1');
      },
    );

    testWidgets('Từ chối and Huỷ lời mời remove their rows', (t) async {
      server.incoming.add(_inReq('r1', 'u1', 'Bình', 'binh'));
      server.outgoing.add(_outReq('r2', 'u2', 'Cúc', 'cuc'));
      await open(t);
      await t.tap(find.text('Từ chối'));
      await t.runAsync(settle);
      await t.pumpAndSettle();
      expect(find.text('Chấp nhận'), findsNothing);
      expect(find.text('Huỷ lời mời'), findsOneWidget);
      await t.tap(find.text('Huỷ lời mời'));
      await t.runAsync(settle);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('requests-block')), findsNothing);
    });

    testWidgets(
      'search rows follow requestState and sending shows the notice',
      (t) async {
        server.searchResults = [
          {
            'id': 'u5',
            'name': 'Dũng',
            'username': 'dung',
            'isFriend': false,
            'requestState': 'none',
          },
          {
            'id': 'u6',
            'name': 'Hà',
            'username': 'ha',
            'isFriend': false,
            'requestState': 'outgoing',
          },
          {
            'id': 'u7',
            'name': 'Khoa',
            'username': 'khoa',
            'isFriend': false,
            'requestState': 'incoming',
          },
        ];
        server.addAnswer = {
          'status': 'pending',
          'request': _outReq('r5', 'u5', 'Dũng', 'dung'),
        };
        await open(t);
        hub.setSearch('d');
        await t.pump(const Duration(milliseconds: 400));
        await t.runAsync(settle);
        await t.pumpAndSettle();
        expect(find.text('Kết bạn'), findsOneWidget);
        expect(find.text('Đã gửi lời mời'), findsOneWidget);
        expect(find.text('Chấp nhận'), findsOneWidget);
        expect(
          t
              .widget<TextButton>(
                find
                    .ancestor(
                      of: find.text('Đã gửi lời mời'),
                      matching: find.byType(TextButton),
                    )
                    .first,
              )
              .onPressed,
          isNull,
        );
        await t.tap(find.text('Kết bạn'));
        await t.runAsync(settle);
        await t.pumpAndSettle();
        expect(
          find.text('Đã gửi lời mời kết bạn tới Dũng. Họ cần chấp nhận.'),
          findsOneWidget,
        );
        expect(hub.friends, isEmpty);
        expect(find.text('Đã gửi lời mời'), findsNWidgets(2));
        expect(t.takeException(), isNull);
      },
    );
  });
}
