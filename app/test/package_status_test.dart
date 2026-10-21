import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/account/account_controller.dart';
import 'package:mamba_app/features/account/me_profile.dart';
import 'package:mamba_app/features/account/package_status.dart';
import 'package:mamba_app/features/overview/package_card.dart';

final now = DateTime(2026, 10, 20, 12, 0);

MeProfile me({required Duration? left, bool active = true, String label = 'Gói tháng', String role = 'user'}) => MeProfile(
      name: 'A',
      username: 'a',
      role: role,
      packageLabel: label,
      packageExpiresAt: left == null ? null : now.add(left).toUtc().toIso8601String(),
      packageActive: active,
    );

void main() {
  group('packageStatus', () {
    test('plenty of time: days only, level ok', () {
      final s = packageStatus(me(left: const Duration(days: 30, hours: 5)), now);
      expect(s.level, PackageLevel.ok);
      expect(s.headline, 'Còn 30 ngày');
      expect(s.detail, contains('Gói tháng'));
      expect(s.detail, contains('Hết hạn: 19/11/2026 17:00'));
      expect(s.needsAction, isFalse);
    });

    test('7 days or fewer is "sắp hết hạn" and shows hours too; 8 days is not', () {
      expect(packageStatus(me(left: const Duration(days: 8)), now).level, PackageLevel.ok);
      final s = packageStatus(me(left: const Duration(days: 7)), now);
      expect(s.level, PackageLevel.soon);
      final t = packageStatus(me(left: const Duration(days: 3, hours: 5, minutes: 10)), now);
      expect(t.level, PackageLevel.soon);
      expect(t.headline, 'Còn 3 ngày 5 giờ');
      expect(t.needsAction, isTrue);
    });

    test('less than a day: hours and minutes, then minutes', () {
      expect(packageStatus(me(left: const Duration(hours: 5, minutes: 20)), now).headline, 'Còn 5 giờ 20 phút');
      expect(packageStatus(me(left: const Duration(hours: 2)), now).headline, 'Còn 2 giờ');
      expect(packageStatus(me(left: const Duration(minutes: 45)), now).headline, 'Còn 45 phút');
      expect(packageStatus(me(left: const Duration(seconds: 20)), now).headline, 'Còn 1 phút');
    });

    test('expired: the server flag or a date in the past', () {
      expect(packageStatus(me(left: const Duration(days: 3), active: false), now).level, PackageLevel.expired);
      final past = packageStatus(me(left: const Duration(days: -2), active: false), now);
      expect(past.level, PackageLevel.expired);
      expect(past.headline, 'Gói đã hết hạn');
      expect(past.detail, contains('18/10/2026'));
      // the date alone says it ran out even if the flag is stale
      expect(packageStatus(me(left: const Duration(minutes: -1)), now).level, PackageLevel.expired);
    });

    test('no package at all', () {
      expect(packageStatus(me(left: null, active: false), now).level, PackageLevel.none);
      expect(packageStatus(null, now).level, PackageLevel.none);
    });
  });

  group('PackageCard', () {
    AccountController ctl(MeProfile? m) => AccountController(ApiClient(AuthStore(), client: MockClient((_) async => http.Response('{}', 404))))
      ..me = m
      ..loading = false;

    Future<void> pump(WidgetTester t, MeProfile? m, {VoidCallback? onRenew}) =>
        t.pumpWidget(MaterialApp(home: Scaffold(body: PackageCard(controller: ctl(m), onRenew: onRenew))));

    testWidgets('active package: remaining time, no renew button', (t) async {
      await pump(t, me(left: const Duration(days: 40)).copyForTest(now));
      expect(find.byKey(const Key('package-headline')), findsOneWidget);
      expect(find.textContaining('Còn '), findsOneWidget);
      expect(find.text('Gia hạn'), findsNothing);
    });

    testWidgets('about to run out: warning text and a renew button', (t) async {
      var renewed = 0;
      await pump(t, me(left: const Duration(days: 2)).copyForTest(now), onRenew: () => renewed++);
      expect(find.textContaining('Sắp hết hạn'), findsOneWidget);
      await t.tap(find.text('Gia hạn'));
      expect(renewed, 1);
    });

    testWidgets('expired: says so and offers renewal', (t) async {
      await pump(t, me(left: const Duration(days: -1), active: false).copyForTest(now));
      expect(find.text('Gói đã hết hạn'), findsOneWidget);
      expect(find.text('Gia hạn'), findsOneWidget);
    });

    testWidgets('nothing is shown before the profile is read, nor for an Admin', (t) async {
      await pump(t, null);
      expect(find.byKey(const Key('package-headline')), findsNothing);
      await pump(t, me(left: const Duration(days: 1), role: 'admin'));
      expect(find.byKey(const Key('package-headline')), findsNothing);
    });
  });
}

extension on MeProfile {
  /// The card reads the real clock; rebase the expiry (built relative to the fixed test clock) onto "now".
  MeProfile copyForTest(DateTime fixedNow) {
    final end = DateTime.parse(packageExpiresAt!).toLocal();
    final left = end.difference(fixedNow);
    return MeProfile(
      name: name,
      username: username,
      role: role,
      packageLabel: packageLabel,
      packageExpiresAt: DateTime.now().add(left).toUtc().toIso8601String(),
      packageActive: packageActive,
    );
  }
}
