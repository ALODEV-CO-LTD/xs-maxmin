import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/friends/fcm_push_port.dart';
import 'package:mamba_app/features/friends/push_registrar.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends AuthStore {
  _Auth() {
    ready = true;
  }
  void signIn(String r) {
    token = 'tok';
    role = r;
    notifyListeners();
  }

  @override
  void clear() {
    token = null;
    role = null;
    notifyListeners();
  }
}

class _Fcm implements FcmClient {
  _Fcm({this.configured = true, this.token, this.initialData, this.permitted = false});
  final bool configured;
  String? token;
  Map<String, dynamic>? initialData;
  bool permitted;
  int permissionAsked = 0;
  final refresh = StreamController<String>.broadcast();
  final opened = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Future<void> initialize() async {
    if (!configured) throw StateError('[core/no-app] missing google-services.json');
  }

  @override
  Future<String?> getToken() async => token;
  @override
  Stream<String> get onTokenRefresh => refresh.stream;
  @override
  Future<Map<String, dynamic>?> initialMessageData() async => initialData;
  @override
  Stream<Map<String, dynamic>> get onOpenedData => opened.stream;
  @override
  Future<bool> requestPermission() async {
    permissionAsked++;
    return true;
  }

  @override
  Future<bool> isPermitted() async => permitted;
}

final _t1 = 'Ab1_-:' * 25;
final _t2 = 'Zy9:_-' * 25;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Auth auth;
  late List<http.Request> calls;
  late List<String> routes;
  late _Fcm fcm;
  late PushRegistrar reg;
  var explained = 0;
  var explainAnswer = true;

  Future<PushRegistrar> make(_Fcm f, {bool ios = false, bool android = true}) async {
    fcm = f;
    final api = ApiClient(auth, client: MockClient((r) async {
      calls.add(r);
      return http.Response('{"ok":true}', 200);
    }));
    reg = PushRegistrar(
      auth: auth,
      api: api,
      openRoute: routes.add,
      port: FcmPushPort(f),
      isIos: ios,
      isAndroid: android,
      openDelay: Duration.zero,
      explain: () async {
        explained++;
        return explainAnswer;
      },
    );
    await reg.start();
    return reg;
  }

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    auth = _Auth();
    calls = [];
    routes = [];
    explained = 0;
    explainAnswer = true;
  });

  test('registers as android after a customer signs in; asks permission once after explaining', () async {
    await make(_Fcm(token: _t1));
    await settle();
    expect(calls, isEmpty); // signed out
    auth.signIn('user');
    await settle();
    expect(calls, hasLength(1));
    expect(calls.single.method, 'POST');
    expect(calls.single.url.path, endsWith('/me/push-token'));
    expect(jsonDecode(calls.single.body), {'platform': 'android', 'token': _t1, 'deviceLabel': 'Android'});
    expect(fcm.permissionAsked, 1);
    expect(explained, 1);
    reg.dispose();
  });

  test('already permitted (or Android < 13): no explanation dialog', () async {
    await make(_Fcm(token: _t1, permitted: true));
    auth.signIn('user');
    await settle();
    expect(explained, 0);
    expect(fcm.permissionAsked, 0);
    expect(calls, hasLength(1));
    reg.dispose();
  });

  test('admin never registers', () async {
    await make(_Fcm(token: _t1));
    auth.signIn('admin');
    await settle();
    expect(calls, isEmpty);
    expect(fcm.permissionAsked, 0);
    reg.dispose();
  });

  test('token refresh re-registers; the same token does not', () async {
    await make(_Fcm(token: _t1));
    auth.signIn('user');
    await settle();
    fcm.refresh.add(_t1);
    await settle();
    expect(calls, hasLength(1));
    fcm.refresh.add(_t2);
    await settle();
    expect(calls, hasLength(2));
    expect(jsonDecode(calls.last.body)['token'], _t2);
    reg.dispose();
  });

  test('a token that arrives late (after sign-in) is registered', () async {
    final f = _Fcm();
    await make(f);
    auth.signIn('user');
    await settle();
    expect(calls, isEmpty);
    f.refresh.add(_t1);
    await settle();
    expect(calls, hasLength(1));
    reg.dispose();
  });

  test('explicit logout deletes the token before the session is cleared', () async {
    await make(_Fcm(token: _t1));
    auth.signIn('user');
    await settle();
    await auth.logout();
    expect(calls.last.method, 'DELETE');
    expect(calls.last.headers['authorization'], 'Bearer tok');
    expect(jsonDecode(calls.last.body), {'token': _t1});
    reg.dispose();
  });

  test('Firebase not configured: silent no-op (no calls, no permission, no dialog)', () async {
    await make(_Fcm(configured: false, token: _t1));
    expect(reg.active, false);
    auth.signIn('user');
    await settle();
    await auth.logout();
    expect(calls, isEmpty);
    expect(explained, 0);
    expect(fcm.permissionAsked, 0);
    reg.dispose();
  });

  test('tap while in background opens the chat; calls open the chat too', () async {
    await make(_Fcm(token: _t1));
    auth.signIn('user');
    await settle();
    fcm.opened.add({'friendId': 'f 1', 'kind': 'message'});
    await settle();
    fcm.opened.add({'friendId': 'f2', 'kind': 'call'});
    await settle();
    fcm.opened.add({'kind': 'message'}); // not ours
    await settle();
    expect(routes, ['/friends/chat/f%201', '/friends/chat/f2']);
    reg.dispose();
  });

  test('cold start from a notification: opens the chat once a customer is signed in', () async {
    await make(_Fcm(token: _t1, initialData: {'friendId': 'f9', 'kind': 'message'}));
    await settle();
    expect(routes, isEmpty);
    auth.signIn('user');
    await settle();
    expect(routes, ['/friends/chat/f9']);
    reg.dispose();
  });

  test('not Android and not iOS (or iOS flag): the FCM path stays off', () async {
    final f = _Fcm(token: _t1);
    await make(f, android: false);
    auth.signIn('user');
    await settle();
    expect(calls, isEmpty);
    expect(reg.active, false);
    reg.dispose();
  });

  test('openedFromData', () {
    expect(FcmPushPort.openedFromData({'friendId': 'a', 'kind': 'call'})!.kind, 'call');
    expect(FcmPushPort.openedFromData({'friendId': 'a'})!.kind, 'message');
    expect(FcmPushPort.openedFromData({'friendId': ''}), isNull);
    expect(FcmPushPort.openedFromData(null), isNull);
  });
}
