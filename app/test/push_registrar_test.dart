import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
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

  // No secure storage in tests: same as clear() without the platform calls.
  @override
  void clear() {
    token = null;
    role = null;
    notifyListeners();
  }
}

class _Port implements PushPort {
  _Port({this.initialValue = const PushInitial()});
  PushInitial initialValue;
  void Function(String)? onToken;
  void Function(PushOpened)? onOpened;
  bool Function(PushOpened)? presentation;
  int permissionAsked = 0;

  @override
  void listen({required onToken, required onError, required onOpened, required presentation}) {
    this.onToken = onToken;
    this.onOpened = onOpened;
    this.presentation = presentation;
  }

  @override
  Future<bool> requestPermission() async {
    permissionAsked++;
    return true;
  }

  @override
  Future<PushInitial> initial() async => initialValue;

  @override
  bool get available => true;

  @override
  Future<bool> isPermitted() async => false;
}

final _t1 = 'ab' * 32;
final _t2 = 'cd' * 32;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Auth auth;
  late List<http.Request> calls;
  late List<String> routes;
  late _Port port;
  late PushRegistrar reg;
  var explainAnswer = true;
  var explained = 0;

  Future<PushRegistrar> make({bool ios = true, PushInitial? initial}) async {
    port = _Port(initialValue: initial ?? const PushInitial());
    final api = ApiClient(auth, client: MockClient((r) async {
      calls.add(r);
      return http.Response('{"ok":true}', 200);
    }));
    reg = PushRegistrar(
      auth: auth,
      api: api,
      openRoute: routes.add,
      port: port,
      isIos: ios,
      openDelay: Duration.zero,
      explain: () async {
        explained++;
        return explainAnswer;
      },
    );
    await reg.start();
    return reg;
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    auth = _Auth();
    calls = [];
    routes = [];
    explainAnswer = true;
    explained = 0;
  });

  test('registers after a customer signs in, once the token is known', () async {
    await make();
    port.onToken!(_t1); // token arrives while signed out: nothing sent
    await settle();
    expect(calls, isEmpty);
    auth.signIn('user');
    await settle();
    expect(calls, hasLength(1));
    expect(calls.single.method, 'POST');
    expect(calls.single.url.path, endsWith('/me/push-token'));
    expect(jsonDecode(calls.single.body), {'platform': 'ios', 'token': _t1, 'deviceLabel': 'iPhone'});
    expect(calls.single.headers['authorization'], 'Bearer tok');
    expect(port.permissionAsked, 1);
    expect(explained, 1);
    reg.dispose();
  });

  test('token known at start (from native) is registered at login; admin never registers', () async {
    await make(initial: PushInitial(token: _t1));
    auth.signIn('admin');
    await settle();
    expect(calls, isEmpty);
    expect(port.permissionAsked, 0);
    reg.dispose();
  });

  test('re-registers when the token changes, not for the same token', () async {
    await make(initial: PushInitial(token: _t1));
    auth.signIn('user');
    await settle();
    port.onToken!(_t1);
    await settle();
    expect(calls, hasLength(1));
    port.onToken!(_t2);
    await settle();
    expect(calls, hasLength(2));
    expect(jsonDecode(calls.last.body)['token'], _t2);
    reg.dispose();
  });

  test('explicit logout deletes the token BEFORE the session is cleared', () async {
    await make(initial: PushInitial(token: _t1));
    auth.signIn('user');
    await settle();
    await auth.logout();
    final del = calls.last;
    expect(del.method, 'DELETE');
    expect(jsonDecode(del.body), {'token': _t1});
    expect(del.headers['authorization'], 'Bearer tok'); // still authenticated
    expect(auth.signedIn, false);
    reg.dispose();
  });

  test('permission is asked once; "Để sau" asks again next sign-in', () async {
    explainAnswer = false;
    await make();
    auth.signIn('user');
    await settle();
    expect(port.permissionAsked, 0);
    auth.clear();
    explainAnswer = true;
    auth.signIn('user');
    await settle();
    expect(port.permissionAsked, 1);
    auth.clear();
    auth.signIn('user');
    await settle();
    expect(port.permissionAsked, 1);
    reg.dispose();
  });

  test('no-op when not iOS', () async {
    await make(ios: false, initial: PushInitial(token: _t1));
    auth.signIn('user');
    await settle();
    expect(calls, isEmpty);
    expect(port.onToken, isNull);
    expect(auth.beforeLogout, isEmpty);
    await auth.logout();
    expect(calls, isEmpty);
  });

  test('tap routes to the chat (calls too), also after a cold start before login', () async {
    await make();
    auth.signIn('user');
    await settle();
    port.onOpened!(const PushOpened('friend 1', 'message'));
    await settle();
    port.onOpened!(const PushOpened('f2', 'call'));
    await settle();
    expect(routes, ['/friends/chat/friend%201', '/friends/chat/f2']);
    reg.dispose();

    routes.clear();
    auth.clear();
    await make(initial: const PushInitial(opened: PushOpened('f3', 'message')));
    await settle();
    expect(routes, isEmpty); // signed out: wait
    auth.signIn('user');
    await settle();
    await settle();
    expect(routes, ['/friends/chat/f3']);
    reg.dispose();
  });

  test('foreground: banner shown when no hub is available', () async {
    await make();
    expect(port.presentation!(const PushOpened('f', 'message')), true);
    reg.dispose();
  });

  test('channel port parses native calls', () async {
    const ch = MethodChannel('vn.mamba/push-test');
    final p = ChannelPushPort(ch);
    String? token;
    PushOpened? opened;
    p.listen(onToken: (t) => token = t, onError: (_) {}, onOpened: (o) => opened = o, presentation: (_) => false);
    Future<dynamic> send(String m, Object? a) async {
      final data = ch.codec.encodeMethodCall(MethodCall(m, a));
      final out = Completer0();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage('vn.mamba/push-test', data, (r) => out.value = r);
      await settle();
      return out.value == null ? null : ch.codec.decodeEnvelope(out.value!);
    }

    await send('token', _t1);
    expect(token, _t1);
    await send('opened', {'friendId': 'x', 'kind': 'call'});
    expect(opened!.friendId, 'x');
    expect(opened!.kind, 'call');
    expect(await send('presentation', {'friendId': 'x', 'kind': 'message'}), false);
  });
}

class Completer0 {
  ByteData? value;
}
