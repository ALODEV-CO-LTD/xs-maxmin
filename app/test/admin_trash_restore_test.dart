import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/admin_session.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/admin/settings/settings_backups.dart';
import 'package:mamba_app/features/admin/trash/admin_trash_screen.dart';
import 'package:mamba_app/features/admin/trash/trash_logic.dart';
import 'package:provider/provider.dart';

class _Mem extends AuthStore {
  @override
  Future<void> init() async {}
}

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json; charset=utf-8'});

Widget _host(Widget child, ApiClient api) => MultiProvider(
      providers: [Provider<ApiClient>.value(value: api), ChangeNotifierProvider<AdminSession>.value(value: AdminSession()..permissions = {'trash.manage', 'backups.manage'})],
      child: MaterialApp(home: Scaffold(body: child)),
    );

void _phone(WidgetTester t) {
  t.view.physicalSize = const Size(400 * 2, 2400 * 2);
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
}

void main() {
  group('trash logic', () {
    test('the counts read as a sentence, in a fixed order, without zeros', () {
      expect(countsSummary({'data_entries': 19, 'customers': 2, 'lottery_results': 85, 'friendships': 0}), '2 khách hàng · 19 số liệu · 85 kết quả xổ số');
      expect(countsSummary({}), '');
      expect(countsSummary({'something_new': 3}), '3 something_new');
    });
    test('an item from the API', () {
      final t = TrashItem.fromJson({'id': 'a', 'kind': 'user', 'label': 'u1 (An)', 'counts': {'data_entries': 2}, 'deletedAt': '2026-10-24T08:00:00Z', 'daysLeft': 1, 'deletedByName': 'admin'});
      expect(t.kindLabel, 'Tài khoản khách hàng');
      expect(t.timeLeft, 'Còn dưới 1 ngày');
      expect(TrashItem.fromJson({'id': 'b', 'kind': 'package', 'label': 'x', 'daysLeft': 5}).timeLeft, 'Còn 5 ngày');
    });
  });

  group('Thùng rác screen', () {
    late List<Map<String, dynamic>> items;
    late List<String> calls;
    ApiClient makeApi() => ApiClient(_Mem(), client: MockClient((req) async {
          calls.add('${req.method} ${req.url.path}');
          if (req.url.path.endsWith('/admin/trash') && req.method == 'GET') return _json({'trashDays': 7, 'items': items});
          final restore = RegExp(r'/admin/trash/([^/]+)/restore$').firstMatch(req.url.path);
          if (restore != null) {
            if (restore.group(1) == 'taken') return _json({'error': 'Tên đăng nhập "an" đã có người khác dùng, chưa thể khôi phục'}, 409);
            items.removeWhere((i) => i['id'] == restore.group(1));
            return _json({'restored': true});
          }
          if (req.method == 'DELETE') {
            items.removeWhere((i) => req.url.path.endsWith('/${i['id']}'));
            return _json({'deleted': true});
          }
          return _json({'error': 'x'}, 404);
        }));

    setUp(() {
      calls = [];
      items = [
        {'id': 'u1', 'kind': 'user', 'label': 'an (Nguyen An)', 'counts': {'customers': 2, 'data_entries': 19}, 'deletedAt': '2026-10-24T08:00:00Z', 'daysLeft': 6, 'deletedByName': 'admin'},
        {'id': 'p1', 'kind': 'package', 'label': 'Gói thử', 'counts': {'packages': 1}, 'deletedAt': '2026-10-23T08:00:00Z', 'daysLeft': 5},
        {'id': 'taken', 'kind': 'user', 'label': 'binh', 'counts': {}, 'deletedAt': '2026-10-22T08:00:00Z', 'daysLeft': 4},
      ];
    });

    testWidgets('lists what was deleted with how long is left and how much, never content', (t) async {
      _phone(t);
      await t.pumpWidget(_host(const AdminTrashScreen(), makeApi()));
      await t.pumpAndSettle();
      expect(find.text('an (Nguyen An)'), findsOneWidget);
      expect(find.text('Còn 6 ngày'), findsOneWidget);
      expect(find.text('2 khách hàng · 19 số liệu'), findsOneWidget);
      expect(find.textContaining('giữ 7 ngày'), findsOneWidget);
      expect(find.text('Khôi phục'), findsNWidgets(3));
    });

    testWidgets('empty trash', (t) async {
      _phone(t);
      items = [];
      await t.pumpWidget(_host(const AdminTrashScreen(), makeApi()));
      await t.pumpAndSettle();
      expect(find.text('Thùng rác trống.'), findsOneWidget);
    });

    testWidgets('restore asks first, then puts the item back and says so', (t) async {
      _phone(t);
      await t.pumpWidget(_host(const AdminTrashScreen(), makeApi()));
      await t.pumpAndSettle();
      await t.tap(find.descendant(of: find.byKey(const ValueKey('trash-u1')), matching: find.text('Khôi phục')));
      await t.pumpAndSettle();
      expect(calls.where((c) => c.contains('/restore')), isEmpty); // not yet: the question is on screen
      await t.tap(find.descendant(of: find.byType(Dialog), matching: find.text('Khôi phục')).last);
      await t.pumpAndSettle();
      expect(calls, contains('POST /api/admin/trash/u1/restore'));
      expect(find.text('Đã khôi phục "an (Nguyen An)".'), findsOneWidget);
      expect(find.byKey(const ValueKey('trash-u1')), findsNothing);
    });

    testWidgets('a restore the server refuses shows its reason and keeps the item', (t) async {
      _phone(t);
      await t.pumpWidget(_host(const AdminTrashScreen(), makeApi()));
      await t.pumpAndSettle();
      await t.tap(find.descendant(of: find.byKey(const ValueKey('trash-taken')), matching: find.text('Khôi phục')));
      await t.pumpAndSettle();
      await t.tap(find.descendant(of: find.byType(Dialog), matching: find.text('Khôi phục')).last);
      await t.pumpAndSettle();
      expect(find.textContaining('đã có người khác dùng'), findsOneWidget);
      expect(find.byKey(const ValueKey('trash-taken')), findsOneWidget);
    });

    testWidgets('"Xoá hẳn" asks, and "Huỷ" in the question deletes nothing', (t) async {
      _phone(t);
      await t.pumpWidget(_host(const AdminTrashScreen(), makeApi()));
      await t.pumpAndSettle();
      await t.tap(find.descendant(of: find.byKey(const ValueKey('trash-p1')), matching: find.text('Xoá hẳn')));
      await t.pumpAndSettle();
      await t.tap(find.descendant(of: find.byType(Dialog), matching: find.text('Huỷ')));
      await t.pumpAndSettle();
      expect(calls.where((c) => c.startsWith('DELETE')), isEmpty);
      await t.tap(find.descendant(of: find.byKey(const ValueKey('trash-p1')), matching: find.text('Xoá hẳn')));
      await t.pumpAndSettle();
      await t.tap(find.descendant(of: find.byType(Dialog), matching: find.text('Xoá hẳn')).last);
      await t.pumpAndSettle();
      expect(calls, contains('DELETE /api/admin/trash/p1'));
      expect(find.byKey(const ValueKey('trash-p1')), findsNothing);
    });
  });

  group('restore one customer from a backup', () {
    late List<Map<String, dynamic>> restores;
    ApiClient makeApi({bool userGone = false}) {
      restores = [];
      return ApiClient(_Mem(), client: MockClient((req) async {
        final p = req.url.path;
        if (p.endsWith('/admin/backups') && req.method == 'GET') {
          return _json({
            'backups': [
              {'name': 'xoso-2026-10-20T01-00-00-000000Z.db', 'size': 266240, 'createdAt': '2026-10-20T01:00:00Z'},
            ],
            'sources': [
              {'id': 'cron:xoso-20261025-0200.db', 'source': 'cron', 'name': 'xoso-20261025-0200.db', 'size': 516096, 'createdAt': '2026-10-25T02:00:00Z'},
              {'id': 'manual:xoso-2026-10-20T01-00-00-000000Z.db', 'source': 'manual', 'name': 'xoso-2026-10-20T01-00-00-000000Z.db', 'size': 266240, 'createdAt': '2026-10-20T01:00:00Z'},
            ],
          });
        }
        if (p.endsWith('/admin/backups/users')) {
          expect(req.url.queryParameters['backup'], 'cron:xoso-20261025-0200.db');
          return _json({
            'users': [
              {'id': 'u1', 'username': 'an', 'name': 'Nguyen An', 'inBackup': {'data_entries': 19, 'customers': 2}, 'now': {'data_entries': 0, 'customers': 0}},
              {'id': 'u2', 'username': 'binh', 'name': '', 'inBackup': {'data_entries': 3}, 'now': userGone ? null : {'data_entries': 3}},
            ],
          });
        }
        if (p.endsWith('/admin/backups/restore-user')) {
          restores.add(jsonDecode(req.body) as Map<String, dynamic>);
          return _json({'restored': true, 'mode': 'merge', 'written': {'data_entries': 19, 'customers': 2}, 'removed': {}, 'safetyBackup': 'xoso-2026-10-25T03-00-00-000000Z.db'});
        }
        return _json({'error': 'x'}, 404);
      }));
    }

    testWidgets('the backups tab also lists the daily server backups with a Khôi phục button', (t) async {
      _phone(t);
      await t.pumpWidget(_host(const SingleChildScrollView(child: BackupsSection()), makeApi()));
      await t.pumpAndSettle();
      expect(find.text('Khôi phục dữ liệu một khách'), findsOneWidget);
      expect(find.byKey(const ValueKey('restore-cron:xoso-20261025-0200.db')), findsOneWidget);
      expect(find.textContaining('Tự động hằng ngày'), findsOneWidget);
      expect(find.textContaining('Tạo trong app'), findsOneWidget);
    });

    Future<void> openSheet(WidgetTester t, {bool userGone = false}) async {
      _phone(t);
      await t.pumpWidget(_host(const SingleChildScrollView(child: BackupsSection()), makeApi(userGone: userGone)));
      await t.pumpAndSettle();
      await t.tap(find.descendant(of: find.byKey(const ValueKey('restore-cron:xoso-20261025-0200.db')), matching: find.text('Khôi phục')));
      await t.pumpAndSettle();
    }

    final sheet = find.byType(BottomSheet);

    testWidgets('pick a customer, see then and now, restore by "thêm lại phần còn thiếu"', (t) async {
      await openSheet(t);
      await t.enterText(find.descendant(of: sheet, matching: find.byType(TextField)), 'nguyen');
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('customer-u2')), findsNothing); // the search narrows the list
      await t.tap(find.byKey(const ValueKey('customer-u1')));
      await t.pumpAndSettle();
      expect(find.descendant(of: sheet, matching: find.text('Trong bản sao lưu')), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('2 khách hàng · 19 số liệu')), findsOneWidget); // then
      expect(find.descendant(of: sheet, matching: find.text('chưa có dữ liệu')), findsOneWidget); // now: nothing left
      await t.tap(find.descendant(of: sheet, matching: find.text('Khôi phục')));
      await t.pumpAndSettle();
      expect(restores, [
        {'backup': 'cron:xoso-20261025-0200.db', 'userId': 'u1', 'mode': 'merge'},
      ]);
      expect(find.textContaining('đã ghi 2 khách hàng · 19 số liệu'), findsOneWidget);
      expect(find.textContaining('xoso-2026-10-25T03-00-00-000000Z.db'), findsOneWidget); // the safety backup it made first
    });

    testWidgets('"replace" needs the customer\'s username typed first', (t) async {
      await openSheet(t);
      await t.tap(find.byKey(const ValueKey('customer-u1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('mode-replace')));
      await t.pumpAndSettle();
      final go = find.descendant(of: sheet, matching: find.text('Thay thế dữ liệu'));
      expect(find.descendant(of: sheet, matching: find.widgetWithText(FilledButton, 'Thay thế dữ liệu')), findsOneWidget);
      await t.tap(go);
      await t.pumpAndSettle();
      expect(restores, isEmpty); // disabled: nothing typed
      await t.enterText(find.descendant(of: sheet, matching: find.byType(TextField)), 'binh');
      await t.pump();
      await t.tap(go);
      await t.pumpAndSettle();
      expect(restores, isEmpty); // the wrong name
      await t.enterText(find.descendant(of: sheet, matching: find.byType(TextField)), 'AN');
      await t.pump();
      await t.tap(go);
      await t.pumpAndSettle();
      expect(restores.single['mode'], 'replace');
    });

    testWidgets('an account that no longer exists cannot be restored here (points to the trash)', (t) async {
      await openSheet(t, userGone: true);
      expect(find.text('Tài khoản đã bị xoá (dùng Thùng rác)'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('customer-u2')));
      await t.pumpAndSettle();
      expect(find.descendant(of: sheet, matching: find.text('Tài khoản không còn')), findsOneWidget);
      await t.tap(find.descendant(of: sheet, matching: find.text('Khôi phục')));
      await t.pumpAndSettle();
      expect(restores, isEmpty);
    });
  });
}
