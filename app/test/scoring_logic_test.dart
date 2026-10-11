import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/features/scoring/entry_model.dart';
import 'package:mamba_app/features/scoring/scoring_days.dart';
import 'package:mamba_app/features/scoring/scoring_logic.dart';

import 'scoring_fixtures.dart';

Entry entry(String value, String score, {String? bet = 'lo', String? station = 'mn-dongnai', String date = '2026-10-07', String name = 'An', String id = 'e1'}) =>
    Entry(id: id, customerName: name, entryDate: date, value: value, score: score, betType: bet, station: station);

LotteryResult mnResult({List<String> tam = const ['00'], String db = '123456'}) => {
      'dacBiet': db,
      'giaiNhat': '11111',
      'giaiNhi': ['22222'],
      'giaiBa': ['33333', '44444'],
      'giaiTu': ['10001', '10002', '10003', '10004', '10005', '10006', '10007'],
      'giaiNam': ['5555'],
      'giaiSau': ['6666', '7777', '8888'],
      'giaiBay': ['999'],
      'giaiTam': tam,
    };

final loConfig = {'rate': 3.5, 'tiers': allBaseTiers, 'digits': 2};

void main() {
  group('helpers', () {
    test('normDigits keeps the last N digits and pads', () {
      expect(normDigits('1234', 2), '34');
      expect(normDigits('7', 2), '07');
      expect(normDigits('abc', 2), '');
      expect(normDigits('12-34', 3), '234');
    });
    test('toNumber / numToString', () {
      expect(toNumber('1.200'), 1.2);
      expect(toNumber('10 điểm'), 10);
      expect(toNumber(null), 0);
      expect(toNumber('abc'), 0);
      expect(numToString(805000.0), '805000');
      expect(numToString(12.5), '12.5');
      expect(numToString(0), '0');
    });
  });

  group('entryDetail', () {
    test('lô 10 điểm, tỉ lệ 3.5, 1 hit = 35 điểm ra = 805.000đ at 23.000đ/điểm', () {
      final r = mnResult(tam: const ['47']);
      final d = entryDetail(entry('47', '10'), r, loConfig);
      expect(d.bets, ['47']);
      expect(d.perNumber.single.hits, 1);
      expect(d.out, 35);
      final s = summarize(
        [DayEntries('2026-10-07', [entry('47', '10', station: 'mn-dongnai')])],
        {'lo': loConfig, 'de': {'rate': 70, 'tiers': ['dacBiet'], 'digits': 2}},
        null,
        (date, st) => st == 'mn-dongnai' ? r : null,
        testStations(),
      );
      expect(s.wonMoney, 805000);
      expect(s.sentMoney, 230000); // 10 điểm x 23.000
      expect(s.sentPoints, 10);
      expect(s.remaining, 230000 - 805000);
      expect(s.wonLots, 1);
      expect(s.won.single.number, '47');
    });

    test('several numbers and repeated hits add up', () {
      // 47 appears twice among the checked prizes (G8 and last two digits of a 5-digit prize)
      final r = mnResult(tam: const ['47'])..['giaiTu'] = ['10047', '10002', '10003', '10004', '10005', '10006', '10007'];
      final d = entryDetail(entry('47,12 08', '2'), r, loConfig);
      expect(d.bets, ['47', '12', '08']);
      expect(d.lots, 3);
      expect(d.perNumber.map((e) => e.hits), [2, 0, 0]);
      expect(d.out, 2 * 3.5 * 2);
    });

    test('no result -> 0, no numbers -> one lot', () {
      final d = entryDetail(entry('', '5'), null, loConfig);
      expect(d.out, 0);
      expect(d.lots, 1);
    });

    test('đề checks only the special prize, money unit: điểm ra = tiền', () {
      final de = {'rate': 70, 'tiers': ['dacBiet'], 'digits': 2};
      final r = mnResult(db: '123456', tam: const ['56']);
      final hit = entryDetail(entry('56', '100000', bet: 'de'), r, de);
      expect(hit.out, 7000000);
      final s = summarize([DayEntries('2026-10-07', [entry('56', '100000', bet: 'de')])], {'de': de}, null, (d, st) => st == 'mn-dongnai' ? r : null, testStations());
      expect(s.wonMoney, 7000000);
      expect(s.sentMoney, 100000);
      expect(s.sentPoints, 0);
      // 12 is in no special prize
      expect(entryDetail(entry('12', '100000', bet: 'de'), r, de).out, 0);
    });

    test('tiers: "all eight" includes giải tám, an explicit list does not unless it has giaiTam', () {
      final r = mnResult(tam: const ['47']);
      expect(numbersForTiers(r, allBaseTiers), contains('47'));
      expect(numbersForTiers(r, ['dacBiet', 'giaiNhat']), isNot(contains('47')));
      expect(numbersForTiers(r, ['giaiTam']), ['47']);
      expect(numbersForTiers(r, ['dacBiet', 'giaiTam']), ['123456', '47']);
      // Miền Bắc has no giaiTam: nothing extra
      expect(numbersForTiers({'dacBiet': '12345'}, allBaseTiers), ['12345']);
    });

    test('digits setting: 3 càng compares the last three digits', () {
      final cfg = {'rate': 600, 'tiers': ['dacBiet'], 'digits': 3};
      final d = entryDetail(entry('456', '1', bet: '3cang'), mnResult(db: '123456'), cfg);
      expect(d.bets, ['456']);
      expect(d.out, 600);
    });
  });

  group('summarize', () {
    final account = {
      'lo': {'rate': 20, 'tiers': allBaseTiers, 'digits': 2},
      'de': {'rate': 70, 'tiers': ['dacBiet'], 'digits': 2},
    };

    test('region-only config wins for its region and the customer config for the customer', () {
      final customer = {
        'lo@mn': {'rate': 3.5, 'tiers': allBaseTiers, 'digits': 2},
      };
      final r = mnResult(tam: const ['47']);
      final mn = summarize([DayEntries('2026-10-07', [entry('47', '10')])], account, customer, (d, st) => r, testStations());
      expect(mn.wonMoney, 805000); // 10 x 3.5 x 23.000
      final mb = summarize(
        [DayEntries('2026-10-07', [entry('47', '10', station: 'mb')])],
        account,
        customer,
        (d, st) => {'dacBiet': '12347', 'giaiNhat': '00000'},
        testStations(),
      );
      expect(mb.wonMoney, 10 * 20 * 23000); // Miền Bắc keeps the account rate 20
    });

    test('a disabled customer type falls back to the account config', () {
      final customer = {'lo': {'disabled': true}};
      final r = mnResult(tam: const ['47']);
      final s = summarize([DayEntries('2026-10-07', [entry('47', '10')])], account, customer, (d, st) => r, testStations());
      expect(s.wonMoney, 10 * 20 * 23000);
    });

    test('an entry on a region counts once per station drawing that day', () {
      final r = mnResult(tam: const ['47']);
      final e = entry('47', '10', station: 'mn');
      final s = summarize([DayEntries('2026-10-07', [e])], account, null, (d, st) => st == 'mn-cantho' ? r : null, testStations());
      // three stations: stake counted three times, only Cần Thơ has a result (and hits)
      expect(s.sentLots, 3);
      expect(s.sentMoney, 3 * 230000);
      expect(s.pendingLots, 2);
      expect(s.settledLots, 1);
      expect(s.won.single.station, 'mn-cantho');
      expect(s.remaining, 230000 - 10 * 20 * 23000);
    });

    test('days without a result are pending and not part of "còn lại"', () {
      final r = mnResult();
      final days = [
        DayEntries('2026-10-07', [entry('47', '10', id: 'a')]),
        DayEntries('2026-10-06', [entry('12', '5', id: 'b', date: '2026-10-06')]),
      ];
      final s = summarize(days, account, null, (d, st) => d == '2026-10-07' ? r : null, testStations());
      expect(s.sentLots, 2);
      expect(s.settledLots, 1);
      expect(s.pendingLots, 1);
      expect(s.pendingMoney, 5 * 23000);
      expect(s.remaining, 230000);
      expect(s.byType.single.key, 'lo');
      expect(s.byType.single.lots, 2);
    });

    test('winners are listed newest day first, then biggest money', () {
      final r = mnResult(tam: const ['47', '12']);
      final days = [
        DayEntries('2026-10-06', [entry('47', '1', date: '2026-10-06', id: 'x')]),
        DayEntries('2026-10-07', [entry('47', '1', id: 'y'), entry('12', '9', id: 'z')]),
      ];
      final s = summarize(days, account, null, (d, st) => r, testStations());
      expect(s.won.map((w) => '${w.date}/${w.number}'), ['2026-10-07/12', '2026-10-07/47', '2026-10-06/47']);
    });

    test('entryOutTotal is null without results and sums the stations that have one', () {
      final st = testStations();
      final r = mnResult(tam: const ['47']);
      double? out(String station, LotteryResult? Function(String) f) =>
          entryOutTotal(entry: entry('47', '10', station: station), stations: st, accountRates: account, customerRates: null, resultOf: f);
      expect(out('mn-dongnai', (_) => null), isNull);
      expect(out('mn-dongnai', (_) => r), 10 * 20 * 1);
      expect(out('mn', (s) => s == 'mn-cantho' || s == 'mn-soctrang' ? r : null), 2 * 10 * 20);
    });
  });

  group('days', () {
    test('shiftIso / dayLabel', () {
      expect(shiftIso('2026-10-31', 1), '2026-11-01');
      expect(shiftIso('2026-03-01', -1), '2026-02-28');
      final l = dayLabel('2026-10-11');
      expect(l.date, '11/10/2026');
      expect(l.weekday, 'Chủ nhật');
    });

    test('rangeForPreset', () {
      expect(rangeForPreset('today', '2026-10-11'), (from: '2026-10-11', to: '2026-10-11'));
      expect(rangeForPreset('7', '2026-10-11'), (from: '2026-10-05', to: '2026-10-11'));
      expect(rangeForPreset('30', '2026-10-11'), (from: '2026-09-12', to: '2026-10-11'));
      expect(rangeForPreset('all', '2026-10-11'), (from: '', to: ''));
      expect(rangeForPreset('custom', '2026-10-11'), isNull);
    });

    test('groupDays filters by customer, region and range and sorts newest first', () {
      final st = testStations();
      final all = [
        entry('1', '1', id: '1', date: '2026-10-05', station: 'mb'),
        entry('2', '1', id: '2', date: '2026-10-07'),
        entry('3', '1', id: '3', date: '2026-10-07', station: 'mn'),
        entry('4', '1', id: '4', date: '2026-10-06', name: 'Bình'),
        entry('5', '1', id: '5', date: '2026-10-01', station: 'mt-hue'),
      ];
      final g = groupDays(all, customer: 'An', stations: st);
      expect(g.map((d) => d.date), ['2026-10-07', '2026-10-05', '2026-10-01']);
      expect(g.first.entries.length, 2);
      expect(groupDays(all, customer: 'An', stations: st, region: 'mn').map((d) => d.date), ['2026-10-07']);
      expect(groupDays(all, customer: 'An', stations: st, region: 'mt').map((d) => d.date), ['2026-10-01']);
      expect(groupDays(all, customer: 'An', stations: st, from: '2026-10-05', to: '2026-10-06').map((d) => d.date), ['2026-10-05']);
    });

    test('lotteryState: yes / partial / no / unknown', () {
      final st = testStations();
      final list = [entry('1', '1', station: 'mn')]; // three stations
      final cache = <String, LotteryResult?>{};
      expect(lotteryState('2026-10-07', list, st, cache), isNull);
      cache['2026-10-07|mn-dongnai'] = null;
      cache['2026-10-07|mn-cantho'] = null;
      expect(lotteryState('2026-10-07', list, st, cache), isNull); // one still unknown
      cache['2026-10-07|mn-soctrang'] = null;
      expect(lotteryState('2026-10-07', list, st, cache), 'no');
      cache['2026-10-07|mn-cantho'] = {'dacBiet': '1'};
      expect(lotteryState('2026-10-07', list, st, cache), 'partial');
      cache['2026-10-07|mn-dongnai'] = {'dacBiet': '1'};
      cache['2026-10-07|mn-soctrang'] = {'dacBiet': '1'};
      expect(lotteryState('2026-10-07', list, st, cache), 'yes');
    });
  });
}
