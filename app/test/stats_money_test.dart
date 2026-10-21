// Tổng quan in money: same figures as Tính điểm, on the real demo account's entries and draws of 11/10 and 18/10.
import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/core/scoring_config.dart';
import 'package:mamba_app/features/account/stats_logic.dart';
import 'package:mamba_app/features/account/stats_money.dart';
import 'package:mamba_app/features/scoring/entry_model.dart';
import 'package:mamba_app/features/scoring/scoring_logic.dart';

import 'scoring_fixtures.dart';

Entry e(String id, String date, String type, String value, String score) =>
    Entry(id: id, customerName: 'Anh Dũng', entryDate: date, value: value, score: score, result: '0', betType: type, station: 'mb');

final draw11 = <String, dynamic>{
  'dacBiet': '24483', 'giaiNhat': '48799', 'giaiNhi': ['63906', '22370'], 'giaiBa': ['92151', '85709', '96557', '45967', '17050', '35145'],
  'giaiTu': ['2719', '2206', '1575', '1644'], 'giaiNam': ['8754', '3913', '4102', '5685', '9938', '3837'], 'giaiSau': ['294', '075', '609'], 'giaiBay': ['84', '65', '87', '63'],
};
final draw18 = <String, dynamic>{
  'dacBiet': '38115', 'giaiNhat': '97733', 'giaiNhi': ['21143', '52941'], 'giaiBa': ['12914', '26998', '10224', '63551', '85741', '77963'],
  'giaiTu': ['7663', '1599', '9528', '3603'], 'giaiNam': ['6707', '5085', '3629', '5755', '2682', '1939'], 'giaiSau': ['455', '297', '980'], 'giaiBay': ['85', '67', '16', '92'],
};

void main() {
  final entries = [
    e('1', '2026-10-11', 'lo', '12', '1321321'),
    e('2', '2026-10-11', 'duoi', '11', '132323232'),
    e('3', '2026-10-11', 'cang3', '232', '2111111'),
    e('4', '2026-10-18', 'lo', '22', '66666'),
    e('5', '2026-10-18', 'xien3', '44 23 24', '50'),
    e('6', '2026-10-18', 'xien2', '27 10', '100'),
    e('7', '2026-10-18', 'xien2', '80 90', '100'),
    e('8', '2026-10-18', 'lo', '40', '20'),
  ];
  const customers = [CustomerRec(id: 'c1', name: 'Anh Dũng')];
  LotteryResult? onlyThese(String d, String s) => s != 'mb' ? null : (d == '2026-10-11' ? draw11 : d == '2026-10-18' ? draw18 : null);

  MoneyStats stats(LotteryResult? Function(String, String) get, [List<Entry>? list]) =>
      computeMoneyStats(entries: list ?? entries, customers: customers, accountRates: defaultRates, stations: testStations(), getResult: get);

  test('same money as Tính điểm: sent, won and profit per day (nobody won)', () {
    final m = stats(onlyThese);
    final direct = summarize([DayEntries('2026-10-18', entries.where((x) => x.entryDate == '2026-10-18').toList())], defaultRates, null, onlyThese, testStations());
    expect(m.byDate['2026-10-18']!.sent, direct.sentMoney);
    expect(m.byDate['2026-10-18']!.sent, greaterThan(1e9)); // lô 66.666 điểm x 23.000 đ: hơn 1 tỷ
    expect(m.won, 0);
    expect(m.pending, 0);
    expect(m.profit, m.sent);
    expect(m.plays, 8);
    expect(m.customerNames, {'Anh Dũng'});
  });

  test('tiền theo từng khách khớp với tổng của Tổng quan', () {
    final other = Entry(id: '9', customerName: 'Chị Lan', entryDate: '2026-10-11', value: '12', score: '10', result: '0', betType: 'lo', station: 'mb');
    final list = [...entries, other];
    final total = stats(onlyThese, list);
    final by = computeMoneyByCustomer(entries: list, customers: customers, accountRates: defaultRates, stations: testStations(), getResult: onlyThese);
    expect(by.keys.toSet(), {'Anh Dũng', 'Chị Lan'});
    expect(by['Anh Dũng']!.sent + by['Chị Lan']!.sent, total.sent);
    expect(by['Anh Dũng']!.won + by['Chị Lan']!.won, total.won);
    expect(by['Anh Dũng']!.profit + by['Chị Lan']!.profit, total.profit);
    expect(by['Chị Lan']!.sent, 216000); // 10 điểm lô x giá mặc định 21.600 đ/điểm
  });

  test('a day with no result yet is "chưa tính": never counted as profit', () {
    final m = stats((d, s) => d == '2026-10-11' && s == 'mb' ? draw11 : null);
    expect(m.byDate['2026-10-18']!.pending, m.byDate['2026-10-18']!.sent);
    expect(m.byDate['2026-10-18']!.profit, 0);
    expect(m.pendingLots, greaterThan(0));
    expect(m.profit, m.byDate['2026-10-11']!.settled);
  });

  test('a winning number is paid out and lowers the profit', () {
    final win = [e('w', '2026-10-18', 'lo', '15', '10')]; // 15 is the last two digits of 38115 (special prize) and others
    final m = stats(onlyThese, win);
    expect(m.won, greaterThan(0));
    expect(m.profit, m.settled - m.won);
    expect(m.profit, lessThan(m.sent));
  });

  test('series: tiền gửi / tiền trúng / lợi nhuận per day, 0 on empty days', () {
    final m = stats(onlyThese);
    final now = DateTime.utc(2026, 10, 19);
    final profit = buildMoneySeries(m.byDate, StatUnit.day, StatMetric.profit, now);
    expect(profit.length, 30);
    expect(profit.last.key, '2026-10-19');
    expect(profit.last.value, 0);
    expect(profit.firstWhere((p) => p.key == '2026-10-11').value, m.byDate['2026-10-11']!.profit);
    final month = buildMoneySeries(m.byDate, StatUnit.month, StatMetric.vao, now);
    expect(month.last.value, m.sent);
  });
}
