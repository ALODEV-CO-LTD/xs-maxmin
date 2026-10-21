import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/core/package_events.dart';
import 'package:mamba_app/features/account/account_controller.dart';
import 'package:mamba_app/features/account/account_packages_tab.dart';
import 'package:mamba_app/features/friends/notifications.dart';
import 'package:provider/provider.dart';

class _Auth extends AuthStore {
  _Auth() {
    token = 'T';
    role = 'user';
    ready = true;
  }
}

http.Response _j(Object o) => http.Response(jsonEncode(o), 200, headers: {'content-type': 'application/json; charset=utf-8'});

class _Server {
  String packageType = 'month';
  bool active = true;
  final List<Map<String, dynamic>> requests = [];
  int meCalls = 0;
  int purchases = 0;
  String? keepReference; // set: the server answers with this reference whatever the app sent

  Future<http.Response> handle(http.Request r) async {
    final p = r.url.path;
    if (p.endsWith('/me/packages/purchase')) {
      purchases++;
      final body = jsonDecode(r.body) as Map;
      final type = body['packageType'];
      requests.insert(0, {'id': 'r1', 'packageType': type, 'amount': type == 'quarter' ? 269000 : 99000, 'status': 'pending', 'referenceCode': keepReference ?? body['referenceCode'], 'createdAt': '2026-10-20T09:00:00.000Z'});
      return _j(requests.first); // flat, like the real route
    }
    if (p.endsWith('/me/packages')) {
      return _j({
        'packages': [
          {'type': 'month', 'label': '1 tháng', 'priceVnd': 99000, 'durationDays': 30},
          {'type': 'quarter', 'label': '3 tháng', 'priceVnd': 269000, 'durationDays': 90},
        ],
      });
    }
    if (p.endsWith('/me/payment-info')) return _j({'bankName': 'ACB', 'bankBin': '970416', 'bankAccountNumber': '123456789', 'bankAccountHolder': 'CTY MAMBA'});
    if (p.endsWith('/me/payment-requests')) return _j({'requests': requests});
    if (p.endsWith('/api/me') || p.endsWith('/me')) {
      meCalls++;
      return _j({
        'name': 'A',
        'username': 'a',
        'role': 'user',
        'package': {'type': packageType, 'label': packageType == 'month' ? '1 tháng' : '3 tháng', 'expiresAt': '2026-11-20T00:00:00.000Z', 'isActive': active},
        'stats': {'total': 10, 'used': 1},
      });
    }
    return http.Response('{}', 404);
  }
}

