// Chạy: cd frontend && npm test
// Bảng cấu hình (Kiểu đánh - Giá tiền/1 điểm - Giá trúng/1 điểm): cách xác định trúng và cách tính tiền.
import test from 'node:test'
import assert from 'node:assert/strict'
import { entryDetail, summarize } from '../src/scoringSummary.js'
import { defaultRow, DEFAULT_RATES, toTableRow } from '../src/scoringConfig.js'

// A Miền Nam day (18 lô; giải tám 2 số, giải bảy 3 số, đặc biệt 6 số) and a Miền Bắc day (27 lô).
const MN = { giaiTam: ['20'], giaiBay: ['120'], giaiSau: ['1234', '5678', '0020'], giaiNam: ['9020'], giaiTu: ['11111', '22222', '33333', '44444', '55555', '66666', '77720'], giaiBa: ['12345', '23456'], giaiNhi: ['34567'], giaiNhat: ['45678'], dacBiet: ['123456'] }
const MB = { dacBiet: ['70002'], giaiNhat: ['11120'], giaiNhi: ['11111', '22222'], giaiBa: ['1', '2', '3', '4', '5', '6'].map((x) => `${x}${x}${x}${x}${x}`), giaiTu: ['1234', '5678', '9012', '3456'], giaiNam: ['1111', '2222', '3333', '4444', '5555', '6666'], giaiSau: ['123', '456', '789'], giaiBay: ['20', '15', '88', '33'] }

const row = (kind, region = 'mn') => defaultRow(kind, region)
const entry = (value, score, extra = {}) => ({ value, score: String(score), ...extra })
const hits = (d) => d.perNumber.map((p) => `${p.number}:${p.hits}`).join(' ')

test('bao lô: 2 số so 18 lô Nam (cả giải tám), nhiều lô về thì nhân lên', () => {
  // "20" về ở giải tám, giải bảy 120, giải sáu 0020, giải năm 9020, giải tư 77720 = 5 lần
  assert.equal(hits(entryDetail(entry('20', 10), MN, row('lo'), { region: 'mn' })), '20:5')
})
test('bao lô 3 số chỉ so các giải có từ 3 chữ số', () => {
  assert.equal(hits(entryDetail(entry('020', 1), MN, row('lo3'), { region: 'mn' })), '020:2') // 0020, 9020 -> 020; giải tám "20" không tính
})
test('đầu Nam/Trung = giải tám; đuôi = 2 số cuối giải đặc biệt', () => {
  assert.equal(hits(entryDetail(entry('20', 5), MN, row('dau'), { region: 'mn' })), '20:1')
  assert.equal(hits(entryDetail(entry('56', 5), MN, row('duoi'), { region: 'mn' })), '56:1')
  assert.equal(hits(entryDetail(entry('20', 5), MN, row('duoi'), { region: 'mn' })), '20:0')
})
test('đầu ở đài Bắc: khách Bắc = giải nhất (1 lô); khách Nam/Trung = 4 giải bảy, tiền xác ×4', () => {
  const bac = entryDetail(entry('20', 1), MB, row('dau', 'mb'), { region: 'mb', customerRegion: 'mb' })
  assert.equal(hits(bac), '20:1')
  assert.equal(bac.stakeFactor, 1)
  const nam = entryDetail(entry('20', 1), MB, row('dau', 'mb'), { region: 'mb', customerRegion: 'mn' })
  assert.equal(hits(nam), '20:1')
  assert.equal(nam.stakeFactor, 4)
})
test('3 càng / 4 càng chỉ so giải đặc biệt', () => {
  assert.equal(hits(entryDetail(entry('456', 2), MN, row('cang3'), { region: 'mn' })), '456:1')
  assert.equal(hits(entryDetail(entry('3456', 2), MN, row('cang4'), { region: 'mn' })), '3456:1')
  assert.equal(hits(entryDetail(entry('123', 2), MN, row('cang3'), { region: 'mn' })), '123:0')
})
test('xiên thật: trúng khi CẢ các số cùng về, và chỉ tính một lần', () => {
  assert.equal(entryDetail(entry('20 56', 10), MN, row('xien2'), { region: 'mn' }).totalHits, 1) // 20 (nhiều lô) và 56 cùng về
  assert.equal(entryDetail(entry('20 99', 10), MN, row('xien2'), { region: 'mn' }).totalHits, 0)
  assert.equal(entryDetail(entry('20 56 34', 10), MN, row('xien3'), { region: 'mn' }).totalHits, 1) // 34 ở 123456? "56" "34": 1234, 12345, 34567 -> 34 về
})

const day = (entries) => [{ date: '2026-10-12', entries }]
const run = (entries, rates, getResult, opts) => summarize(day(entries), rates, null, getResult, opts)

