// Chạy: cd frontend && npm test
import test from 'node:test'
import assert from 'node:assert/strict'
import { buildSeries, rangeTotals, tickEvery, tickIndices, compactNumber, isoWeek } from '../src/lib/statsSeries.js'

const NOW = new Date(2026, 9, 17) // Thứ Bảy 17/10/2026 (tuần ISO 42)
const E = [
  { entryDate: '2026-10-17', score: '1000', result: '400' },
  { entryDate: '2026-10-12', score: '500', result: '' }, // Thứ Hai tuần 42
  { entryDate: '2026-10-11', score: '200', result: '900' }, // Chủ nhật tuần 41
  { entryDate: '2025-01-05', score: '100', result: '30' },
]

test('số điểm kỳ: ngày 30, tuần 12, tháng 12, năm 5; kỳ trống = 0; đúng thứ tự', () => {
  const sizes = { day: 30, week: 12, month: 12, year: 5 }
  for (const [unit, n] of Object.entries(sizes)) {
    const s = buildSeries([], { unit, metric: 'vao', now: NOW })
    assert.equal(s.length, n)
    assert.ok(s.every((p) => p.value === 0))
    assert.deepEqual(s.map((p) => p.key), [...s.map((p) => p.key)].sort())
  }
})
test('ngày: vào/ra/lợi nhuận', () => {
  const g = (metric) => buildSeries(E, { unit: 'day', metric, now: NOW })
  const last = (m) => g(m).at(-1)
  assert.equal(last('vao').value, 1000)
  assert.equal(last('ra').value, 400)
  assert.equal(last('profit').value, 600)
  assert.equal(last('profit').label, '17/10')
  assert.equal(last('profit').full, '17/10/2026')
})
test('tuần ISO: thứ Hai là đầu tuần, Chủ nhật thuộc tuần trước', () => {
  const s = buildSeries(E, { unit: 'week', metric: 'vao', now: NOW })
  assert.equal(s.at(-1).key, '2026-10-12')
  assert.equal(s.at(-1).value, 1500) // 17/10 + 12/10
  assert.equal(s.at(-2).key, '2026-10-05')
  assert.equal(s.at(-2).value, 200) // Chủ nhật 11/10
  assert.equal(s.at(-1).label, '12/10')
  assert.match(s.at(-1).full, /^Tuần 42 /)
})
test('isoWeek qua mốc năm', () => {
  assert.deepEqual(isoWeek(new Date(2026, 0, 1)), { year: 2026, week: 1 })
  assert.deepEqual(isoWeek(new Date(2027, 0, 1)), { year: 2026, week: 53 })
})
test('tháng và năm', () => {
  const m = buildSeries(E, { unit: 'month', metric: 'vao', now: NOW })
  assert.equal(m.at(-1).value, 1700)
  assert.equal(m.at(-1).label, '10/26')
  assert.equal(m[0].key, '2025-11')
  const y = buildSeries(E, { unit: 'year', metric: 'profit', now: NOW })
  assert.deepEqual(y.map((p) => p.label), ['2022', '2023', '2024', '2025', '2026'])
  assert.equal(y.at(-2).value, 70)
  assert.equal(y.at(-1).value, 1700 - 1300)
})
test('rangeTotals: kỳ hiện tại và kỳ liền trước', () => {
  const t = rangeTotals(E, { unit: 'week', metric: 'vao', now: NOW })
  assert.equal(t.current, 1700)
  assert.equal(t.previous, null)
  const y = rangeTotals(E, { unit: 'year', metric: 'vao', now: new Date(2026, 5, 1) })
  assert.equal(y.current, 1800)
  assert.equal(rangeTotals([{ entryDate: '2020-01-01', score: '5' }], { unit: 'year', metric: 'vao', now: NOW }).previous, 5)
})
test('tickEvery / tickIndices: luôn có nhãn đầu và cuối, không dày hơn bề rộng', () => {
  assert.equal(tickEvery(12, 600), 1)
  assert.equal(tickEvery(30, 320), 5)
  for (const [n, w] of [[30, 320], [30, 700], [12, 300], [5, 300]]) {
    const idx = tickIndices(n, tickEvery(n, w))
    assert.equal(idx[0], 0)
    assert.equal(idx.at(-1), n - 1)
    const min = Math.min(...idx.slice(1).map((v, i) => v - idx[i]))
    assert.ok(n === 1 || min * (w / n) >= 40, `${n}/${w}`)
  }
})
test('compactNumber', () => {
  assert.equal(compactNumber(0), '0')
  assert.equal(compactNumber(950), '950')
  assert.equal(compactNumber(1500), '1,5k')
  assert.equal(compactNumber(-2500000), '-2,5tr')
  assert.equal(compactNumber(3e9), '3 tỷ')
  assert.equal(compactNumber(-1000), '-1k')
})