void main() {
  late _Server server;
  late AccountController ctl;
  late ApiClient api;

  Future<void> pumpTab(WidgetTester t) async {
    t.view.physicalSize = const Size(400 * 3, 1400 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    server = _Server();
    final auth = _Auth();
    api = ApiClient(auth, client: MockClient(server.handle));
    ctl = AccountController(api);
    await ctl.load();
    await t.pumpWidget(MultiProvider(
      providers: [Provider<ApiClient>.value(value: api)],
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: AccountPackagesTab(ctl: ctl)))),
    ));
    await t.pump(const Duration(milliseconds: 200));
  }

  testWidgets('the package in use says "Gia hạn", every other one says "Đăng ký"', (t) async {
    await pumpTab(t);
    expect(find.text('Gia hạn'), findsOneWidget);
    expect(find.text('Đăng ký'), findsOneWidget);
    expect(find.text('Đang dùng'), findsOneWidget);
  });

  testWidgets('"Đăng ký" shows the transfer QR first and sends NOTHING to Admin yet', (t) async {
    await pumpTab(t);
    await t.tap(find.text('Đăng ký'));
    await t.pumpAndSettle();
    expect(server.purchases, 0);
    expect(find.text('Chuyển khoản để kích hoạt gói'), findsOneWidget);
    final sheet = find.byType(BottomSheet);
    expect(find.descendant(of: sheet, matching: find.text('123456789')), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('CTY MAMBA')), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('269.000đ')), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.byType(Image)), findsOneWidget); // the QR (it cannot load in a test: no network)
    // the content is already there and is a well-formed reference
    final refs = t.widgetList<SelectableText>(find.descendant(of: sheet, matching: find.byType(SelectableText))).map((x) => x.data ?? '').where((x) => RegExp(r'^XS[A-HJ-NP-Z2-9]{6}$').hasMatch(x));
    expect(refs.length, 1);
    // the sheet ends with the two choices
    expect(find.descendant(of: sheet, matching: find.text('Đã chuyển khoản')), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('Huỷ')), findsOneWidget);
    expect(find.text('Đã hiểu'), findsNothing);
  });

  testWidgets('the tab itself shows no bank details or QR; they open in the sheet', (t) async {
    await pumpTab(t);
    expect(find.text('Thông tin chuyển khoản'), findsNothing);
    expect(find.text('123456789'), findsNothing);
    expect(find.byType(Image), findsNothing);
    // with a request waiting it is still only the button that shows them
    await t.tap(find.text('Đăng ký'));
    await t.pumpAndSettle();
    await t.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Đã chuyển khoản')));
    await t.pumpAndSettle();
    expect(find.text('123456789'), findsNothing);
    expect(find.byType(Image), findsNothing);
    await t.tap(find.text('Xem thông tin chuyển khoản và mã QR'));
    await t.pumpAndSettle();
    expect(find.text('123456789'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('"Huỷ" leaves no request behind', (t) async {
    await pumpTab(t);
    await t.tap(find.text('Đăng ký'));
    await t.pumpAndSettle();
    await t.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Huỷ')));
    await t.pumpAndSettle();
    expect(find.text('Chuyển khoản để kích hoạt gói'), findsNothing);
    expect(server.purchases, 0);
    expect(server.requests, isEmpty);
    expect(find.text('Xem thông tin chuyển khoản và mã QR'), findsNothing); // nothing is waiting
    expect(find.text('Đăng ký'), findsOneWidget); // the buttons work again
  });

  testWidgets('closing the sheet without choosing (swipe down / tap outside) also sends nothing', (t) async {
    await pumpTab(t);
    await t.tap(find.text('Đăng ký'));
    await t.pumpAndSettle();
    await t.tapAt(const Offset(200, 60)); // the dimmed page above the sheet
    await t.pumpAndSettle();
    expect(find.text('Chuyển khoản để kích hoạt gói'), findsNothing);
    expect(server.purchases, 0);
  });

  testWidgets('"Đã chuyển khoản" sends the request with the reference the QR carried', (t) async {
    await pumpTab(t);
    await t.tap(find.text('Đăng ký'));
    await t.pumpAndSettle();
    final shown = t.widgetList<SelectableText>(find.descendant(of: find.byType(BottomSheet), matching: find.byType(SelectableText))).map((x) => x.data ?? '').firstWhere((x) => RegExp(r'^XS[A-HJ-NP-Z2-9]{6}$').hasMatch(x));
    await t.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Đã chuyển khoản')));
    await t.pumpAndSettle();
    expect(server.purchases, 1);
    expect(server.requests.single['referenceCode'], shown);
    expect(find.text('Chuyển khoản để kích hoạt gói'), findsNothing);
    expect(find.textContaining('Đã gửi yêu cầu cho admin'), findsOneWidget);
    // the request now waits: its details can be looked at again, with a plain "Đóng"
    await t.tap(find.text('Xem thông tin chuyển khoản và mã QR'));
    await t.pumpAndSettle();
    expect(find.text('Đóng'), findsOneWidget);
    expect(find.text('Đã chuyển khoản'), findsNothing);
  });

  testWidgets('if the server had to use another reference the customer is told', (t) async {
    await pumpTab(t);
    server.keepReference = 'XSZZZZZZ';
    await t.tap(find.text('Đăng ký'));
    await t.pumpAndSettle();
    await t.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Đã chuyển khoản')));
    await t.pumpAndSettle();
    expect(find.textContaining('XSZZZZZZ'), findsWidgets);
    expect(find.textContaining('khác mã trên QR'), findsOneWidget);
  });

  testWidgets('renewing the plan in use goes the same way', (t) async {
    await pumpTab(t);
    await t.tap(find.text('Gia hạn'));
    await t.pumpAndSettle();
    expect(server.purchases, 0);
    expect(find.text('Chuyển khoản để kích hoạt gói'), findsOneWidget);
    await t.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Đã chuyển khoản')));
    await t.pumpAndSettle();
    expect(server.purchases, 1);
    expect(server.requests.single['packageType'], 'month');
  });

  testWidgets('Admin decided: the screen reads the package again without leaving it', (t) async {
    await pumpTab(t);
    final before = server.meCalls;
    server.packageType = 'quarter';
    PackageEvents.instance.bump(); // what the `payment-decided` event does
    await t.pump(const Duration(milliseconds: 200));
    expect(server.meCalls, greaterThan(before));
    expect(ctl.me!.packageType, 'quarter');
    // the plan in use moved to the 3-month one
    expect(find.text('Đang dùng'), findsOneWidget);
  });

  test('the payment notification: text, payload and where a tap goes', () {
    final ok = paymentNotice(approved: true);
    expect(ok.body, 'Gói của bạn đã được gia hạn');
    expect(ok.payload, 'pay:approved');
    expect(routeForTarget(parseNoticePayload(ok.payload)!), '/overview');
    final no = paymentNotice(approved: false);
    expect(routeForTarget(parseNoticePayload(no.payload)!), '/account?tab=packages');
    expect(no.body, isNot(matches(RegExp(r'\d')))); // no amount on a lock screen
    expect(ok.body, isNot(matches(RegExp(r'\d'))));
  });
}
