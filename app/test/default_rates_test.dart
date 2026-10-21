import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/core/scoring_config.dart';

// The SAME table is asserted in backend/test/scoring_rates_test.dart and web-next/tests/defaultRates.test.mjs: the defaults of
// every kind must be identical in the backend, the app and the web. [kind, price Bắc, payout Bắc, price Nam/Trung, payout Nam/Trung]
void main() {
  test('default rates: every kind has a price and a payout, identical in all three code bases', () {
    const table = [
    ['lo', 21600, 70000, 12600, 70000],
    ['lo3', 18400, 500000, 11900, 500000],
    ['lo4', 16000, 5000000, 11200, 5000000],
    ['dau', 1000, 70000, 1000, 70000],
    ['duoi', 1000, 70000, 1000, 70000],
    ['cang3', 12600, 500000, 12600, 500000],
    ['cang4', 12600, 5000000, 12600, 5000000],
    ['xien2', 21600, 430000, 12600, 250000],
    ['xien3', 21600, 2590000, 12600, 1500000],
    ['xien4', 21600, 8640000, 12600, 5000000],
    ['truot4', 21600, 225000, 12600, 90000],
    ['truot8', 21600, 1350000, 12600, 350000],
    ['truot10', 21600, 2800000, 12600, 630000],
    ['tai_xiu', 1000, 1900, 1000, 1900],
    ['chan_le', 1000, 1900, 1000, 1900],
    ];
    for (final r in table) {
      final mb = defaultRates['${r[0]}@mb'] as Map;
      expect([mb['price'], mb['payout']], [r[1], r[2]], reason: '${r[0]} Bắc');
      for (final region in ['mt', 'mn']) {
        final c = defaultRates['${r[0]}@$region'] as Map;
        expect([c['price'], c['payout']], [r[3], r[4]], reason: '${r[0]} $region');
      }
    }
  });
}
