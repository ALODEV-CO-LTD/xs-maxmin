// Chạy: cd web-next && npm test
// The SAME table is asserted in backend/test/scoring_rates_test.dart and app/test/default_rates_test.dart: the defaults of every
// kind must be identical in the backend, the app and the web. [kind, price Bắc, payout Bắc, price Nam/Trung, payout Nam/Trung]
import test from 'node:test'
import assert from 'node:assert/strict'
import { DEFAULT_RATES } from '../src/lib/scoringConfig.js'

const TABLE = [
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
]

test('default rates: every kind has a price and a payout, identical in all three code bases', () => {
  for (const [kind, priceMb, payoutMb, priceMn, payoutMn] of TABLE) {
    const mb = DEFAULT_RATES[`${kind}@mb`]
    assert.deepEqual([mb.price, mb.payout], [priceMb, payoutMb], `${kind} Bắc`)
    for (const region of ['mt', 'mn']) {
      const c = DEFAULT_RATES[`${kind}@${region}`]
      assert.deepEqual([c.price, c.payout], [priceMn, payoutMn], `${kind} ${region}`)
    }
  }
})
