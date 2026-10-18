// Audit of the money formulas against a REAL result (Miền Bắc 12/10/2026, copied from the database) and numbers worked out by hand,
// independently of the engine: the expected figures below come from counting the two-digit tails of the 27 prizes yourself.
import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/core/scoring_config.dart';
import 'package:mamba_app/features/scoring/entry_model.dart';
import 'package:mamba_app/features/scoring/scoring_logic.dart';

// Miền Bắc 12/10/2026. The 27 two-digit tails, prize by prize:
// ĐB 23432->32 | G1 76877->77 | G2 58145->45, 35342->42 | G3 23887->87 38->38? (see below) ...
final LotteryResult mb = {
  'dacBiet': '23432',
  'giaiNhat': '76877',
  'giaiNhi': ['58145', '35342'],
  'giaiBa': ['23887', '23638', '53252', '26261', '62365', '36485'],
  'giaiTu': ['2637', '4646', '6262', '2642'],
  'giaiNam': ['5235', '2768', '0967', '2356', '3658', '7585'],
  'giaiSau': ['636', '654', '745'],
  'giaiBay': ['34', '23', '22', '55'],
};

/// Tails counted by hand (27 numbers): 32 | 77 | 45 42 | 87 38 52 61 65 85 | 37 46 62 42 | 35 68 67 56 58 85 | 36 54 45 | 34 23 22 55
const hand = {'32': 1, '77': 1, '45': 2, '42': 2, '87': 1, '38': 1, '52': 1, '61': 1, '65': 1, '85': 2, '37': 1, '46': 1, '62': 1, '35': 1, '68': 1, '67': 1, '56': 1, '58': 1, '36': 1, '54': 1, '34': 1, '23': 1, '22': 1, '55': 1};

Entry e(String value, String score, String bet) => Entry(id: 'x', customerName: 'An', entryDate: '2026-10-12', value: value, score: score, betType: bet, station: 'mb');

void main() {
  test('the hand count is 27 prizes', () {
    expect(hand.values.fold<int>(0, (a, b) => a + b), 27);
  });

  Cfg cfg(String type) => effectiveConfig(defaultRates, null, type, 'mb');

  test('lô (bao lô 2 số): hits = how many of the 27 tails equal the number; win = điểm x hits x payout; stake = điểm x price', () {
    final c = cfg('lo');
    for (final n in ['42', '85', '45', '32', '99', '00']) {
      final d = entryDetail(e(n, '10', 'lo'), mb, c);
      final want = hand[n] ?? 0;
      expect(d.totalHits, want, reason: 'lô $n');
      expect(winMoney('lo', c, 10, d.totalHits), 10 * want * numOf(c['payout']), reason: 'tiền trúng lô $n');
    }
    expect(stakeMoney('lo', c, 10), 10 * numOf(c['price']));
  });

  test('đề: only the last two digits of the special prize (32) win', () {
    final c = cfg('de');
    expect(entryDetail(e('32', '5', 'de'), mb, c).totalHits, 1);
    expect(entryDetail(e('77', '5', 'de'), mb, c).totalHits, 0); // 77 is prize 1, not the special prize
    // the default "de" row is the older rate model (rate 70, no money model): out = điểm x rate x hits
    expect(entryDetail(e('32', '5', 'de'), mb, c).out, 5 * 70); // 5 điểm x rate 70 x 1 hit = 350 điểm ra
  });

  test('xiên 2: wins ONCE when both numbers are among the 27 tails, however many times they appear', () {
    final c = cfg('xien2');
    final both = entryDetail(e('42 85', '10', 'xien2'), mb, c); // 42 appears twice and 85 twice: still one win
    expect(both.totalHits, 1);
    expect(winMoney('xien2', c, 10, both.totalHits), 10 * numOf(c['payout']));
    expect(entryDetail(e('42 99', '10', 'xien2'), mb, c).totalHits, 0); // 99 is not there
    expect(entryDetail(e('42 85', '10', 'xien2'), mb, c).lots, 2); // two numbers in the bet (stake = điểm x giá x lots)
  });

  test('xiên 3: needs all three', () {
    final c = cfg('xien3');
    expect(entryDetail(e('42 85 32', '10', 'xien3'), mb, c).totalHits, 1);
    expect(entryDetail(e('42 85 99', '10', 'xien3'), mb, c).totalHits, 0);
  });

  test('3 càng: last three digits of the special prize only (432); 4 càng the last four (3432)', () {
    expect(entryDetail(e('432', '1', 'cang3'), mb, cfg('cang3')).totalHits, 1);
    expect(entryDetail(e('632', '1', 'cang3'), mb, cfg('cang3')).totalHits, 0);
    expect(entryDetail(e('3432', '1', 'cang4'), mb, cfg('cang4')).totalHits, 1);
  });

  test('đầu / đuôi: đầu = the 2 last digits of the 7th prize numbers (first digits rule of the config); đuôi = special prize tail', () {
    final duoi = cfg('duoi');
    expect(entryDetail(e('32', '2', 'duoi'), mb, duoi).totalHits, 1);
    expect(entryDetail(e('33', '2', 'duoi'), mb, duoi).totalHits, 0);
  });
}
