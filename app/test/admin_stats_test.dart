import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/admin/stats/admin_stats_logic.dart';
import 'package:mamba_app/features/admin/stats/admin_stats_screen.dart';

const _body = {
  'series': [
    {'date': '2026-10-10', 'newUsers': 2, 'revenue': 300000},
    {'date': '2026-10-11', 'newUsers': 0, 'revenue': 1500000},
  ],
  'seriesRange': '7',
  'canRevenue': true,
  'totalSubscribers': 10,
  'activeSubscribers': 7,
  'expiredSubscribers': 3,
  'byPackage': {'trial': 4, 'm1': 6},
};

void main() {
  test('parses stats', () {
    final s = AdminStats.fromJson(_body);
    expect([s.total, s.active, s.expired], [10, 7, 3]);
    expect(s.byPackage['m1'], 6);
    expect(s.totalNewUsers, 2);
    expect(s.totalRevenue, 1800000);
    expect(s.canRevenue, isTrue);
  });

  test('revenue absent when not allowed', () {
    final s = AdminStats.fromJson({
      'series': [
        {'date': '2026-10', 'newUsers': 5},
      ],
      'canRevenue': false,
    });
    expect(s.canRevenue, isFalse);
    expect(s.series.single.revenue, 0);
    expect(s.total, 0);
  });

  test('axis helpers', () {
    expect(niceMax(0), 4);
    expect(niceMax(130), 200);
    expect(niceMax(4.2), 5);
    expect(shortDate('2026-10-11'), '11/10');
    expect(shortDate('2026-10'), '10/26');
    expect(longDate('2026-10'), 'Tháng 10/2026');
    expect(shortDate('2026'), '2026');
    expect(longDate('2026', 'year'), 'Năm 2026');
    expect(longDate('2026-10-05', 'week'), 'Tuần 05/10 – 11/10/2026');
    expect(longDate('2026-12-28', 'week'), 'Tuần 28/12 – 03/01/2027');
    expect(shortAxis(1500000, money: true), '1,5tr');
    expect(shortAxis(200000, money: true), '200k');
    expect(packageLabelOf('trial', {}), 'Dùng thử 30 ngày');
    expect(packageLabelOf('m1', {'m1': 'Gói 1 tháng'}), 'Gói 1 tháng');
    expect(packageLabelOf('old', {}), 'old');
  });

  testWidgets('screen requests chosen range and shows package labels', (t) async {
    final seen = <String>[];
    final api = ApiClient(
      AuthStore(),
      client: MockClient((req) async {
        seen.add(req.url.path.replaceFirst('/api', '') + (req.url.hasQuery ? '?${req.url.query}' : ''));
        final p = req.url.path.replaceFirst('/api', '');
        Object b = p == '/admin/stats'
            ? _body
            : {
                'packages': [
                  {'type': 'm1', 'label': 'Gói 1 tháng'},
                ],
              };
        return http.Response.bytes(utf8.encode(jsonEncode(b)), 200);
      }),
    );
    await t.binding.setSurfaceSize(const Size(360, 1400));
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: StatsBody(api: api)),
      ),
    );
    await t.pumpAndSettle();
    expect(seen, contains('/admin/stats?range=day'));
    expect(find.text('Tổng khách hàng'), findsOneWidget);
    expect(find.text('Gói 1 tháng'), findsOneWidget);
    for (final (label, key) in [('Tuần', 'week'), ('Tháng', 'month'), ('Năm', 'year')]) {
      await t.tap(find.text(label));
      await t.pumpAndSettle();
      expect(seen, contains('/admin/stats?range=$key'));
    }
    expect(find.text('5 năm gần nhất'), findsOneWidget);
    await t.binding.setSurfaceSize(null);
  });

  testWidgets('without right nothing is requested', (t) async {
    var n = 0;
    final api = ApiClient(
      AuthStore(),
      client: MockClient((req) async {
        n++;
        return http.Response('{}', 200);
      }),
    );
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: StatsBody(api: api, allowed: false)),
      ),
    );
    await t.pumpAndSettle();
    expect(n, 1); // only the harmless package-label lookup
    expect(find.textContaining('chưa được cấp quyền'), findsOneWidget);
  });
}
