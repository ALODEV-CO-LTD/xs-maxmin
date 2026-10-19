// Màn Khách hàng: gộp danh sách khách với số liệu, tìm không dấu, thêm khách + đài mặc định, thông báo lỗi.
import test from 'node:test'
import assert from 'node:assert/strict'
import { OFFLINE_WRITE, buildCustomers, createCustomer, entriesUrl, filterCustomers, formatNumber, removeConfirm, saveError, sortRoster, toNumber, writeError } from '../src/features/customers/customersLogic.js'

const err = (status, message) => Object.assign(new Error(message), { status })
const roster = [
  { id: 'r1', name: 'Anh Dũng', phone: '0901' },
  { id: 'r2', name: 'Chị Mai' },
  { id: 'r3', name: 'Đỗ Ngọc Mai', phone: '' },
]
const entries = [
  { customerName: 'Anh Dũng', entryDate: '2026-10-10', score: '1.000', result: '400' },
  { customerName: 'Anh Dũng', entryDate: '2026-10-12', score: '500', result: 'abc' },
  { customerName: 'Khách lạ', entryDate: '2026-10-11', score: '200', result: '300' },
  { customerName: '', entryDate: '2026-10-01', score: '7', result: '' },
]

test('toNumber / formatNumber như bản Vue', () => {
  assert.equal(toNumber('1.000'), 1)
  assert.equal(toNumber('-12.5đ'), -12.5)
  assert.equal(toNumber(''), 0)
  assert.equal(toNumber(null), 0)
  assert.equal(toNumber('abc'), 0)
  assert.equal(formatNumber(1234567), '1.234.567')
})
test('danh sách: khách trong roster (kể cả chưa có lượt nhập) + tên chỉ có trong số liệu, cộng điểm vào/ra', () => {
  const list = buildCustomers(roster, entries)
  assert.equal(list.length, 5) // 3 roster + Khách lạ + (Không tên)
  const dung = list.find((c) => c.name === 'Anh Dũng')
  assert.deepEqual([dung.rosterId, dung.phone, dung.count, dung.vao, dung.ra, dung.chenhLech, dung.lastDate], ['r1', '0901', 2, 501, 400, 101, '2026-10-12'])
  const la = list.find((c) => c.name === 'Khách lạ')
  assert.equal(la.rosterId, null)
  assert.equal(la.chenhLech, -100)
  assert.ok(list.find((c) => c.name === '(Không tên)'))
})
test('sắp xếp: khách chưa có lượt nhập lên đầu theo tên, sau đó ngày gần nhất trước', () => {
  const list = buildCustomers(roster, entries)
  assert.deepEqual(list.map((c) => c.name), ['Chị Mai', 'Đỗ Ngọc Mai', 'Anh Dũng', 'Khách lạ', '(Không tên)'])
})
test('tìm kiếm không phân biệt dấu và hoa thường', () => {
  const list = buildCustomers(roster, entries)
  assert.deepEqual(filterCustomers(list, 'do ngoc').map((c) => c.name), ['Đỗ Ngọc Mai'])
  assert.deepEqual(filterCustomers(list, '  MAI ').map((c) => c.name).sort(), ['Chị Mai', 'Đỗ Ngọc Mai'])
  assert.equal(filterCustomers(list, '   ').length, list.length)
  assert.equal(filterCustomers(list, 'zzz').length, 0)
})
test('sắp xếp roster theo tên tiếng Việt, địa chỉ Nhập số', () => {
  assert.deepEqual(sortRoster([{ name: 'Mai' }, { name: 'An' }, { name: 'Đức' }]).map((c) => c.name), ['An', 'Đức', 'Mai'])
  assert.equal(entriesUrl('Anh Dũng'), '/entries?customer=Anh%20D%C5%A9ng')
})
test('thêm khách: đài Miền Bắc không gọi PATCH; đài khác lưu thêm đài mặc định', async () => {
  const calls = []
  const api = { post: async (p, b) => (calls.push(['POST', p, b]), { id: 'n1', name: b.name, phone: b.phone }), patch: async (p, b) => (calls.push(['PATCH', p, b]), { defaultStation: b.defaultStation }) }
  let r = await createCustomer(api, { name: 'A', phone: '1', station: 'mb' })
  assert.equal(r.warn, '')
  assert.equal(calls.length, 1)
  r = await createCustomer(api, { name: 'B', phone: '', station: 'mn' })
  assert.deepEqual(calls[2], ['PATCH', '/me/customers/n1', { defaultStation: 'mn' }])
  assert.equal(r.created.defaultStation, 'mn')
  assert.equal(r.warn, '')
})
test('thêm khách: tạo được nhưng lưu đài lỗi thì vẫn có khách và báo cảnh báo; tạo lỗi thì ném lỗi', async () => {
  const bad = { post: async () => ({ id: 'n', name: 'A' }), patch: async () => { throw err(400, 'Đài không hợp lệ') } }
  let r = await createCustomer(bad, { name: 'A', phone: '', station: 'mt' })
  assert.equal(r.created.id, 'n')
  assert.equal(r.warn, 'Đã tạo khách nhưng chưa lưu được đài mặc định: Đài không hợp lệ.')
  r = await createCustomer({ ...bad, patch: async () => { throw new Error('x') } }, { name: 'A', phone: '', station: 'mt' })
  assert.match(r.warn, /lỗi mạng\.$/)
  await assert.rejects(createCustomer({ post: async () => { throw err(409, 'Khách này đã có') } }, { name: 'A', phone: '', station: 'mb' }), /đã có/)
})
test('thông báo lỗi: server, offline, không rõ', () => {
  assert.equal(writeError(err(409, 'Đã có'), 'x'), 'Đã có')
  assert.equal(writeError(err(0, 'net'), 'x'), OFFLINE_WRITE)
  assert.equal(writeError(new Error('boom'), 'Không xoá được'), 'Không xoá được')
  assert.equal(saveError(err(0, 'net'), 'x'), 'net')
  assert.equal(saveError(null, 'Không lưu được đài'), 'Không lưu được đài')
  assert.deepEqual(removeConfirm('An'), { title: 'Xoá khách hàng', message: 'Xoá "An" khỏi danh sách khách hàng? Số liệu đã nhập của khách này vẫn được giữ nguyên.', confirmText: 'Xoá', danger: true })
})
