import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/account/privacy/privacy_gate.dart';
import 'package:mamba_app/features/account/privacy/privacy_store.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemAuth extends AuthStore {
  _MemAuth() {
    token = 'T';
    role = 'user';
    ready = true;
  }
}

http.Response _json(Object o, int s) => http.Response.bytes(utf8.encode(jsonEncode(o)), s, headers: {'content-type': 'application/json; charset=utf-8'});

/// The server of the lock screen: 5 free tries, the 5th wrong one locks for [lockSeconds].
class _Server {
  int failed = 0;
  int lockSeconds = 30;
  bool locked = false;
  final tries = <String>[];

  Future<http.Response> handle(http.Request r) async {
    if (r.url.path.endsWith('/me/policy')) return _json({'autoLockMinutes': 1}, 200);
    if (r.url.path.endsWith('/me/verify-password')) {
      final pw = (jsonDecode(r.body) as Map)['password'];
      tries.add('$pw');
      if (locked) return _json({'error': 'Quá nhiều lần thử không thành công. Vui lòng thử lại sau $lockSeconds giây.', 'retryAfterSeconds': lockSeconds}, 429);
      if (pw == 'dung') return _json({'ok': true}, 200);
      failed++;
      if (failed >= 5) {
        locked = true;
        return _json({'error': 'Quá nhiều lần thử không thành công. Vui lòng thử lại sau $lockSeconds giây.', 'retryAfterSeconds': lockSeconds}, 429);
      }
      return _json({'error': 'Mật khẩu không đúng', 'failedAttempts': failed, 'maxAttempts': 5, 'attemptsLeft': 5 - failed}, 403);
    }
    return _json({}, 404);
  }
}

void main() {
  late _Server server;
  late PrivacyStore privacy;

  Future<void> pumpLocked(WidgetTester t) async {
    SharedPreferences.setMockInitialValues({});
    server = _Server();
    final auth = _MemAuth();
    final api = ApiClient(auth, client: MockClient(server.handle));
    privacy = PrivacyStore();
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthStore>.value(value: auth),
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider<PrivacyStore>.value(value: privacy),
      ],
      child: MaterialApp(builder: (c, ch) => PrivacyGate(child: ch!), home: const Scaffold(body: Text('NOI DUNG'))),
    ));
    await t.pumpAndSettle();
    privacy.lock();
    await t.pumpAndSettle();
    expect(find.text('Ứng dụng đã khoá'), findsOneWidget);
  }

  Future<void> wrong(WidgetTester t) async {
    await t.enterText(find.byType(TextField), 'sai');
    await t.tap(find.text('Mở khoá'));
    await t.pumpAndSettle();
  }

  testWidgets('a wrong password says how many tries were wrong, the maximum, and how many are left before the lock', (t) async {
    await pumpLocked(t);
    await wrong(t);
    expect(find.textContaining('Mật khẩu không đúng. Đã sai 1/5 lần. Còn 4 lần thử trước khi bị khoá tạm.'), findsOneWidget);
    await wrong(t);
    expect(find.textContaining('Đã sai 2/5 lần. Còn 3 lần thử'), findsOneWidget);
    await wrong(t);
    await wrong(t);
    expect(find.textContaining('Đã sai 4/5 lần. Còn 1 lần thử'), findsOneWidget);
    expect(find.text('Mở khoá'), findsOneWidget); // still possible: the 5th try may be the right one
  });

  testWidgets('the lock counts down live, disables the field and the button, and gives the screen back at zero', (t) async {
    await pumpLocked(t);
    for (var i = 0; i < 5; i++) {
      await wrong(t);
    }
    expect(find.byKey(const ValueKey('lock-countdown')), findsOneWidget);
    expect(find.textContaining('thử lại sau 30 giây'), findsWidgets);
    expect(find.text('Mở khoá'), findsNothing);
    expect(find.text('Thử lại sau 30 giây'), findsOneWidget); // the button says it too
    expect(t.widget<TextField>(find.byType(TextField)).enabled, isFalse);

    await t.pump(const Duration(seconds: 1));
    expect(find.textContaining('thử lại sau 29 giây'), findsWidgets);
    await t.pump(const Duration(seconds: 10));
    expect(find.textContaining('thử lại sau 19 giây'), findsWidgets);
    // pressing during the lock sends nothing
    final sent = server.tries.length;
    await t.tap(find.text('Thử lại sau 19 giây'), warnIfMissed: false);
    await t.pump();
    expect(server.tries.length, sent);

    await t.pump(const Duration(seconds: 19));
    expect(find.byKey(const ValueKey('lock-countdown')), findsNothing);
    expect(find.text('Mở khoá'), findsOneWidget);
    expect(t.widget<TextField>(find.byType(TextField)).enabled, isTrue);
  });

  testWidgets('a minute or more reads as minutes and seconds', (t) async {
    await pumpLocked(t);
    server.lockSeconds = 125;
    for (var i = 0; i < 5; i++) {
      await wrong(t);
    }
    expect(find.textContaining('2 phút 05 giây'), findsWidgets);
    await t.pump(const Duration(seconds: 6));
    expect(find.textContaining('1 phút 59 giây'), findsWidgets);
  });

  testWidgets('after the lock the right password opens the screen', (t) async {
    await pumpLocked(t);
    for (var i = 0; i < 5; i++) {
      await wrong(t);
    }
    server.locked = false; // the server's lock ended too
    await t.pump(const Duration(seconds: 31));
    await t.enterText(find.byType(TextField), 'dung');
    await t.tap(find.text('Mở khoá'));
    await t.pumpAndSettle();
    expect(find.text('Ứng dụng đã khoá'), findsNothing);
    expect(privacy.locked, isFalse);
  });

  test('the wait is written in seconds, then minutes', () {
    expect(formatLockWait(1), '1 giây');
    expect(formatLockWait(59), '59 giây');
    expect(formatLockWait(60), '1 phút');
    expect(formatLockWait(61), '1 phút 01 giây');
    expect(formatLockWait(900), '15 phút');
  });
}