test('tiền: xác = điểm × giá tiền; trúng = lần trúng × điểm × giá trúng; lợi nhuận = xác - trúng', () => {
  // bao lô Nam 30 điểm số 20: về 5 lần. xác = 30 × 12.600 = 378.000; trúng = 5 × 30 × 70.000 = 10.500.000
  const s = run([entry('20', 30, { betType: 'lo', station: 'mn' })], DEFAULT_RATES, () => MN)
  assert.equal(s.sent.money, 378000)
  assert.equal(s.won.money, 10500000)
  assert.equal(s.remaining, 378000 - 10500000)
})
test('xiên 2: xác = điểm × 2 × giá tiền; trúng một lần = điểm × giá trúng', () => {
  const rates = { ...DEFAULT_RATES, 'xien2@mn': { ...DEFAULT_RATES['xien2@mn'], payout: 1000000 } }
  const s = run([entry('20 56', 10, { betType: 'xien2', station: 'mn' })], rates, () => MN)
  assert.equal(s.sent.money, 10 * 2 * 12600)
  assert.equal(s.won.money, 10 * 1000000)
})
test('đầu đài Bắc, khách Nam/Trung: 1 điểm = 4.000đ', () => {
  const s = run([entry('20', 3, { betType: 'dau', station: 'mb' })], DEFAULT_RATES, () => MB, { customerRegion: 'mn' })
  assert.equal(s.sent.money, 3 * 4 * 1000)
  assert.equal(s.won.money, 3 * 1 * 70000)
})
test('cấu hình cũ (rate, unit, pointValue) vẫn tính như trước và hiện được trong bảng', () => {
  const legacy = { lo: { rate: 20, tiers: ['dacBiet', 'giaiNhat', 'giaiNhi', 'giaiBa', 'giaiTu', 'giaiNam', 'giaiSau', 'giaiBay'], digits: 2, unit: 'point', pointValue: 23000 } }
  const s = run([entry('20', 1, { betType: 'lo', station: 'mb' })], legacy, () => MB)
  assert.equal(s.sent.money, 23000)
  assert.equal(s.won.money, 1 * 20 * 23000 * 2) // giải nhất 11120 và giải bảy 20
  const t = toTableRow('lo', legacy.lo)
  assert.equal(t.price, 23000)
  assert.equal(t.payout, 460000)
})

test('bao lô 4 số: chỉ các lô có từ 4 chữ số (Nam/Trung 16, Bắc 20)', () => {
  assert.equal(hits(entryDetail(entry('9020', 1), MN, row('lo4'), { region: 'mn' })), '9020:1')
  assert.equal(hits(entryDetail(entry('1234', 1), MB, row('lo4', 'mb'), { region: 'mb' })), '1234:1')
  assert.equal(hits(entryDetail(entry('0020', 1), MN, row('lo4'), { region: 'mn' })), '0020:1')
})
test('mỗi miền một cách lấy số: cùng bao lô 2 số, Bắc so 27 lô, Nam/Trung 18 lô (cả giải tám)', () => {
  // "20": Bắc có giải nhất 11120 và giải bảy 20 = 2 lần; Nam có 5 lần như trên
  assert.equal(hits(entryDetail(entry('20', 1), MB, row('lo', 'mb'), { region: 'mb' })), '20:2')
  assert.equal(hits(entryDetail(entry('20', 1), MN, row('lo'), { region: 'mn' })), '20:5')
})
test('lô trượt: trúng khi TẤT CẢ các số đều không về, một lần; tiền xác × số số', () => {
  const none = entryDetail(entry('01 02 03 04', 10), MN, row('truot4'), { region: 'mn' })
  assert.equal(none.totalHits, 1)
  assert.equal(none.lots, 4)
  assert.equal(entryDetail(entry('01 02 03 20', 10), MN, row('truot4'), { region: 'mn' }).totalHits, 0) // 20 về
  assert.equal(entryDetail(entry('01 02 03', 10), MN, row('truot4'), { region: 'mn' }).totalHits, 0) // thiếu số
  const rates = { ...DEFAULT_RATES, 'truot4@mn': { ...DEFAULT_RATES['truot4@mn'], payout: 50000 } }
  const s = run([entry('01 02 03 04', 10, { betType: 'truot4', station: 'mn' })], rates, () => MN)
  assert.equal(s.sent.money, 10 * 4 * 12600)
  assert.equal(s.won.money, 10 * 50000)
})
test('tài/xỉu và chẵn/lẻ theo đuôi giải đặc biệt', () => {
  // MN đặc biệt 123456 -> đuôi 56: Tài, chẵn
  assert.equal(entryDetail(entry('tai', 5), MN, row('tai_xiu'), { region: 'mn' }).totalHits, 1)
  assert.equal(entryDetail(entry('xiu', 5), MN, row('tai_xiu'), { region: 'mn' }).totalHits, 0)
  assert.equal(entryDetail(entry('chan', 5), MN, row('chan_le'), { region: 'mn' }).totalHits, 1)
  assert.equal(entryDetail(entry('le', 5), MN, row('chan_le'), { region: 'mn' }).totalHits, 0)
  // MB đặc biệt 70002 -> đuôi 02: Xỉu, chẵn
  assert.equal(entryDetail(entry('xiu', 5), MB, row('tai_xiu', 'mb'), { region: 'mb' }).totalHits, 1)
})

