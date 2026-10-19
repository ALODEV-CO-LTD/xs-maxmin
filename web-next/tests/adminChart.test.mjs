import test from 'node:test'
import assert from 'node:assert/strict'
import { niceMax, axisMax, shortDate, longDate, shortValue, fullValue, labelIndexes, RANGES, seriesPoints } from '../src/features/admin/chartMath.js'

test('niceMax làm tròn lên 1/2/5 x 10^n', () => {
  assert.equal(niceMax(0), 4)
  assert.equal(niceMax(1), 1)
  assert.equal(niceMax(1.5), 2)
  assert.equal(niceMax(3), 5)
  assert.equal(niceMax(7), 10)
  assert.equal(niceMax(230), 500)
  assert.equal(axisMax([1], false), 4) // đếm người: trục tối thiểu 4
  assert.equal(axisMax([], true), 4)
  assert.equal(axisMax([1], true), 1)
})
test('nhãn trục và chú thích theo ngày / tuần / tháng / năm', () => {
  assert.equal(shortDate('2026-10-05'), '05/10')
  assert.equal(shortDate('2026-10'), '10/26')
  assert.equal(shortDate('2026'), '2026')
  assert.equal(longDate('2026-10-05'), '05/10/2026')
  assert.equal(longDate('2026-10-05', 'week'), 'Tuần 05/10 – 11/10/2026')
  assert.equal(longDate('2026-12-28', 'week'), 'Tuần 28/12 – 03/01/2027')
  assert.equal(longDate('2026-10'), 'Tháng 10/2026')
  assert.equal(longDate('2026'), 'Năm 2026')
})
test('giá trị rút gọn và đầy đủ', () => {
  assert.equal(shortValue(2500000, true), '2.5tr')
  assert.equal(shortValue(50000, true), '50k')
  assert.equal(shortValue(500, true), '500')
  assert.equal(shortValue(2, false), '2')
  assert.match(fullValue(1500000, true), /đ$/)
  assert.equal(fullValue(3, false), '3')
})
test('bốn khoảng thời gian và nhãn nhịp', () => {
  assert.deepEqual(RANGES.map((r) => r.key), ['day', 'week', 'month', 'year'])
  assert.deepEqual(RANGES.map((r) => r.span), ['30 ngày gần nhất', '12 tuần gần nhất', '12 tháng gần nhất', '5 năm gần nhất'])
  const idx = labelIndexes(30, 600)
  assert.equal(idx[0], 0)
  assert.equal(idx.at(-1), 29)
  assert.deepEqual(seriesPoints([{ date: 'a', newUsers: 2 }, { date: 'b' }], 'revenue'), [{ date: 'a', value: 0 }, { date: 'b', value: 0 }])
})
