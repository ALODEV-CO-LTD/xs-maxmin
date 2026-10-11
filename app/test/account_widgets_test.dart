import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/account/privacy/privacy_gate.dart';
import 'package:mamba_app/features/account/privacy/privacy_store.dart';
import 'package:mamba_app/features/auth/register_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemAuth extends AuthStore {
  _MemAuth() {
    token = 'T';
    role = 'user';
    ready = true;
  }
}

Widget _host(Widget child, AuthStore auth, PrivacyStore privacy, ApiClient api) => MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthStore>.value(value: auth),
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider<PrivacyStore>.value(value: privacy),
      ],
      child: MaterialApp(builder: (c, ch) => PrivacyGate(child: ch!), home: child),
    );

void main() {
  testWidgets('lock overlay covers the app, wrong password shows the server message, right one unlocks', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final auth = _MemAuth();
    final api = ApiClient(auth, client: MockClient((req) async {
      if (req.url.path.endsWith('/me/policy')) return http.Response('{"autoLockMinutes":1}', 200);
      return req.body.contains('good') ? http.Response('{"ok":true}', 200) : http.Response('{"error":"Mật khẩu không đúng"}', 403, headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    final privacy = PrivacyStore();
    await tester.pumpWidget(_host(const Scaffold(body: Text('NOI DUNG')), auth, privacy, api));
    await tester.pumpAndSettle();
    expect(privacy.ready, isTrue);
    expect(find.text('Ứng dụng đã khoá'), findsNothing);
    privacy.lock();
    await tester.pumpAndSettle();
    expect(find.text('Ứng dụng đã khoá'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'bad');
    await tester.tap(find.text('Mở khoá'));
    await tester.pumpAndSettle();
    expect(find.text('Mật khẩu không đúng'), findsOneWidget);
    expect(privacy.locked, isTrue);
    await tester.enterText(find.byType(TextField), 'good');
    await tester.tap(find.text('Mở khoá'));
    await tester.pumpAndSettle();
    expect(find.text('Ứng dụng đã khoá'), findsNothing);
    expect(privacy.locked, isFalse);
    // sign out: the gate stops the store
    auth.clear();
    await tester.pumpAndSettle();
    expect(privacy.ready, isFalse);
  });

  testWidgets('register screen: step 1 validation, then step 2', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final auth = _MemAuth()..token = null;
    final api = ApiClient(auth, client: MockClient((req) async => http.Response('{"error":"x"}', 400)));
    await tester.pumpWidget(_host(const RegisterScreen(), auth, PrivacyStore(), api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();
    expect(find.text('Vui lòng nhập tên hiển thị'), findsOneWidget);
    expect(find.text('Tên đăng nhập phải có ít nhất 3 ký tự'), findsOneWidget);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'An');
    await tester.enterText(fields.at(1), 'an123');
    await tester.enterText(fields.at(2), 'pw');
    await tester.enterText(fields.at(3), 'pw');
    await tester.pump();
    await tester.tap(find.text('Tiếp tục'));
    await tester.pumpAndSettle();
    expect(find.text('Bảo vệ tài khoản'), findsOneWidget);
    expect(find.text('Tạo tài khoản'), findsOneWidget);
  });
}
