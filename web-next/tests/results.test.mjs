// Nhập kết quả: quy tắc thuần (bảng giải, kế hoạch lưu, đọc ảnh Miền Bắc, tính Điểm ra của ngày).
import test from 'node:test'
import assert from 'node:assert/strict'

const L = await import('../src/features/results/logic.js')

const MB = [
  { tier: 'dacBiet', label: 'Đặc biệt', count: 1, digits: 5 },
  { tier: 'giaiNhat', label: 'Giải nhất', count: 1, digits: 5 },
  { tier: 'giaiNhi', label: 'Giải nhì', count: 2, digits: 5 },
  { tier: 'giaiBa', label: 'Giải ba', count: 6, digits: 5 },
  { tier: 'giaiTu', label: 'Giải tư', count: 4, digits: 4 },
  { tier: 'giaiNam', label: 'Giải năm', count: 6, digits: 4 },
  { tier: 'giaiSau', label: 'Giải sáu', count: 3, digits: 3 },
  { tier: 'giaiBay', label: 'Giải bảy', count: 4, digits: 2 },
]
const fullForm = () => {
  const f = L.blankForm(MB)
  for (const p of MB) f[p.tier] = L.SINGLE_TIERS.includes(p.tier) ? '1'.repeat(p.digits) : f[p.tier].map(() => '2'.repeat(p.digits))
  return f
}

test('shiftDay đi qua tháng / năm; viDay đảo ngày', () => {
  assert.equal(L.shiftDay('2026-10-01', -1), '2026-09-30')
  assert.equal(L.shiftDay('2026-12-31', 1), '2027-01-01')
  assert.equal(L.viDay('2026-10-19'), '19/10/2026')
  assert.ok(L.isIsoDate('2026-10-19') && !L.isIsoDate('19/10/2026'))
})

test('form giải: 27 ô, ô thêm được giữ lại, bớt chỉ ô vừa thêm', () => {
  const f = L.blankForm(MB)
  assert.equal(L.totalBoxes(MB), 27)
  assert.equal(L.flatValues(MB, f).length, 27)
  const giaiBay = MB[7]
  const more = L.addCell(f, giaiBay)
  assert.equal(more.giaiBay.length, 5)
  assert.equal(L.shapeForm(MB, more).giaiBay.length, 5)
  assert.equal(L.removeCell(more, giaiBay).giaiBay.length, 4)
  assert.equal(L.removeCell(f, giaiBay), f)
})

test('nhập ô: chỉ chữ số, không quá số chữ số của giải', () => {
  const f = L.blankForm(MB)
  assert.equal(L.setCell(f, MB[0], null, '12a3456789').dacBiet, '12345')
  assert.deepEqual(L.setCell(f, MB[7], 1, '9-7x').giaiBay, ['', '97', '', ''])
  assert.equal(L.filledCount(MB, L.setCell(f, MB[0], null, '12345')), 1)
})

test('requiredFilled / ô sai độ dài', () => {
  assert.ok(L.requiredFilled(MB, fullForm()))
  const f = fullForm()
  f.giaiBa[2] = ''
  assert.ok(!L.requiredFilled(MB, f))
  assert.ok(L.cellBad(MB[0], '123', false))
  assert.ok(!L.cellBad(MB[0], '', false))
  assert.ok(L.cellBad(MB[0], '', true)) // ô trống sau khi đọc ảnh bị tô đỏ
  // ô thừa trống bị bỏ khi lưu, ô thừa có số được giữ
  const g = L.addCell(L.addCell(fullForm(), MB[7]), MB[7])
  g.giaiBay[5] = '77'
  assert.deepEqual(L.valuesOf(MB[7], g.giaiBay), ['22', '22', '22', '22', '', '77'].filter((x, i) => i < 4 || x))
})

test('planSave Miền Bắc: phải đủ 27 số', () => {
  const base = { region: 'mb', cols: ['mb'], structure: MB, date: '2026-10-19', nameOf: (s) => s }
  assert.equal(L.planSave({ ...base, forms: { mb: L.blankForm(MB) } }).error, 'Vui lòng nhập đủ 27 số trước khi lưu.')
  const ok = L.planSave({ ...base, forms: { mb: fullForm() } })
  assert.equal(ok.bodies.length, 1)
  assert.equal(ok.bodies[0].body.station, 'mb')
  assert.equal(ok.bodies[0].body.drawDate, '2026-10-19')
  assert.equal(ok.bodies[0].body.giaiBay.length, 4)
})

