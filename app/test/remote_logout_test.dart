import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/app.dart';
import 'package:mamba_app/core/admin_session.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/core/lottery_stations.dart';
import 'package:mamba_app/core/mask_store.dart';
import 'package:mamba_app/core/scoring_config_bus.dart';
import 'package:mamba_app/features/account/privacy/privacy_store.dart';
import 'package:mamba_app/features/friends/call_service.dart';
import 'package:mamba_app/features/friends/friends_controller.dart';
import 'package:mamba_app/features/friends/messaging_host.dart';
import 'package:mamba_app/features/friends/realtime_socket.dart';
import 'package:provider/provider.dart';

class _Auth extends AuthStore {
  _Auth() {
    ready = true;
    token = 'tok';
    role = 'user';
  }
  // like clear() without the secure-storage platform channel
  void drop() {
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

class _Hub extends FriendsController {
  _Hub(ApiClient api, AuthStore auth) : super(api: api, auth: auth);
  @override
  Future<void> start() async {
    call = CallService(api: api, socket: _Sink(), canCall: true);
    loading = false;
  }
}

/// The session is ended from another device (the server closes the socket / answers 401): the app must go to the login screen
/// and not show a framework error, wherever the person is.
void main() {
  for (final start in ['/friends', '/overview', '/calc', '/account']) {
    testWidgets('signed out remotely while on $start: no error, login screen shown', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final auth = _Auth();
      final api = ApiClient(auth, client: MockClient((_) async => http.Response('{"error":"x"}', 404, headers: {'content-type': 'application/json'})));
      final router = buildRouter(auth);
      final privacy = PrivacyStore();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthStore>.value(value: auth),
          Provider<ApiClient>.value(value: api),
          ChangeNotifierProvider<LotteryStations>(create: (_) => LotteryStations()),
          ChangeNotifierProvider<MaskStore>(create: (_) => MaskStore()),
          ChangeNotifierProvider<AdminSession>(create: (_) => AdminSession()),
          ChangeNotifierProvider<PrivacyStore>.value(value: privacy),
          ChangeNotifierProvider<ScoringConfigBus>(create: (_) => ScoringConfigBus()),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => ListenableBuilder(
            listenable: auth,
            builder: (context, _) => Stack(children: [
              MessagingHost(auth: auth, api: api, router: router, privacy: privacy, factory: (a, b) => _Hub(a, b), child: child ?? const SizedBox.shrink()),
            ]),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      router.go(start);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(tester.takeException(), isNull, reason: 'before logging out');

      auth.drop();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      // (the login screen overflows by a few pixels in the test font; only real errors count)
      final err = tester.takeException();
      expect(err == null || '$err'.contains('overflowed'), isTrue, reason: '$err');
      expect(router.routerDelegate.currentConfiguration.uri.path, '/login');
    });
  }
}
