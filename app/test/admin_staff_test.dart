import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/admin/staff/admin_staff_logic.dart';
import 'package:mamba_app/features/admin/staff/admin_staff_screen.dart';

const _res = {
  'permissions': {'users.view': 'Xem danh sách và thông tin khách hàng', 'stats.view': 'Xem thống kê hệ thống'},
  'staff': [
    {
      'id': 's1',
      'name': 'Lê Thị Ánh',
      'username': 'anh',
      'permissions': ['users.view'],
      'locked': true,
      'createdAt': '2026-10-01T00:00:00.000Z',
    },
  ],
};

void main() {
  test('parses staff data', () {
    final d = StaffData.fromJson(_res);
    expect(d.catalog.length, 2);
    expect(d.staff.single.name, 'Lê Thị Ánh');
    expect(d.staff.single.locked, isTrue);
    expect(d.staff.single.permissions, ['users.view']);
  });

  test('validation and permission diff', () {
    expect(validateNewStaff(name: '', username: 'abc', password: '12345678', permissions: ['a']), isNotNull);
    expect(validateNewStaff(name: 'A', username: 'ab', password: '12345678', permissions: ['a']), contains('3 ký tự'));
    expect(validateNewStaff(name: 'A', username: 'abc', password: '1234', permissions: ['a']), isNotNull);
    expect(validateNewStaff(name: 'A', username: 'abc', password: '12345678', permissions: []), isNotNull);
    expect(validateNewStaff(name: 'A', username: 'abc', password: '12345678', permissions: ['a']), isNull);
    expect(samePermissions(['a', 'b'], ['b', 'a']), isTrue);
    expect(samePermissions(['a'], ['a', 'b']), isFalse);
  });

  testWidgets('non-root sees a notice and no request is made', (t) async {
    var n = 0;
    final api = ApiClient(
      AuthStore(),
      client: MockClient((r) async {
        n++;
        return http.Response('{}', 200);
      }),
    );
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: StaffBody(api: api, isRoot: false)),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Chỉ Admin gốc được quản lý phân quyền.'), findsOneWidget);
    expect(n, 0);
  });

  testWidgets('root sees staff list', (t) async {
    final api = ApiClient(AuthStore(), client: MockClient((r) async => http.Response.bytes(utf8.encode(jsonEncode(_res)), 200)));
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: StaffBody(api: api, isRoot: true)),
      ),
    );
    await t.pumpAndSettle();
    expect(find.textContaining('Lê Thị Ánh'), findsOneWidget);
    expect(find.text('Đang khoá'), findsOneWidget);
    expect(find.text('Mở khoá'), findsOneWidget);
  });
}
