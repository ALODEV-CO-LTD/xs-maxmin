import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/account/privacy/privacy_store.dart';
import 'package:mamba_app/features/friends/call_service.dart';
import 'package:mamba_app/features/friends/friends_controller.dart';
import 'package:mamba_app/features/friends/messaging_host.dart';
import 'package:mamba_app/features/friends/realtime_socket.dart';
import 'package:mamba_app/features/shell/app_shell.dart';
import 'package:go_router/go_router.dart';

class _Auth extends AuthStore {
  _Auth() {
    ready = true;
  }

  // No secure-storage platform channel in widget tests (awaiting it would never complete under fake async).
  void signIn(String r) {
    token = 'tok';
    role = r;
    notifyListeners();
  }

  void signOut() {
    token = null;
    role = null;
    notifyListeners();
  }
}

class _Sink implements FrameSink {
  @override
  bool ready = true;
  @override
  void send(Map<String, dynamic> frame) {}
}

/// A hub that records its life cycle and never touches the network.
class SpyHub extends FriendsController {
  SpyHub(ApiClient api, AuthStore auth) : super(api: api, auth: auth);
  int started = 0;
  int disposed = 0;
  @override
  Future<void> start() async {
    started++;
    call = CallService(api: api, socket: _Sink(), canCall: true);
    loading = false;
  }

  @override
  void dispose() {
    disposed++;
    super.dispose();
  }
}

ApiClient _api(AuthStore a) => ApiClient(a, client: MockClient((_) async => http.Response('{}', 404)));

void main() {
  testWidgets('hub is created once on customer login and disposed (and wiped) on logout', (tester) async {
    final auth = _Auth();
    final api = _api(auth);
    final privacy = PrivacyStore();
    final hubs = <SpyHub>[];
    FriendsController? seen;
    await tester.pumpWidget(MaterialApp(
      home: MessagingHost(
        auth: auth,
        api: api,
        privacy: privacy,
        factory: (a, b) => _track(hubs, SpyHub(a, b)),
        child: Builder(builder: (context) {
          seen = MessagingScope.maybeOf(context);
          return const Scaffold(body: Text('APP'));
        }),
      ),
    ));
    expect(hubs, isEmpty);
    expect(seen, isNull);
    expect(privacy.isBusy, isNull);

    auth.signIn('user');
    await tester.pump();
    expect(hubs, hasLength(1));
    expect(hubs.single.started, 1);
    expect(seen, same(hubs.single));
    expect(privacy.isBusy, isNotNull); // calls are never auto-locked
    expect(privacy.isBusy!(), isFalse);

    // Token refresh style notifications must not create a second hub.
    auth.signOut();
    await tester.pump();
    expect(hubs.single.disposed, 1);
    expect(seen, isNull);
    expect(privacy.isBusy, isNull);

    auth.signIn('user');
    await tester.pump();
    expect(hubs, hasLength(2)); // a fresh account session gets a fresh hub
    expect(hubs.last.started, 1);

    // The widget going away disposes it too.
    await tester.pumpWidget(const SizedBox());
    expect(hubs.last.disposed, 1);
  });

  testWidgets('admin accounts never get a hub (calls and friend chat are customer-to-customer)', (tester) async {
    final auth = _Auth();
    final hubs = <SpyHub>[];
    await tester.pumpWidget(MaterialApp(
      home: MessagingHost(auth: auth, api: _api(auth), factory: (a, b) => _track(hubs, SpyHub(a, b)), child: const Scaffold(body: Text('APP'))),
    ));
    auth.signIn('admin');
    await tester.pump();
    expect(hubs, isEmpty);
  });

  testWidgets('incoming call appears above whatever screen is showing, and goes away when declined', (tester) async {
    final auth = _Auth();
    late SpyHub hub;
    await tester.pumpWidget(MaterialApp(
      home: MessagingHost(auth: auth, api: _api(auth), factory: (a, b) => hub = SpyHub(a, b), child: const Scaffold(body: Text('MÀN HÌNH BẤT KỲ'))),
    ));
    auth.signIn('user');
    await tester.pump();
    await tester.pump();
    expect(find.text('Nghe máy'), findsNothing);

    hub.call!.onFrame({'type': 'call-invite', 'from': 'u2', 'fromName': 'Bình'});
    await tester.pump();
    expect(find.text('Bình'), findsOneWidget);
    expect(find.text('Nghe máy'), findsOneWidget);
    expect(find.text('Từ chối'), findsOneWidget);
    expect(hub.callBusy, isTrue);

    await tester.tap(find.byIcon(Icons.call_end));
    await tester.pump();
    expect(find.text('Nghe máy'), findsNothing);
    expect(hub.call!.lastEnd!.outcome, CallOutcome.rejected);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('in-app banner is shown for a new message and not while the app is locked', (tester) async {
    final auth = _Auth();
    final privacy = PrivacyStore();
    late SpyHub hub;
    await tester.pumpWidget(MaterialApp(
      home: MessagingHost(auth: auth, api: _api(auth), privacy: privacy, factory: (a, b) => hub = SpyHub(a, b), child: const Scaffold(body: Text('APP'))),
    ));
    auth.signIn('user');
    await tester.pump();
    hub.showBanner(const AppBanner(title: 'Bình', body: 'xin chào', friendId: 'u2', route: '/friends/chat/u2'));
    await tester.pump();
    expect(find.text('xin chào'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    expect(find.text('xin chào'), findsNothing);

    privacy.locked = true;
    hub.showBanner(const AppBanner(title: 'Bình', body: 'riêng tư', friendId: 'u2'));
    await tester.pump();
    expect(find.text('riêng tư'), findsNothing); // nothing leaks over the lock screen
  });

  testWidgets('the Bạn bè tab of the bottom bar shows the number of chats that need a look', (tester) async {
    final auth = _Auth();
    late SpyHub hub;
    final router = GoRouter(
      initialLocation: '/overview',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => AppShell(shell: shell),
          branches: [
            for (final p in ['/overview', '/calc', '/friends', '/config', '/account']) StatefulShellBranch(routes: [GoRoute(path: p, builder: (_, _) => Text(p))]),
          ],
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => Overlay(initialEntries: [OverlayEntry(builder: (_) => MessagingHost(auth: auth, api: _api(auth), factory: (a, b) => hub = SpyHub(a, b), child: child!))]),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(Badge), findsNothing);
    auth.signIn('user');
    await tester.pump();
    hub.supportUnread = 2;
    hub.unseenMissed = {'u2': 1};
    hub.showBanner(const AppBanner(title: 'x', body: 'y')); // any notification of the hub rebuilds the listeners
    await tester.pump();
    expect(find.widgetWithText(Badge, '2'), findsOneWidget); // 1 chat with a missed call + the Admin reply
    await tester.pump(const Duration(seconds: 7));
  });
}

SpyHub _track(List<SpyHub> l, SpyHub h) {
  l.add(h);
  return h;
}
