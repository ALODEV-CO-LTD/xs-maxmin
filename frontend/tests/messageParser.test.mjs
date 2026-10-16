// Chạy: cd frontend && npm test   (dùng node:test có sẵn, không cần cài thêm gì)
import test from 'node:test'
import assert from 'node:assert/strict'
import { parseMessage, decodeMessage } from '../src/messageParser.js'

const TYPES = ['de', 'lo']
const WIDE = ['de', 'lo', 'dau', 'cang3', 'cang4', 'xien2', 'xien3', 'xien4']
const brief = (r) => `${r.type}:${r.value}@${r.score}${r.uncertain ? '!' : ''}`
const parse = (text, betTypes = TYPES, template = null) => parseMessage(text, { betTypes, template }).rows.map(brief)
const decode = (text, betTypes = TYPES, template = null) => decodeMessage(text, { betTypes, template }).map((l) => l.decoded)

test('ví dụ chính trong tài liệu: 20lo100 70lo500 54lo300', () => {
  assert.deepEqual(parse('20lo100 70lo500 54lo300'), ['lo:20@100', 'lo:70@500', 'lo:54@300'])
  // Giải mã chỉ đổi cách viết ký hiệu. Tài liệu có ví dụ "70" thành "10" nhưng không có quy tắc nào để đổi số,
  // nên bộ giải mã KHÔNG đổi số.
  assert.deepEqual(decode('20lo100 70lo500 54lo300'), ['20lô100 70lô500 54lô300'])
})

test('bao lô: mọi cách viết ký hiệu', () => {
  for (const sym of ['lo', 'l', 'L', 'lô', 'Lô', 'LO', 'x', 'X']) assert.deepEqual(parse(`20${sym}30`), ['lo:20@30'], sym)
})

test('đầu và đuôi (đuôi trùng với Đề đã có của tài khoản)', () => {
  for (const sym of ['d', 'D', 'đ', 'dau', 'đầu', 'đâu', 'dâu']) assert.deepEqual(parse(`20${sym}10`, WIDE), ['dau:20@10'], sym)
  for (const sym of ['c', 'C', 'cuoi', 'cuôi', 'cuối', 'CUOI']) assert.deepEqual(parse(`20${sym}10`), ['de:20@10'], sym)
  assert.deepEqual(parse('20c10', [...TYPES, 'duoi']), ['duoi:20@10'])
})

test('đầu đuôi trong một cụm: 20d10c20 = đầu 10 điểm + đuôi 20 điểm', () => {
  assert.deepEqual(parse('20d10c20', WIDE), ['dau:20@10', 'de:20@20'])
  assert.deepEqual(decode('20d10c20', WIDE), ['20đầu10 20đuôi20'])
})

test('3 càng và 4 càng theo số chữ số', () => {
  assert.deepEqual(parse('123x100', WIDE), ['cang3:123@100'])
  assert.deepEqual(parse('5000x100', WIDE), ['cang4:5000@100'])
  assert.deepEqual(parse('5000l100', WIDE), ['cang4:5000@100'])
  assert.deepEqual(parse('5000Lo100', WIDE), ['cang4:5000@100'])
})

test('xiên: ký hiệu nối số luôn là xiên, dấu chấm chỉ khi tài khoản có loại Xiên', () => {
  assert.deepEqual(parse('20x02lo10', WIDE), ['xien2:20 02@10!']) // luôn bị đánh dấu: chưa tính điểm xiên
  assert.deepEqual(parse('20.02lo10', WIDE), ['xien2:20 02@10!'])
  assert.deepEqual(parse('20.02.35x10', WIDE), ['xien3:20 02 35@10!'])
  assert.deepEqual(parse('20.02x10', TYPES), ['de:20@10!', 'de:02@10!']) // không có loại Xiên: giữ cách hiểu cũ
  assert.deepEqual(decode('20x02lo10', WIDE), ['20.02xiên10'])
})

test('mọi dòng liền đều bị đánh dấu khi tài khoản chưa có loại đó (không lưu âm thầm)', () => {
  const [r] = parseMessage('20dau10', { betTypes: TYPES }).rows
  assert.equal(r.type, 'dau')
  assert.equal(r.uncertain, true)
  assert.ok(r.reasons.some((x) => x.includes('chưa có trong cấu hình')))
  assert.equal(parseMessage('20dau10', { betTypes: WIDE }).rows[0].uncertain, false)
})

