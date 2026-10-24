import test from 'node:test'
import assert from 'node:assert/strict'
import { parseColumns } from '../src/lib/lotteryColumns.js'

const W = (text, cx, cy) => ({ text, x0: cx - 30, x1: cx + 30, y0: cy - 10, y1: cy + 10 })
function column(x, seed) {
  const num = (digits, k) => String(seed * 1000 + k * 37 + 11).padStart(digits, '0').slice(0, digits)
  const out = []
  let k = 0
  const add = (digits, y) => out.push(W(num(digits, ++k), x, y))
  add(2, 100)
  add(3, 130)
  for (const y of [160, 190, 220]) add(4, y)
  add(4, 250)
  for (let i = 0; i < 7; i++) add(5, 280 + i * 30)
  for (const y of [490, 520]) add(5, y)
  add(5, 550)
  add(5, 580)
  add(6, 610)
  return out
}
const table = (extra = []) => [W('Đồng', 170, 60), W('Cần', 470, 60), W('Sóc', 770, 60), ...[0, 1, 2].flatMap((i) => column(200 + i * 300, i + 1)), ...extra]

test('đọc ảnh Miền Nam: dòng chân trang, mã 6 số, số điện thoại dưới bảng không thành giải', () => {
  const plain = parseColumns(table())
  const extra = [
    ...[0, 1, 2, 3, 4, 5].flatMap((r) => [0, 1, 2].map((c) => W(`${r}7`, 200 + c * 300, 700 + r * 30))),
    W('123456', 500, 900),
    W('0901234567', 500, 940),
    W('2026', 500, 980),
  ]
  const p = parseColumns(table(extra))
  assert.equal(p.columns.length, 3)
  p.columns.forEach((c, i) => assert.deepEqual(c.values, plain.columns[i].values))
})

test('đọc ảnh Miền Nam: mã 6 số ở tiêu đề không thành một cột', () => {
  const p = parseColumns([...table(), W('654321', 500, 30)])
  assert.equal(p.columns.length, 3)
})

import { decodeMessage } from '../src/lib/messageParser.js'
test('Đối chiếu: "de 44x20" giữ nguyên là đề, không đổi thành lô; không có hạng mục thì vẫn là bao lô', () => {
  const dec = (t) => decodeMessage(t, { betTypes: ['de', 'lo'] }).map((l) => l.decoded)
  assert.deepEqual(dec('de 44x20'), ['de 44x20'])
  assert.deepEqual(dec('de:\n44x20'), ['de:', '44x20'])
  assert.deepEqual(dec('lo 12x5'), ['lo 12x5'])
  assert.deepEqual(dec('44x20'), ['44lô20'])
})
