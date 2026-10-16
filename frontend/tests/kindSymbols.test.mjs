// Ký hiệu do khách đặt trong bảng cấu hình -> bộ đọc tin nhắn (cần cú pháp liền của messageParser.js).
import test from 'node:test'
import assert from 'node:assert/strict'
import { DEFAULT_RATES } from '../src/scoringConfig.js'

import { parseMessage } from '../src/messageParser.js'
import { kindSymbolsFor } from '../src/scoringConfig.js'
test('ký hiệu do khách đặt trong bảng được bộ đọc tin nhắn hiểu', () => {
  const WIDE = ['lo', 'dau', 'duoi', 'cang3', 'cang4', 'xien2', 'xien3', 'xien4']
  const rates = { ...DEFAULT_RATES, 'lo@mn': { ...DEFAULT_RATES['lo@mn'], symbols: ['bl'] } }
  const kindSymbols = kindSymbolsFor(rates, null, 'mn')
  assert.deepEqual(kindSymbols, { lo: ['bl'] })
  const own = parseMessage('20bl100', { betTypes: WIDE, kindSymbols }).rows.map((r) => `${r.type}:${r.value}@${r.score}`)
  assert.deepEqual(own, ['lo:20@100'])
})
