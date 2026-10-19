// Nhập số: quy tắc thuần của bản mới (chỉ nhập điểm vào, ngày luôn là hôm nay, không tìm/lọc/sao chép).
import test from 'node:test'
import assert from 'node:assert/strict'

globalThis.indexedDB = undefined
const L = await import('../src/features/entries/logic.js')

test('normalizeNumberText: dấu phẩy thập phân và hàng nghìn', () => {
  assert.equal(L.normalizeNumberText('10'), '10')
  assert.equal(L.normalizeNumberText('2,5'), '2.5')
  assert.equal(L.normalizeNumberText('1,234'), '1234')
  assert.equal(L.normalizeNumberText('1,234.5'), '1234.5')
  assert.equal(L.normalizeNumberText('0,125'), '0.125')
  assert.equal(L.normalizeNumberText('abc,1'), 'abc,1')
})

test('điểm: toNumber, fmtPoints, tổng', () => {
  assert.equal(L.toNumber('5.000đ'), 5)
  assert.equal(L.toNumber(''), 0)
  assert.equal(L.fmtPoints(''), '-')
  assert.equal(L.fmtPoints('2000000'), (2000000).toLocaleString('vi-VN'))
  assert.equal(L.fmtPoints('x10'), 'x10')
  const t = L.totalsOf([{ score: '10', result: '4' }, { score: '5' }, { result: '1' }])
  assert.deepEqual(t, { vao: 15, ra: 5, chenhLech: 10 })
})

test('dòng nhập: trống / đủ / sửa hạng mục', () => {
  const r = L.blankRow('lo')
  assert.ok(L.rowBlank(r) && !L.rowComplete(r))
  assert.ok(L.rowComplete({ ...r, value: '12', score: '5' }))
  assert.ok(!L.rowComplete({ ...r, value: '12', score: ' ' }))
  const rows = [{ ...r, type: 'xien' }, { ...r, type: 'de' }]
  const fixed = L.fixRowTypes(rows, ['de', 'lo'])
  assert.deepEqual(fixed.map((x) => x.type), ['de', 'de'])
  assert.equal(L.fixRowTypes(fixed, ['de', 'lo']), fixed)
})

test('checkRows: thiếu số / nửa dòng chặn cả lần lưu', () => {
  const blank = L.blankRow()
  assert.equal(L.checkRows('A', [blank]).error, 'Nhập ít nhất một số')
  assert.equal(L.checkRows('', [{ ...blank, value: '1', score: '1' }]).error, 'Nhập ít nhất một số')
  assert.equal(L.checkRows('A', [{ ...blank, value: '12' }, { ...L.blankRow(), value: '3', score: '1' }]).error, 'Nhập đủ Hạng mục, Số và Điểm vào')
  const ok = L.checkRows('A', [{ ...blank, value: '12', score: '5' }, L.blankRow()])
  assert.equal(ok.started.length, 1)
})

test('entryPayload: ngày là hôm nay, điểm chuẩn hoá, ghi chú trống bị bỏ', () => {
  const p = L.entryPayload({ customerName: ' A ', type: 'de', value: ' 12 ', score: '2,5', station: 'mb', note: '  ', date: '2026-10-19' })
  assert.deepEqual(p, { customerName: 'A', value: '12', entryDate: '2026-10-19', betType: 'de', station: 'mb', score: '2.5' })
})

test('saveItems: một dòng lỗi không làm mất các dòng khác', async () => {
  const items = [{ uid: 1, type: 'de', value: '12', score: '5' }, { uid: 2, type: 'lo', value: '34', score: '1' }, { uid: 3, type: 'de', value: '56', score: '2' }]
  const create = async (p) => {
    if (p.value === '34') throw new Error('hết hạn mức')
    return { entry: { id: p.value, ...p }, queued: p.value === '56' }
  }
  const { saved, failed } = await L.saveItems(items, (i) => ({ value: i.value }), create)
  assert.deepEqual(saved.map((s) => s.item.uid), [1, 3])
  assert.deepEqual(saved.map((s) => s.queued), [false, true])
  assert.deepEqual(failed, ['Lô "34": hết hạn mức'])
})

test('danh sách: chỉ khách đang chọn, hôm nay, đúng đài (không đài = Miền Bắc)', () => {
  const e = (id, customerName, entryDate, station) => ({ id, customerName, entryDate, station })
  const all = [e(1, 'A', '2026-10-19'), e(2, 'A', '2026-10-19', 'mn'), e(3, 'A', '2026-10-18'), e(4, 'B', '2026-10-19')]
  const q = { customerName: 'A', date: '2026-10-19' }
  assert.deepEqual(L.listFor(all, { ...q, station: 'mb' }).map((x) => x.id), [1])
  assert.deepEqual(L.listFor(all, { ...q, station: 'mn' }).map((x) => x.id), [2])
  assert.deepEqual(L.listFor(all, { ...q, customerName: '' , station: 'mb' }), [])
  assert.equal(L.entryCount(all, 'A'), 3)
  assert.match(L.emptyListText({ ...q, entries: all }), /Chưa có số liệu ngày 19\/10\/2026/)
  assert.equal(L.emptyListText({ customerName: 'C', entries: all, date: q.date }), 'Khách hàng này chưa có số liệu nào.')
})

test('gộp dòng đọc từ ảnh/tin nhắn và đoán số từ OCR', () => {
  const blank = [L.blankRow()]
  const fresh = L.ocrGuessRows('Anh Ba\n12 345 6 7890', 'de')
  assert.deepEqual(fresh.map((r) => r.value), ['12', '345', '7890'])
  assert.equal(L.mergeRows(blank, fresh), fresh)
  const typed = [{ ...L.blankRow(), value: '99', score: '1' }]
  assert.equal(L.mergeRows(typed, fresh).length, 4)
})

test('sửa: chỉ đổi số, điểm vào, ghi chú', () => {
  const entry = { customerName: 'A', entryDate: '2026-10-19', betType: 'lo', value: '1' }
  assert.equal(L.editError({ value: ' ' }), 'Vui lòng nhập số liệu')
  assert.deepEqual(L.editChanges(entry, { value: ' 12 ', score: '3,5', note: ' x ' }), {
    customerName: 'A', value: '12', entryDate: '2026-10-19', score: '3.5', betType: 'lo', note: 'x',
  })
})