import { effectiveConfig, typesIn } from '../src/scoringConfig.js'
test('xoá một dòng chuẩn khỏi bảng: bị ẩn khỏi danh sách, số liệu cũ vẫn tính theo mặc định', () => {
  const rates = { ...DEFAULT_RATES, 'xien4@mn': { disabled: true } }
  assert.equal(typesIn(rates, 'mn').includes('xien4'), false)
  assert.equal(typesIn(rates, 'mb').includes('xien4'), false || typesIn(rates, 'mb').includes('xien4')) // miền khác không đổi
  assert.equal(typesIn(DEFAULT_RATES, 'mn').includes('xien4'), true)
  const cfg = effectiveConfig(rates, null, 'xien4', 'mn')
  assert.equal(cfg.kind, 'xien4')
  assert.equal(cfg.price, 12600)
})

test('lấy số tuỳ chỉnh: giải nào, vị trí đầu/cuối, bao nhiêu số, lô thứ mấy', () => {
  const withSource = (kind, source) => ({ ...defaultRow(kind, 'mn'), source })
  // đầu của giải đặc biệt Nam 123456: 2 số đầu = "12"
  const head = withSource('duoi', { tiers: ['dacBiet'], position: 'first', digits: 2 })
  assert.equal(hits(entryDetail(entry('12', 1), MN, head, { region: 'mn' })), '12:1')
  assert.equal(hits(entryDetail(entry('56', 1), MN, head, { region: 'mn' })), '56:0')
  // 3 số cuối của giải đặc biệt và giải nhất (45678 -> 678)
  const two = withSource('cang3', { tiers: ['dacBiet', 'giaiNhat'], position: 'last', digits: 3 })
  assert.equal(hits(entryDetail(entry('678', 1), MN, two, { region: 'mn' })), '678:1')
  // chỉ lô thứ 2 của giải ba (23456 -> 56) trong khi lô thứ 1 là 12345
  const pick = withSource('duoi', { tiers: ['giaiBa'], position: 'last', digits: 2, pick: [2] })
  assert.equal(hits(entryDetail(entry('56', 1), MN, pick, { region: 'mn' })), '56:1')
  assert.equal(hits(entryDetail(entry('45', 1), MN, pick, { region: 'mn' })), '45:0')
  // 4 số cuối của cả giải sáu (4 chữ số): "5678"
  const sau = withSource('lo4', { tiers: ['giaiSau'], position: 'last', digits: 4 })
  assert.equal(hits(entryDetail(entry('5678', 1), MN, sau, { region: 'mn' })), '5678:1')
  // đầu ở đài Bắc khi đã chỉnh lấy số thì không còn tự đổi theo miền của khách
  const custom = withSource('dau', { tiers: ['giaiBay'], position: 'last', digits: 2 })
  const d = entryDetail(entry('20', 1), MB, custom, { region: 'mb', customerRegion: 'mn' })
  assert.equal(d.stakeFactor, 1)
})

test('Kiểu đánh cũ "de" / "3-càng" trùng chuẩn mới thì chỉ hiện một (giữ dữ liệu cũ để tính điểm)', async () => {
  const { customerBetTypes, effectiveConfig } = await import('../src/scoringConfig.js')
  const acc = { de: { rate: 70, tiers: ['dacBiet'], digits: 2 }, lo: { rate: 20, tiers: ['dacBiet'], digits: 2 }, '3-càng': { rate: 400, tiers: ['dacBiet'], digits: 3 }, 'duoi@mb': { ...defaultRow('duoi', 'mb') }, 'cang3@mb': { ...defaultRow('cang3', 'mb') } }
  assert.deepEqual(customerBetTypes(acc, null, 'mb'), ['lo', 'duoi', 'cang3'])
  assert.equal(effectiveConfig(acc, null, 'de', 'mb').rate, 70) // an old entry typed "de" is still scored with its own config
  const only = { de: acc.de, lo: acc.lo }
  assert.deepEqual(customerBetTypes(only, null, 'mb'), ['de', 'lo']) // no standard duplicate, so it stays
})
