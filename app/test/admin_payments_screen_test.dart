import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/admin_session.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/admin/notices/admin_notices_screen.dart';
import 'package:mamba_app/features/admin/payments/admin_payments_screen.dart';
import 'package:mamba_app/features/admin/settings/admin_settings_screen.dart';
import 'package:provider/provider.dart';

class _Mem extends AuthStore {
  @override
  Future<void> init() async {}
}

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json; charset=utf-8'});

Widget _host(Widget child, ApiClient api, Set<String> perms) {
  final s = AdminSession()..permissions = perms;
  return MultiProvider(
    providers: [
      Provider<ApiClient>.value(value: api),
      ChangeNotifierProvider<AdminSession>.value(value: s),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('payments: lists requests, filters by status, approves after confirmation', (tester) async {
    _phone(tester);
    final calls = <String>[];
    var decided = false;
    final api = ApiClient(
      _Mem(),
      client: MockClient((req) async {
        calls.add('${req.method} ${req.url.path}?${req.url.query}');
        if (req.url.path.endsWith('/me/packages')) {
          return _json({
            'packages': [
              {'type': 'p1', 'label': 'Gói 1 tháng'},
            ],
          });
        }
        if (req.url.path.endsWith('/approve')) {
          decided = true;
          return _json({'ok': true});
        }
        if (req.url.path.endsWith('/admin/payment-requests')) {
          final status = req.url.queryParameters['status'];
          final pending = (status == 'pending' || status == 'all') && !decided; // the list opens on Tất cả
          return _json({
            'requests': pending
                ? [
                    {
                      'id': 'r1',
                      'userName': 'Nguyễn An',
                      'username': 'an',
                      'packageType': 'p1',
                      'amount': 150000,
                      'status': 'pending',
                      'referenceCode': 'MB123',
                      'createdAt': '2026-10-11T03:00:00.000Z',
                    },
                  ]
                : [],
            'total': pending ? 1 : 0,
            'hasMore': false,
            'summary': {'pending': pending ? 1 : 0, 'approvedCount': 2, 'revenueToday': 0, 'revenue7d': 0, 'revenue30d': 0, 'revenueAll': 300000},
          });
        }
        return _json({'error': 'x'}, 404);
      }),
    );
    await tester.pumpWidget(_host(const AdminPaymentsScreen(), api, {'payments.manage'}));
    await tester.pumpAndSettle();

    expect(find.text('Nguyễn An (@an)'), findsOneWidget);
    expect(find.text('Gói 1 tháng · 150.000 đ'), findsOneWidget);
    expect(find.text('Duyệt thanh toán'), findsOneWidget); // pill
    expect(find.text('Lịch sử gia hạn'), findsOneWidget);

    await tester.tap(find.text('Duyệt').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Xác nhận đã nhận 150.000 đ'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Duyệt')));
    await tester.pumpAndSettle();
    expect(calls.any((c) => c.startsWith('POST /api/admin/payment-requests/r1/approve')), isTrue);
    expect(find.text('Không có yêu cầu nào'), findsOneWidget);
    expect(calls.where((c) => c.contains('status=all')).length, greaterThanOrEqualTo(2)); // opens on Tất cả and reloads after approving
    expect(calls.any((c) => c.contains('status=pending')), isFalse);
  });

  testWidgets('settings: only the pills the rights allow; policy stays read-only until Sửa', (tester) async {
    _phone(tester);
    final api = ApiClient(
      _Mem(),
      client: MockClient((req) async {
        if (req.url.path.endsWith('/admin/security-policy')) {
          return _json({
            'policy': {
              'loginFreeAttempts': 5,
              'loginBaseLockSeconds': 30,
              'loginMaxLockSeconds': 900,
              'tokenDays': 30,
              'autoLockMinutes': 0,
              'watermarkEnabled': false,
              'screenshotGuardEnabled': true,
              'blurOnHideEnabled': false,
            },
            'defaults': {'loginFreeAttempts': 5, 'loginBaseLockSeconds': 30, 'loginMaxLockSeconds': 900, 'tokenDays': 30, 'autoLockMinutes': 0},
          });
        }
        return _json({'error': 'x'}, 404);
      }),
    );
    await tester.pumpWidget(_host(const AdminSettingsScreen(), api, {'security.policy', 'backups.manage'}));
    await tester.pumpAndSettle();

    expect(find.text('Chính sách bảo mật'), findsOneWidget);
    expect(find.text('Sao lưu'), findsOneWidget);
    expect(find.text('Thanh toán'), findsNothing);
    expect(find.text('Nhật ký bảo mật'), findsNothing);

    expect(tester.widget<TextField>(find.byKey(const ValueKey('policy-tokenDays'))).enabled, isFalse);
    await tester.ensureVisible(find.text('Sửa'));
    await tester.tap(find.text('Sửa'));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('policy-tokenDays'));
    expect(tester.widget<TextField>(field).enabled, isTrue);
    await tester.enterText(field, '400');
    await tester.pump();
    await tester.ensureVisible(find.text('Huỷ'));
    await tester.tap(find.text('Huỷ'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).enabled, isFalse);
    expect(tester.widget<TextField>(field).controller!.text, '30');
  });

  testWidgets('notices: maintenance only account sees just the maintenance card', (tester) async {
    _phone(tester);
    final api = ApiClient(
      _Mem(),
      client: MockClient((req) async {
        if (req.url.path.endsWith('/admin/maintenance')) return _json({'enabled': true, 'message': 'Bảo trì 23h'});
        return _json({'error': 'x'}, 403);
      }),
    );
    await tester.pumpWidget(_host(const AdminNoticesScreen(), api, {'maintenance.manage'}));
    await tester.pumpAndSettle();
    expect(find.text('Chế độ bảo trì'), findsWidgets);
    expect(find.text('Gửi thông báo'), findsNothing);
    expect(find.text('Bảo trì 23h'), findsOneWidget);
  });
}