test('số chữ số sai bị đánh dấu', () => {
  const [r] = parseMessage('200lo10', { betTypes: WIDE }).rows // 3 chữ số + lo = 3 càng, hợp lệ
  assert.equal(r.type, 'cang3')
  const [d] = parseMessage('123d10', { betTypes: WIDE }).rows // đầu phải 2 chữ số
  assert.equal(d.uncertain, true)
  assert.ok(d.reasons.some((x) => x.includes('2 chữ số')))
})

test('x trần: theo loại của khách/dòng trước nếu có, nếu không thì là bao lô', () => {
  assert.deepEqual(parse('20x30'), ['lo:20@30'])
  assert.deepEqual(parse('20x30', TYPES, { defaultType: 'de' }), ['de:20@30'])
  assert.deepEqual(parse('de:\n20x30'), ['de:20@30'])
})

test('hồi quy: các định dạng cũ vẫn như trước', () => {
  assert.deepEqual(parse('de 12 34 56 x 10'), ['de:12@10', 'de:34@10', 'de:56@10'])
  assert.deepEqual(parse('lô 45,78 con 3'), ['lo:45@3', 'lo:78@3'])
  assert.deepEqual(parse('12=50', TYPES, { defaultType: 'de' }), ['de:12@50'])
  assert.deepEqual(parse('de:\n12 x 5\n34 x 7'), ['de:12@5', 'de:34@7'])
  assert.deepEqual(parse('lo 20 x 30'), ['lo:20@30'])
  assert.deepEqual(parseMessage('xin chào anh', { betTypes: TYPES }).rows, [])
})

test('dòng lẫn cú pháp liền và chữ khác: đi theo đường cũ, không vỡ', () => {
  const out = parseMessage('20lo100 abc', { betTypes: TYPES })
  assert.ok(Array.isArray(out.rows) && Array.isArray(out.ignored))
  assert.ok(out.rows.every((r) => r.uncertain))
})

test('ký hiệu riêng của khách (mẫu) dùng được ở dạng liền', () => {
  const tpl = { typeAliases: { tr: 'truot' } }
  assert.deepEqual(parse('20tr10', ['de', 'lo', 'truot'], tpl), ['truot:20@10'])
  assert.deepEqual(parse('20tr10', TYPES, tpl), ['truot:20@10!']) // loại chưa có trong cấu hình: bị đánh dấu
})

test('điểm thập phân và số 0 đầu được giữ nguyên', () => {
  assert.deepEqual(parse('02lo10.5'), ['lo:02@10.5'])
  assert.deepEqual(parse('02lo10,5'), ['lo:02@10.5'])
  assert.deepEqual(decode('02lo10,5'), ['02lô10,5']) // giải mã giữ nguyên số như khách gõ
})

test('giải mã: không đổi số, giữ khoảng trắng, báo phần không nhận ra', () => {
  const [line] = decodeMessage('  20lo100   chào 99zz  54L300', { betTypes: TYPES })
  assert.equal(line.decoded, '  20lô100   chào 99zz  54lô300')
  assert.equal(line.changed, true)
  assert.equal(line.unknown, true) // "99zz" có số nhưng không nhận ra: giữ nguyên và báo để kiểm tra
  assert.equal(line.parts.find((p) => p.text === '99zz').status, 'unknown')
  assert.equal(line.parts.find((p) => p.text === 'chào').status, 'plain')
})

test('giải mã chạy lần hai không đổi gì thêm (ổn định)', () => {
  for (const t of ['20lo100 70lo500', '20d10c20', '20x02lo10', '123x100', '5000l100', '20dau10 20cuoi10']) {
    const once = decode(t, WIDE)[0]
    assert.equal(decode(once, WIDE)[0], once, t)
  }
})

test('mỗi tin nhắn được xử lý độc lập theo từng dòng', () => {
  assert.deepEqual(decode('20lo100\n30d5\n99', WIDE), ['20lô100', '30đầu5', '99'])
})
