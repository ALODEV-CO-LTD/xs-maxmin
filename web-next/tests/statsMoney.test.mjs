// Chạy: cd frontend && npm test
// Thống kê bằng TIỀN, cùng số liệu với app (app/test/stats_money_test.dart): tài khoản demo "2", kết quả ngày 11/10 và 18/10.
import test from 'node:test'
import assert from 'node:assert/strict'
import { moneyByDate, moneyTotals, neededResults, pseudoEntries } from '../src/lib/statsMoney.js'
import { buildSeries } from '../src/lib/statsSeries.js'
import { summarize } from '../src/lib/scoringSummary.js'
import { DEFAULT_RATES } from '../src/lib/scoringConfig.js'

const draw11 = { dacBiet: '24483', giaiNhat: '48799', giaiNhi: ['63906', '22370'], giaiBa: ['92151', '85709', '96557', '45967', '17050', '35145'], giaiTu: ['2719', '2206', '1575', '1644'], giaiNam: ['8754', '3913', '4102', '5685', '9938', '3837'], giaiSau: ['294', '075', '609'], giaiBay: ['84', '65', '87', '63'] }
const draw18 = { dacBiet: '38115', giaiNhat: '97733', giaiNhi: ['21143', '52941'], giaiBa: ['12914', '26998', '10224', '63551', '85741', '77963'], giaiTu: ['7663', '1599', '9528', '3603'], giaiNam: ['6707', '5085', '3629', '5755', '2682', '1939'], giaiSau: ['455', '297', '980'], giaiBay: ['85', '67', '16', '92'] }
const e = (id, entryDate, betType, value, score) => ({ id, customerName: 'Anh Dũng', entryDate, value, score, result: '0', betType, station: 'mb' })
const entries = [
  e('1', '2026-10-11', 'lo', '12', '1321321'),
  e('2', '2026-10-11', 'duoi', '11', '132323232'),
  e('3', '2026-10-11', 'cang3', '232', '2111111'),
  e('4', '2026-10-18', 'lo', '22', '66666'),
  e('5', '2026-10-18', 'xien3', '44 23 24', '50'),
  e('6', '2026-10-18', 'xien2', '27 10', '100'),
  e('7', '2026-10-18', 'xien2', '80 90', '100'),
  e('8', '2026-10-18', 'lo', '40', '20'),
]
const customers = [{ name: 'Anh Dũng', scoringRates: null, homeRegion: null }]
const both = (d, s) => (s !== 'mb' ? null : d === '2026-10-11' ? draw11 : d === '2026-10-18' ? draw18 : null)

test('same money as Tính điểm; nobody won so the profit is the money sent', () => {
  const m = moneyByDate(entries, customers, DEFAULT_RATES, both)
  const direct = summarize([{ date: '2026-10-18', entries: entries.filter((x) => x.entryDate === '2026-10-18') }], DEFAULT_RATES, null, both)
  assert.equal(m.byDate['2026-10-18'].sent, direct.sent.money)
  assert.ok(m.byDate['2026-10-18'].sent > 1e9)
  const t = moneyTotals(m.byDate)
  assert.equal(t.won, 0)
  assert.equal(t.pending, 0)
  assert.equal(t.profit, t.sent)
  assert.equal(m.plays, 8)
  assert.equal(m.customers, 1)
})

test('a day with no result yet is "chưa tính", never profit', () => {
  const m = moneyByDate(entries, customers, DEFAULT_RATES, (d, s) => (d === '2026-10-11' && s === 'mb' ? draw11 : null))
  assert.equal(m.byDate['2026-10-18'].pending, m.byDate['2026-10-18'].sent)
  const t = moneyTotals(m.byDate)
  assert.ok(t.pendingLots > 0)
  assert.equal(t.profit, m.byDate['2026-10-11'].settled)
})

test('a winning number is paid and lowers the profit', () => {
  const m = moneyByDate([e('w', '2026-10-18', 'lo', '15', '10')], customers, DEFAULT_RATES, both)
  const t = moneyTotals(m.byDate)
  assert.ok(t.won > 0)
  assert.ok(t.profit < t.sent)
})

test('series per day go through the unit-tested statsSeries', () => {
  const m = moneyByDate(entries, customers, DEFAULT_RATES, both)
  const now = new Date(2026, 9, 19)
  const profit = buildSeries(pseudoEntries(m.byDate, 'profit'), { unit: 'day', metric: 'profit', now })
  assert.equal(profit.length, 30)
  assert.equal(profit.at(-1).value, 0)
  assert.equal(profit.find((p) => p.key === '2026-10-11').value, m.byDate['2026-10-11'].settled - m.byDate['2026-10-11'].won)
  assert.deepEqual(neededResults(entries).map((x) => x.join('|')).sort(), ['2026-10-11|mb', '2026-10-18|mb'])
})

import { moneyByCustomer } from '../src/lib/statsMoney.js'
test('tiền của từng khách cộng lại bằng tiền theo ngày; khách chưa có kết quả thì tiền ở "pending"', () => {
  const two = [...entries, { id: '9', customerName: 'Chị Lan', entryDate: '2026-10-20', value: '12', score: '100', result: '0', betType: 'lo', station: 'mb' }]
  const per = moneyByCustomer(two, customers, DEFAULT_RATES, both)
  const day = moneyByDate(two, customers, DEFAULT_RATES, both)
  const sum = (k) => Object.values(per).reduce((a, m) => a + m[k], 0)
  const dsum = (k) => Object.values(day.byDate).reduce((a, m) => a + m[k], 0)
  for (const k of ['sent', 'settled', 'won', 'pending']) assert.equal(sum(k), dsum(k))
  assert.equal(per['Chị Lan'].settled, 0)
  assert.ok(per['Chị Lan'].pending > 0)
})
