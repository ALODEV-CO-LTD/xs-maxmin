import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/admin_session.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/admin/users/admin_users_logic.dart';
import 'package:mamba_app/features/admin/users/admin_users_screen.dart';

http.Response _json(Object o, [int code = 200]) => http.Response.bytes(utf8.encode(jsonEncode(o)), code, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _sub(int i, {bool locked = false}) => {
  'id': 'u$i',
  'name': 'Khách $i',
  'username': 'user$i',
  'package': {'type': 'm1', 'label': 'Gói 1 tháng', 'expiresAt': '2026-12-01T00:00:00.000Z'},
  'status': 'active',
  'accountLocked': locked,
};

ApiClient _api(Map<String, Object Function(http.Request)> routes, [List<String>? seen]) => ApiClient(
  AuthStore(),
  client: MockClient((req) async {
    seen?.add('${req.method} ${req.url.path.replaceFirst('/api', '')}${req.url.hasQuery ? '?${req.url.query}' : ''}');
    final h = routes[req.url.path.replaceFirst('/api', '')];
    return h == null ? _json({'error': 'nf'}, 404) : _json(h(req));
  }),
);

void main() {
  test('parses subscribers with Vietnamese names and lock flag', () {
    final p = UsersPage.fromJson({
      'total': 1,
      'subscribers': [_sub(1, locked: true)..['name'] = 'Nguyễn Văn Á'],
    });
    expect(p.users.single.name, 'Nguyễn Văn Á');
    expect(p.users.single.locked, isTrue);
    expect(p.users.single.packageLabel, 'Gói 1 tháng');
    expect(p.users.single.active, isTrue);
  });

  test('pager reveals 30 at a time, replaces and removes', () {
    final pager = UsersPager()..reset([for (var i = 0; i < 70; i++) Subscriber.fromJson(_sub(i))]);
    expect(pager.visible.length, 30);
    expect(pager.hasMore, isTrue);
    pager.loadMore();
    pager.loadMore();
    expect(pager.visible.length, 70);
    expect(pager.hasMore, isFalse);
    pager.remove('u3');
    expect(pager.all.length, 69);
    pager.replace(Subscriber.fromJson(_sub(5, locked: true)));
    expect(pager.all.firstWhere((s) => s.id == 'u5').locked, isTrue);
  });

  test('rights follow AdminSession.can', () {
    final s = AdminSession()..permissions = {'users.view', 'users.lock'};
    final r = UserRights.of(s);
    expect([r.view, r.lock, r.recovery, r.delete], [true, true, false, false]);
    s.isRoot = true;
    expect(UserRights.of(s).delete, isTrue);
  });

  test('delete confirmation needs the typed username', () {
    expect(deleteConfirmed('', 'abc'), isFalse);
    expect(deleteConfirmed(' ABC ', 'abc'), isTrue);
    expect(deleteConfirmed('abd', 'abc'), isFalse);
  });

  test('generated password satisfies policy shape', () {
    final p = generatePassword();
    expect(p.length, 10);
    expect(RegExp(r'[0-9]').hasMatch(p) && RegExp(r'[A-Za-z]').hasMatch(p), isTrue);
  });

  test('recovery queue parsing', () {
    final q = RecoveryQueue.fromJson({
      'pending': 1,
      'requests': [
        {'id': 'r1', 'username': 'a', 'name': 'Á', 'status': 'pending', 'note': 'xin giúp', 'accountLocked': true},
      ],
    });
    expect(q.pending, 1);
    expect(q.requests.single.statusLabel, 'Chờ duyệt');
    expect(q.requests.single.accountLocked, isTrue);
  });

  testWidgets('list loads, searches and hides recovery tile without right', (t) async {
    final seen = <String>[];
    final api = _api({
      '/admin/users': (r) => {
        'total': 2,
        'subscribers': [_sub(1), _sub(2)],
      },
      '/admin/recovery-requests': (r) => {'pending': 3, 'requests': []},
    }, seen);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UsersListBody(api: api, rights: const UserRights(view: true)),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Khách 1'), findsOneWidget);
    expect(find.text('Yêu cầu hỗ trợ khôi phục'), findsNothing);
    expect(seen.any((s) => s.contains('recovery-requests')), isFalse);
    await t.enterText(find.byType(TextField), 'Á');
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    expect(seen.last, contains('q=%C3%81'));
  });

  testWidgets('shows recovery tile with pending count when allowed', (t) async {
    final api = _api({
      '/admin/users': (r) => {'total': 0, 'subscribers': []},
      '/admin/recovery-requests': (r) => {'pending': 3, 'requests': []},
    });
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UsersListBody(api: api, rights: const UserRights(view: true, recovery: true)),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('3 yêu cầu chờ duyệt'), findsOneWidget);
    expect(find.text('Không có khách hàng nào'), findsOneWidget);
  });

  testWidgets('no view right shows a message and makes no request', (t) async {
    final seen = <String>[];
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UsersListBody(api: _api({}, seen), rights: const UserRights()),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.textContaining('chưa được cấp quyền'), findsOneWidget);
    expect(seen, isEmpty);
  });
}