test('planSave nhiều đài: chỉ lưu cột đã nhập, cột dở dang chặn lưu', () => {
  const base = { region: 'mn', cols: ['tp', 'dt'], structure: MB, date: '2026-10-19', nameOf: (s) => s.toUpperCase() }
  assert.equal(L.planSave({ ...base, forms: { tp: L.blankForm(MB), dt: L.blankForm(MB) } }).error, 'Chưa có số nào để lưu.')
  const half = L.setCell(L.blankForm(MB), MB[0], null, '12345')
  assert.match(L.planSave({ ...base, forms: { tp: half, dt: L.blankForm(MB) } }).error, /^TP: chưa nhập đủ 27 số/)
  const ok = L.planSave({ ...base, forms: { tp: fullForm(), dt: L.blankForm(MB) } })
  assert.deepEqual(ok.bodies.map((b) => b.col), ['tp'])
  assert.equal(ok.message, 'Đã lưu kết quả TP ngày 19/10/2026.')
})

test('buildBoard: cột nào đã lưu thì khoá, đài lệch lịch hiện thêm', () => {
  const results = [{ station: 'tp', dacBiet: '12345', giaiNhat: '', giaiNhi: [] }, { station: 'vl' }]
  const b = L.buildBoard({ structure: MB, cols: ['tp', 'dt'], results })
  assert.deepEqual(b.saved, { tp: true, dt: false })
  assert.equal(b.forms.tp.dacBiet, '12345')
  assert.deepEqual(L.extraStationsOf(results, 'mn', ['tp', 'dt'], () => 'mn'), ['vl'])
  assert.deepEqual(L.stationChoices(['tp', 'dt'], ['vl', 'tp']), ['tp', 'dt', 'vl'])
  assert.deepEqual(L.columnsOf('mb', ['x']), ['mb'])
})

test('đọc ảnh Miền Bắc: xếp theo độ dài, chỉ điền ô trống, bỏ nhãn lẫn chữ', () => {
  const text = '13GH 12345 67890 11111 22222 33333 44444 55555 66666 77777 88888 99999 1234 5678 123 45 67 xx9'
  const f = L.guessFromText(L.blankForm(MB), text)
  assert.equal(f.dacBiet, '12345')
  assert.equal(f.giaiNhat, '67890')
  assert.deepEqual(f.giaiNhi, ['11111', '22222'])
  assert.deepEqual(f.giaiBa.slice(0, 6), ['33333', '44444', '55555', '66666', '77777', '88888'])
  assert.deepEqual(f.giaiTu.slice(0, 2), ['1234', '5678'])
  assert.deepEqual(f.giaiSau, ['123', '', ''])
  assert.deepEqual(f.giaiBay, ['45', '67', '', ''])
  // ô đã có số không bị ghi đè
  const typed = L.setCell(L.blankForm(MB), MB[0], null, '99999')
  assert.equal(L.guessFromText(typed, text).dacBiet, '99999')
})

test('Điểm ra của ngày: tính theo kết quả đã lưu, bỏ qua ngày khác và đài chưa có kết quả', () => {
  // đề 12 trúng giải đặc biệt ...12 → với DEFAULT de { rate: 70, tiers: ['dacBiet'], digits: 2 }
  const rates = { de: { rate: 70, tiers: ['dacBiet'], digits: 2 }, lo: { rate: 20, tiers: ['dacBiet'], digits: 2 } }
  const result = { station: 'mb', dacBiet: '99912' }
  const e = (id, value, over = {}) => ({ id, customerName: 'A', entryDate: '2026-10-19', betType: 'de', value, score: '10', ...over })
  const entries = [e(1, '12'), e(2, '34'), e(3, '12', { entryDate: '2026-10-18' }), e(4, '12', { station: 'tp' })]
  const ctx = { customers: [{ name: 'A' }], rates }
  const plan = L.planScoreSync(entries, '2026-10-19', { mb: result }, ctx)
  assert.deepEqual(plan.changes.map((c) => c.e.id), [1, 2])
  assert.equal(plan.changes[0].value, '700')
  assert.equal(plan.changes[1].value, '0')
  assert.equal(plan.overwrites.length, 0)
  // đã có Điểm ra khác → coi là ghi đè; đã đúng → không đổi
  const again = L.planScoreSync([e(1, '12', { result: '5' }), e(2, '34', { result: '0' })], '2026-10-19', { mb: result }, ctx)
  assert.deepEqual(again.changes.map((c) => c.e.id), [1])
  assert.equal(again.overwrites.length, 1)
  assert.equal(L.planScoreSync(entries, '2026-10-19', {}, ctx).changes.length, 0)
})
