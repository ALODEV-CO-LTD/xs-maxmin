import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/account/account_packages_tab.dart';
import 'package:mamba_app/features/account/me_profile.dart';
import 'package:mamba_app/features/account/privacy/privacy_store.dart';
import 'package:mamba_app/features/account/account_profile_tab.dart' show changePasswordProblem;
import 'package:mamba_app/features/account/stats_logic.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Clock {
  DateTime now = DateTime(2026, 10, 11, 12);
  void add(Duration d) => now = now.add(d);
}

ApiClient _api(http.Response Function(http.Request) h) => ApiClient(AuthStore(), client: MockClient((r) async => h(r)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PrivacyPolicy.fromJson', () {
    test('safe defaults', () {
      final p = PrivacyPolicy.fromJson(null);
      expect(p.autoLockMinutes, 0);
      expect(p.screenshotGuardEnabled, isTrue);
      expect(p.blurOnHideEnabled, isFalse);
      expect(p.watermarkEnabled, isFalse);
      final e = PrivacyPolicy.fromJson(<String, dynamic>{});
      expect(e.screenshotGuardEnabled, isTrue);
      expect(e.blurOnHideEnabled, isFalse);
    });
    test('explicit values', () {
      final p = PrivacyPolicy.fromJson({'autoLockMinutes': 10, 'watermarkEnabled': true, 'screenshotGuardEnabled': false, 'blurOnHideEnabled': true});
      expect(p.autoLockMinutes, 10);
      expect(p.watermarkEnabled, isTrue);
      expect(p.screenshotGuardEnabled, isFalse);
      expect(p.blurOnHideEnabled, isTrue);
    });
    test('guard stays on for non-false values; blur needs exactly true; minutes tolerate strings/garbage', () {
      expect(PrivacyPolicy.fromJson({'screenshotGuardEnabled': 0}).screenshotGuardEnabled, isTrue);
      expect(PrivacyPolicy.fromJson({'blurOnHideEnabled': 1}).blurOnHideEnabled, isFalse);
      expect(PrivacyPolicy.fromJson({'autoLockMinutes': '7'}).autoLockMinutes, 7);
      expect(PrivacyPolicy.fromJson({'autoLockMinutes': 'x'}).autoLockMinutes, 0);
      expect(PrivacyPolicy.fromJson({'autoLockMinutes': -3}).autoLockMinutes, 0);
    });
  });

  group('PrivacyStore auto-lock timing', () {
    late _Clock clock;
    late PrivacyStore s;
    late ApiClient api;

    Future<void> startWith(Map<String, Object> policy, {Map<String, Object> prefs = const {}}) async {
      SharedPreferences.setMockInitialValues(prefs);
      clock = _Clock();
      s = PrivacyStore(clock: () => clock.now);
      api = _api((r) => http.Response('{"autoLockMinutes":${policy['autoLockMinutes'] ?? 0},"hideLockSeconds":${policy['hideLockSeconds'] ?? 0},"blurOnHideEnabled":${policy['blur'] ?? false},"screenshotGuardEnabled":${policy['guard'] ?? true}}', 200));
      await s.start(api);
    }

    test('policy default applies until the user chooses their own value', () async {
      await startWith({'autoLockMinutes': 5});
      expect(s.autoLockMinutes, 5);
      expect(s.hasOwnAutoLock, isFalse);
      await s.setAutoLockMinutes(1);
      expect(s.autoLockMinutes, 1);
      await s.setAutoLockMinutes(0);
      expect(s.autoLockMinutes, 0, reason: '0 = the user switched it off, overriding the default');
    });

    test('the Admin default for "lock when away" applies until the user chooses their own', () async {
      await startWith({'hideLockSeconds': 60});
      expect(s.hideLockSeconds, 60);
      expect(s.hasOwnHideLock, isFalse);
      // away for 61 s, back: locked by the system default
      s.onLifecycle(AppLifecycleState.paused);
      clock.now = clock.now.add(const Duration(seconds: 61));
      s.onLifecycle(AppLifecycleState.resumed);
      expect(s.locked, isTrue);
      await s.setHideLockSeconds(0);
      expect(s.hideLockSeconds, 0, reason: '0 = the user switched it off, overriding the default');
      expect(s.hasOwnHideLock, isTrue);
    });

    test('locks only after the idle limit, touch resets the clock', () async {
      await startWith({'autoLockMinutes': 5});
      clock.add(const Duration(minutes: 4, seconds: 59));
      expect(s.checkIdle(), isFalse);
      s.touch();
      clock.add(const Duration(minutes: 4));
      expect(s.checkIdle(), isFalse);
      clock.add(const Duration(minutes: 1));
      expect(s.checkIdle(), isTrue);
      expect(s.locked, isTrue);
    });

    test('off (0) never locks', () async {
      await startWith({'autoLockMinutes': 0});
      clock.add(const Duration(days: 2));
      expect(s.checkIdle(), isFalse);
      expect(s.locked, isFalse);
    });

    test('touch is ignored while locked; unlock verifies the password and restarts the clock', () async {
      await startWith({'autoLockMinutes': 1});
      clock.add(const Duration(minutes: 2));
      s.checkIdle();
      expect(s.locked, isTrue);
      s.touch();
      var calls = 0;
      final good = _api((r) {
        calls++;
        expect(r.url.path, endsWith('/me/verify-password'));
        return http.Response('{"ok":true}', 200);
      });
      await s.unlock(good, 'pw');
      expect(calls, 1);
      expect(s.locked, isFalse);
      expect(s.checkIdle(), isFalse);
    });

    test('wrong password keeps the lock', () async {
      await startWith({'autoLockMinutes': 1});
      s.lock();
      final bad = _api((r) => http.Response('{"error":"Mật khẩu không đúng"}', 403));
      await expectLater(s.unlock(bad, 'x'), throwsA(isA<ApiError>()));
      expect(s.locked, isTrue);
    });

    test('a busy feature (call) is never locked and counts as activity', () async {
      await startWith({'autoLockMinutes': 1});
      s.isBusy = () => true;
      clock.add(const Duration(minutes: 10));
      expect(s.checkIdle(), isFalse);
      s.isBusy = null;
      clock.add(const Duration(seconds: 59));
      expect(s.checkIdle(), isFalse, reason: 'idle clock restarted during the call');
      clock.add(const Duration(seconds: 2));
      expect(s.checkIdle(), isTrue);
    });

    test('lock when back from the background after hideLockSeconds', () async {
      await startWith({});
      await s.setHideLockSeconds(30);
      s.onLifecycle(AppLifecycleState.paused);
      clock.add(const Duration(seconds: 29));
      s.onLifecycle(AppLifecycleState.resumed);
      expect(s.locked, isFalse);
      s.onLifecycle(AppLifecycleState.paused);
      clock.add(const Duration(seconds: 30));
      s.onLifecycle(AppLifecycleState.resumed);
      expect(s.locked, isTrue);
    });

    test('hideLockSeconds = 0 never locks on return', () async {
      await startWith({});
      s.onLifecycle(AppLifecycleState.paused);
      clock.add(const Duration(hours: 5));
      s.onLifecycle(AppLifecycleState.resumed);
      expect(s.locked, isFalse);
    });

    test('blur only when policy allows AND user keeps it on (default policy: off)', () async {
      await startWith({});
      s.onLifecycle(AppLifecycleState.inactive);
      expect(s.veiled, isFalse);
      s.onLifecycle(AppLifecycleState.resumed);

      await startWith({'blur': true});
      expect(s.blurActive, isTrue);
      s.onLifecycle(AppLifecycleState.inactive);
      expect(s.veiled, isTrue);
      s.onLifecycle(AppLifecycleState.resumed);
      expect(s.veiled, isFalse);
      await s.setBlurOnHide(false);
      s.onLifecycle(AppLifecycleState.paused);
      expect(s.veiled, isFalse);
    });

    test('the lock survives an app restart; the idle clock too', () async {
      await startWith({'autoLockMinutes': 5});
      s.lock();
      await Future<void>.delayed(Duration.zero);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('xoso_locked'), isTrue);
      final again = PrivacyStore(clock: () => clock.now);
      await again.start(api);
      expect(again.locked, isTrue);
      expect(again.ready, isTrue);
    });

    test('settings persist per device', () async {
      await startWith({});
      await s.setAutoLockMinutes(15);
      await s.setHideLockSeconds(60);
      final again = PrivacyStore(clock: () => clock.now);
      await again.start(api);
      expect(again.autoLockMinutes, 15);
      expect(again.hideLockSeconds, 60);
    });

    test('policy fetch failure keeps the safe defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final st = PrivacyStore();
      await st.start(_api((r) => http.Response('{"error":"x"}', 500)));
      expect(st.screenshotGuardOn, isTrue);
      expect(st.blurActive, isFalse);
      expect(st.autoLockMinutes, 0);
    });

    test('stop clears lock state', () async {
      await startWith({});
      s.lock();
      await s.stop();
      expect(s.locked, isFalse);
      expect(s.ready, isFalse);
    });
  });

  group('MeProfile', () {
    test('parses GET /me', () {
      final m = MeProfile.fromJson({
        'name': 'An',
        'username': 'an',
        'role': 'user',
        'hasSecondPassword': true,
        'hasWipePassword': false,
        'hasRecoveryCode': true,
        'package': {'type': 'trial', 'label': 'Dùng thử 30 ngày', 'expiresAt': '2026-11-01T00:00:00.000Z', 'isActive': true},
        'stats': {'total': 1000, 'used': 12, 'remaining': 988},
      });
      expect(m.hasSecondPassword, isTrue);
      expect(m.hasWipePassword, isFalse);
      expect(m.packageActive, isTrue);
      expect(m.quotaUsed, 12);
      expect(m.unlimited, isFalse);
      expect(MeProfile.fromJson({'name': 'x', 'username': 'y', 'stats': {'total': 999999999, 'used': 0}}).unlimited, isTrue);
    });
  });

  group('changePasswordProblem', () {
    test('rules', () {
      expect(changePasswordProblem(['', 'a', 'a']), isNotNull);
      expect(changePasswordProblem(['c', 'a', 'b']), contains('không khớp'));
      expect(changePasswordProblem(['c', 'a' * 73, 'a' * 73]), contains('72'));
      expect(changePasswordProblem(['c', 'a', 'a']), isNull);
    });
  });

  group('vietQrUrl', () {
    final bank = {'bankBin': '970436', 'bankAccountNumber': '0123456789', 'bankAccountHolder': 'NGUYEN VAN A'};
    test('built like the web app', () {
      final url = vietQrUrl(bank: bank, pending: {'amount': 199000, 'referenceCode': 'MB123', 'packageType': '1m'}, username: 'an')!;
      expect(url, startsWith('https://api.vietqr.io/image/970436-0123456789-compact2.png?'));
      final q = Uri.parse(url).queryParameters;
      expect(q, {'amount': '199000', 'addInfo': 'MB123', 'accountName': 'NGUYEN VAN A'});
      expect(url, contains('accountName=NGUYEN+VAN+A'));
    });
    test('null without bank bin/account or pending request', () {
      expect(vietQrUrl(bank: bank, pending: null, username: 'an'), isNull);
      expect(vietQrUrl(bank: {'bankBin': null, 'bankAccountNumber': '1'}, pending: {'amount': 1}, username: 'an'), isNull);
    });
    test('falls back to username + package when there is no reference', () {
      final url = vietQrUrl(bank: bank, pending: {'amount': 5, 'packageType': '1m'}, username: 'an')!;
      expect(Uri.parse(url).queryParameters['addInfo'], 'an 1m');
    });
  });

  group('stats logic', () {
    test('toNumber follows the web parseFloat convention', () {
      expect(toNumber('1.5'), 1.5);
      expect(toNumber('-20'), -20);
      expect(toNumber('1,000'), 1000);
      expect(toNumber('12abc'), 12);
      expect(toNumber(''), 0);
      expect(toNumber(null), 0);
      expect(toNumber('abc'), 0);
      expect(toNumber('-'), 0);
    });
    test('period keys are continuous and end at today', () {
      final now = DateTime(2026, 3, 2);
      final d = periodKeys(StatUnit.day, now);
      expect(d.length, 30);
      expect(d.last, '2026-03-02');
      expect(d[d.length - 3], '2026-02-28');
      final m = periodKeys(StatUnit.month, now);
      expect(m.length, 12);
      expect(m.first, '2025-04');
      expect(m.last, '2026-03');
      expect(periodKeys(StatUnit.year, now), ['2022', '2023', '2024', '2025', '2026']);
    });
    test('series and totals', () {
      const es = [
        StatEntry(customerName: 'A', entryDate: '2026-03-02', score: '100', result: '30'),
        StatEntry(customerName: 'A', entryDate: '2026-03-02T05:00:00Z', score: '50', result: ''),
        StatEntry(customerName: '', entryDate: '2026-03-01', score: '', result: '20'),
        StatEntry(customerName: 'B', entryDate: '2000-01-01', score: '999', result: '0'),
      ];
      final now = DateTime(2026, 3, 2);
      final profit = buildSeries(es, StatUnit.day, StatMetric.profit, now);
      expect(profit.last.value, 120);
      expect(profit[profit.length - 2].value, -20);
      expect(profit.last.label, '02/03');
      expect(profit.last.full, '02/03/2026');
      expect(buildSeries(es, StatUnit.month, StatMetric.vao, now).last.value, 150);
      expect(buildSeries(es, StatUnit.year, StatMetric.ra, now).last.value, 50);
      final t = computeTotals(['Z'], es);
      expect(t.customers, 4, reason: 'Z + A + (Không tên) + B');
      expect(t.plays, 4);
      expect(t.vao, 1149);
      expect(t.profit, 1149 - 50);
    });
    test('shortNum', () {
      expect(shortNum(1500), '1,5k');
      expect(shortNum(2000000), '2tr');
      expect(shortNum(-3000), '-3k');
      expect(shortNum(3200000000), '3,2 tỷ');
      expect(shortNum(12), '12');
      expect(shortNum(0), '0');
    });
    test('ISO weeks start on Monday', () {
      // 2026-03-02 is a Monday; 2026-03-01 (Sunday) belongs to the week of 2026-02-23.
      expect(keyOf('2026-03-02', StatUnit.week), '2026-03-02');
      expect(keyOf('2026-03-01', StatUnit.week), '2026-02-23');
      expect(keyOf('2026-03-08T10:00:00Z', StatUnit.week), '2026-03-02');
      expect(keyOf('bad', StatUnit.week), '');
      expect(isoWeek(DateTime.utc(2026, 1, 1)), 1);
      expect(isoWeek(DateTime.utc(2024, 12, 30)), 1);
      expect(isoWeek(DateTime.utc(2021, 1, 3)), 53);
      final k = periodKeys(StatUnit.week, DateTime(2026, 3, 4));
      expect(k.length, 12);
      expect(k.last, '2026-03-02');
      expect(k[10], '2026-02-23');
      expect(labelOf('2026-03-02', StatUnit.week), '02/03');
      expect(fullLabelOf('2026-02-23', StatUnit.week), 'Tuần 9 (23/02 – 01/03/2026)');
    });
    test('series by week, month, year with empty periods = 0', () {
      const es = [
        StatEntry(customerName: 'A', entryDate: '2026-03-01', score: '10', result: '4'),
        StatEntry(customerName: 'A', entryDate: '2026-03-02', score: '100', result: '30'),
        StatEntry(customerName: 'A', entryDate: '2026-03-08', score: '1', result: ''),
      ];
      final now = DateTime(2026, 3, 4);
      final w = buildSeries(es, StatUnit.week, StatMetric.vao, now);
      expect(w.map((p) => p.key).last, '2026-03-02');
      expect(w.last.value, 101);
      expect(w[w.length - 2].value, 10);
      expect(w.first.value, 0);
      expect(buildSeries(es, StatUnit.week, StatMetric.profit, now).last.value, 71);
      final m = buildSeries(es, StatUnit.month, StatMetric.ra, now);
      expect(m.length, 12);
      expect(m.last.label, '03/26');
      expect(m.last.full, 'Tháng 03/2026');
      expect(m.last.value, 34);
      expect(m.first.value, 0);
      expect(buildSeries(es, StatUnit.year, StatMetric.vao, now).map((p) => p.label).toList(), ['2022', '2023', '2024', '2025', '2026']);
      expect(buildSeries(es, StatUnit.year, StatMetric.vao, now).last.full, 'Năm 2026');
    });
    test('previous window and percent change', () {
      const es = [
        StatEntry(customerName: 'A', entryDate: '2026-03-02', score: '100', result: ''),
        StatEntry(customerName: 'A', entryDate: '2026-01-20', score: '50', result: ''),
      ];
      final now = DateTime(2026, 3, 2);
      final cur = sumOf(buildSeries(es, StatUnit.day, StatMetric.vao, now));
      final prev = sumOf(buildSeries(es, StatUnit.day, StatMetric.vao, previousAnchor(StatUnit.day, now)));
      expect(cur, 100);
      expect(prev, 50);
      expect(percentChange(cur, prev), 100);
      expect(percentChange(5, 0), isNull);
      expect(percentChange(-50, -100), 50);
      expect(previousAnchor(StatUnit.month, now).month, 3);
      expect(previousAnchor(StatUnit.month, now).year, 2025);
    });
    test('label step and indices never overlap, keep first and last', () {
      expect(labelStep(30, 300, 30), 4);
      expect(labelStep(5, 300, 30), 1);
      for (final n in [5, 12, 30]) {
        for (final step in [1, 2, 3, 4, 7]) {
          final idx = labelIndices(n, step);
          expect(idx.first, 0);
          expect(idx.last, n - 1);
          for (var i = 1; i < idx.length; i++) {
            expect(idx[i] - idx[i - 1] >= (step / 2).floor().clamp(1, 99), isTrue, reason: 'n=$n step=$step $idx');
          }
        }
      }
    });
    test('niceAxis contains zero and data, with round ticks', () {
      final a = niceAxis(-130, 870);
      expect(a.min <= -130 && a.max >= 870, isTrue);
      expect(a.ticks.contains(0.0), isTrue);
      expect(a.ticks.first, a.min);
      expect(a.ticks.last, a.max);
      final z = niceAxis(0, 0);
      expect(z.max, 1);
      final p = niceAxis(0, 1234567);
      expect(p.min, 0);
      expect(p.max, 1500000);
    });
  });
}
