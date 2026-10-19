// Màn Tính điểm: logic thuần (features/scoring) tương đương ScoringView.vue, ScoringSummary.vue, DeleteDataDialog.vue, DeletionSchedules.vue.
import test from 'node:test'
import assert from 'node:assert/strict'
import {
  PAGE_DAYS, addedNotice, areaName, buildDays, computeOne, dayLabel, emptyMessage, entryOut, filterEntries, filterMissing, isOpen,
  lotteryState, money, openKey, presetRange, rangeForDay, singleDayOf, toNumber, totalsOf, scoreEntryAll,
} from '../src/features/scoring/scoringLogic.js'
import { deleteBody, deleteProblem, hasLimit, scopeText } from '../src/features/scoring/deleteLogic.js'
import { buildScheduleBody, confirmMessage, defaultRunAt, describe, repeatValue, statusText, toLocalInput } from '../src/features/scoring/scheduleLogic.js'
import { DEFAULT_RATES } from '../src/lib/scoringConfig.js'
import { summarize } from '../src/lib/scoringSummary.js'

const draw = { dacBiet: '38115', giaiNhat: '97733', giaiNhi: ['21143', '52941'], giaiBa: ['12914', '26998', '10224', '63551', '85741', '77963'], giaiTu: ['7663', '1599', '9528', '3603'], giaiNam: ['6707', '5085', '3629', '5755', '2682', '1939'], giaiSau: ['455', '297', '980'], giaiBay: ['85', '67', '16', '92'] }
const ent = (id, entryDate, betType, value, score, extra = {}) => ({ id, customerName: 'A', entryDate, value, score, result: '', betType, station: 'mb', ...extra })
const ctx = { rates: DEFAULT_RATES, customerRates: null, customerRegion: null }

test('định dạng ngày, số và tiền', () => {
  assert.deepEqual(dayLabel('2026-10-19'), { date: '19/10/2026', weekday: 'Thứ hai' })
  assert.equal(toNumber('1.500 đ'), 1.5)
  assert.equal(toNumber(''), 0)
  assert.equal(money(1234567.6), '1.234.568 đ')
})

test('chọn nhanh khoảng ngày và ô Ngày', () => {
  const now = new Date(2026, 9, 19)
  assert.deepEqual(presetRange('today', now), ['2026-10-19', '2026-10-19'])
  assert.deepEqual(presetRange('7', now), ['2026-10-13', '2026-10-19'])
  assert.deepEqual(presetRange('30', now), ['2026-09-20', '2026-10-19'])
  assert.deepEqual(presetRange('all', now), ['', ''])
  assert.equal(presetRange('', now), null)
  assert.equal(singleDayOf('2026-10-19', '2026-10-19'), '2026-10-19')
  assert.equal(singleDayOf('2026-10-13', '2026-10-19'), '')
  assert.equal(singleDayOf('', ''), '')
  assert.deepEqual(rangeForDay('2026-10-01'), ['2026-10-01', '2026-10-01', ''])
  assert.deepEqual(rangeForDay(''), ['', '', 'all'])
})

test('lọc số liệu theo khách và khoảng ngày; chưa chọn khách thì rỗng', () => {
  const list = [ent('1', '2026-10-18', 'lo', '12', '5'), ent('2', '2026-10-10', 'lo', '12', '5'), ent('3', '2026-10-18', 'lo', '12', '5', { customerName: 'B' })]
  assert.equal(filterEntries(list, { customer: '' }).length, 0)
  assert.equal(filterEntries(list, { customer: 'A' }).length, 2)
  assert.deepEqual(filterEntries(list, { customer: 'A', from: '2026-10-18', to: '2026-10-18' }).map((e) => e.id), ['1'])
  assert.deepEqual(filterEntries(list, { customer: 'A', from: '', to: '2026-10-10' }).map((e) => e.id), ['2'])
})

test('trạng thái kết quả xổ số của ngày', () => {
  const list = [ent('1', '2026-10-18', 'lo', '12', '5')]
  assert.equal(lotteryState('2026-10-18', list, {}), undefined)
  assert.equal(lotteryState('2026-10-18', list, { '2026-10-18|mb': null }), 'no')
  assert.equal(lotteryState('2026-10-18', list, { '2026-10-18|mb': draw }), 'yes')
  assert.equal(lotteryState('2026-10-18', [], {}), undefined)
})

test('gom ngày mới nhất trước; ngày mới nhất mở sẵn; điểm ra từ kết quả đã biết', () => {
  const list = [ent('1', '2026-10-17', 'lo', '12', '5'), ent('2', '2026-10-18', 'duoi', '15', '10'), ent('3', '2026-10-18', 'lo', '99', '10', { result: '7' })]
  const cache = { '2026-10-18|mb': draw }
  const days = buildDays(list, cache, {}, ctx)
  assert.deepEqual(days.map((d) => d.date), ['2026-10-18', '2026-10-17'])
  assert.equal(days[0].lottery, 'yes')
  assert.equal(days[0].settled, true)
  assert.equal(days[1].lottery, undefined)
  assert.equal(days[1].settled, false)
  assert.equal(days[0].totalIn, 20)
  assert.ok(days[0].totalOut > 0) // 15 trúng giải Bảy lô/đuôi tuỳ cấu hình
  assert.equal(days[1].totalOut, 0)
  // chưa có kết quả thì dùng số đã lưu
  assert.equal(entryOut(list[2], undefined, {}, ctx), 7)
  // đã tính xong thì lấy số đã lưu của lần tính
  assert.equal(entryOut(list[2], { state: 'saved', value: 123 }, cache, ctx), 123)
  assert.equal(isOpen({}, '2026-10-18', days), true)
  assert.equal(isOpen({}, '2026-10-17', days), false)
  assert.equal(isOpen({ '2026-10-17': true }, '2026-10-17', days), true)
  assert.equal(isOpen({ '2026-10-18': false }, '2026-10-18', days), false)
  assert.equal(filterMissing(days, false).length, 2)
  assert.deepEqual(filterMissing([{ lottery: 'no' }, { lottery: 'yes' }], true), [{ lottery: 'no' }])
  const t = totalsOf(days)
  assert.equal(t.days, 2)
  assert.equal(t.rows, 3)
  assert.equal(t.hasSettled, true)
  assert.equal(t.totalIn, 25)
})

test('khóa tính lại thay đổi khi mở ngày, đổi khách hoặc bấm Tính lại', () => {
  const days = [{ date: 'b' }, { date: 'a' }]
  assert.equal(openKey(days, days, {}, 'A', 0), 'b#A#0')
  assert.equal(openKey(days, days, { a: true }, 'A', 1), 'b|a#A#1')
  assert.equal(openKey(days, days, { b: false }, 'A', 0), '#A#0')
})

test('tổng tiền theo ngày dùng cùng summarize với ScoringSummary', () => {
  const d = { date: '2026-10-18', entries: [ent('1', '2026-10-18', 'lo', '41', '10'), ent('2', '2026-10-18', 'lo', '77', '10')] }
  const get = (date, st) => (st === 'mb' ? draw : undefined)
  const s = summarize([d], DEFAULT_RATES, null, get, { customerRegion: null })
  assert.ok(s.sent.money > 0)
  assert.equal(s.settled.lots, 2)
  assert.equal(s.remaining, s.settled.money - s.won.money)
  const unknown = summarize([d], DEFAULT_RATES, null, () => undefined, {})
  assert.equal(unknown.pending.lots, 2)
  assert.equal(unknown.remaining, 0)
})

test('computeOne: chưa có kết quả thì không ghi; có thì PATCH một lần, đúng số thì bỏ qua', async () => {
  const patches = []
  const deps = (lr) => ({ fetchLottery: async () => lr, patch: async (id, body) => (patches.push([id, body]), { id, result: body.result }) })
  const e1 = ent('1', '2026-10-18', 'lo', '41', '10')
  let r = await computeOne(e1, ctx, deps(null))
  assert.equal(r.status.state, 'no-lottery')
  assert.equal(patches.length, 0)
  r = await computeOne(e1, ctx, deps(draw))
  assert.equal(r.status.state, 'saved')
  assert.equal(patches.length, 1)
  assert.deepEqual(patches[0], ['1', { result: String(r.status.value) }])
  assert.equal(r.updated.id, '1')
  const same = { ...e1, result: String(r.status.value) }
  r = await computeOne(same, ctx, deps(draw))
  assert.equal(r.status.state, 'saved')
  assert.equal(r.updated, undefined)
  assert.equal(patches.length, 1)
  // lỗi lưu
  r = await computeOne(e1, ctx, { fetchLottery: async () => draw, patch: async () => { throw new Error('') } })
  assert.equal(r.status.state, 'error')
  assert.equal(r.status.error, 'Không lưu được')
  assert.equal(scoreEntryAll(e1, [['mb', draw]], ctx), r.status.value)
})

test('tên khu vực, thông báo và dòng rỗng', () => {
  const deps = { isRegionCode: (c) => c === 'mt', regionOf: () => ({ name: 'Miền Trung' }), stationName: (c) => `Đài ${c}` }
  assert.equal(areaName('', deps), 'Miền Bắc')
  assert.equal(areaName('mb', deps), 'Miền Bắc')
  assert.equal(areaName('mt', deps), 'Miền Trung')
  assert.equal(areaName('mn-tphcm', deps), 'Đài mn-tphcm')
  assert.equal(addedNotice('An', '2026-10-19', '3'), 'Đã thêm 3 số liệu cho An ngày 19/10/2026. Điểm ra được tính theo kết quả xổ số đã nhập.')
  assert.equal(addedNotice('An', null, '3'), 'Đã thêm 3 số liệu cho An. Điểm ra được tính theo kết quả xổ số đã nhập.')
  assert.equal(emptyMessage({ onlyMissing: false, rangeCount: 0, customerHasEntries: true }), 'Không có số liệu nào trong khoảng ngày này. Chọn "Tất cả" để xem lịch sử.')
  assert.equal(emptyMessage({ onlyMissing: false, rangeCount: 0, customerHasEntries: false }), 'Khách hàng này chưa có số liệu nào.')
  assert.ok(emptyMessage({ onlyMissing: true, rangeCount: 0, customerHasEntries: true }).startsWith('Không có ngày nào thiếu'))
  assert.equal(PAGE_DAYS, 10)
})

test('Xóa số liệu: thân yêu cầu, phạm vi và kiểm tra nhập', () => {
  const base = { scope: 'customer', customerName: 'An', from: '2026-10-19', to: '2026-10-19', keepDays: '0' }
  assert.deepEqual(deleteBody(base, { dryRun: true }), { customerName: 'An', dateFrom: '2026-10-19', dateTo: '2026-10-19', keepDays: 0, dryRun: true })
  assert.equal(hasLimit({ ...base, scope: 'all', from: '', to: '' }), false)
  assert.deepEqual(deleteBody({ ...base, scope: 'all', from: '', to: '' }), { customerName: null, dateFrom: null, dateTo: null, keepDays: 0, allDataConfirmed: true })
  assert.equal(hasLimit({ ...base, scope: 'all', from: '', to: '', keepDays: '3' }), true)
  assert.equal(scopeText(base), 'khách "An", ngày 19/10/2026')
  assert.equal(scopeText({ ...base, from: '2026-10-01', keepDays: '7' }), 'khách "An", ngày 01/10/2026 đến 19/10/2026, giữ lại 7 ngày gần nhất')
  assert.equal(scopeText({ ...base, scope: 'all', from: '', to: '2026-10-19' }), 'TẤT CẢ khách, ngày ... đến 19/10/2026')
  assert.equal(scopeText({ ...base, scope: 'all', from: '', to: '' }), 'TẤT CẢ khách, mọi ngày')
  const all = { ...base, scope: 'all', from: '', to: '' }
  assert.equal(deleteProblem(all, false, 'x'), 'Hãy tích ô xác nhận xoá toàn bộ số liệu')
  assert.equal(deleteProblem(all, true, ''), 'Nhập mật khẩu đăng nhập để xác nhận')
  assert.equal(deleteProblem(base, false, 'x'), '')
})

test('Đặt lịch xóa: chu kỳ, lần chạy đầu, kiểm tra và nội dung xác nhận', () => {
  const f = { customerName: '', dateFrom: '', dateTo: '', repeat: 'none', customN: '2', customUnit: 'day', keepDays: '0', runAt: '2026-10-20T08:00', password: 'p' }
  assert.equal(repeatValue(f), null)
  assert.deepEqual(repeatValue({ ...f, repeat: '10d' }), { every: 10, unit: 'day' })
  assert.deepEqual(repeatValue({ ...f, repeat: 'custom', customN: '3.9', customUnit: 'week' }), { every: 3, unit: 'week' })
  const now = new Date(2026, 9, 19, 9, 5)
  assert.equal(defaultRunAt(f, now), '2026-10-20T09:05')
  assert.equal(defaultRunAt({ ...f, repeat: '1w' }, now), '2026-10-26T09:05')
  assert.equal(defaultRunAt({ ...f, repeat: '1m' }, now), '2026-11-19T09:05')
  assert.equal(toLocalInput(new Date(2026, 0, 2, 3, 4)), '2026-01-02T03:04')
  assert.equal(buildScheduleBody({ ...f, runAt: '' }).error, 'Vui lòng chọn thời điểm xoá')
  assert.equal(buildScheduleBody({ ...f, repeat: 'custom', customN: '400' }).error, 'Chu kỳ lặp phải từ 1 đến 365')
  assert.equal(buildScheduleBody({ ...f, keepDays: '4000' }).error, 'Số ngày giữ lại phải từ 0 đến 3650')
  assert.equal(buildScheduleBody({ ...f, password: '' }).error, 'Nhập mật khẩu đăng nhập để xác nhận')
  const once = buildScheduleBody({ ...f, customerName: 'An', dateFrom: '2026-10-01', keepDays: '5' })
  assert.equal(once.body.kind, 'data')
  assert.equal(once.body.customerName, 'An')
  assert.equal(once.body.dateFrom, '2026-10-01')
  assert.equal(once.body.dateTo, undefined)
  assert.equal(once.body.keepDays, 5)
  assert.equal(once.body.repeat, undefined)
  const rep = buildScheduleBody({ ...f, repeat: '1w', dateFrom: '2026-10-01' })
  assert.deepEqual(rep.body.repeat, { every: 1, unit: 'week' })
  assert.equal('dateFrom' in rep.body, false)
  assert.equal('keepDays' in rep.body, false)
  const msg = confirmMessage({ scopeText: 'Xoá số liệu của mọi khách' }, rep.body, rep.repeat)
  assert.ok(msg.startsWith('CẢNH BÁO: Xoá số liệu của mọi khách\n\nLặp lại mỗi 1 tuần.\n\nThời điểm xoá lần đầu: '))
  assert.ok(msg.endsWith('Bạn có thể huỷ lịch trước thời điểm này.'))
  const full = confirmMessage({ scopeText: 'Lặp mỗi tuần, lần đầu lúc 20:00, xoá ngay 3 số liệu', willDeleteNow: 3 }, rep.body, rep.repeat)
  assert.equal(full, 'CẢNH BÁO: Lặp mỗi tuần, lần đầu lúc 20:00, xoá ngay 3 số liệu\n\nBạn có thể huỷ lịch trước thời điểm này.')
  assert.ok(confirmMessage({ scopeText: 'x', willDeleteNow: 4 }, once.body, null).includes('Nếu chạy ngay bây giờ sẽ xoá 4 số liệu.'))
})

test('mô tả lịch xoá', () => {
  assert.equal(describe({ kind: 'data', customerName: 'An', dateFrom: '2026-10-01', dateTo: '', keepDays: 3 }), 'Số liệu đã nhập của khách "An", ngày 2026-10-01 đến ..., giữ lại 3 ngày gần nhất')
  assert.equal(describe({ kind: 'data' }), 'Số liệu đã nhập của mọi khách, mọi ngày')
  assert.equal(describe({ kind: 'chat', chatScope: 'images', ttlSeconds: 86400, friendName: 'Bình' }), 'Ảnh cũ hơn 1 ngày trong cuộc trò chuyện với Bình')
  assert.equal(describe({ kind: 'chat', ttlSeconds: 5 }), 'Tin nhắn & tệp cũ hơn 5 giây trong cuộc trò chuyện với ?')
  assert.ok(statusText({ status: 'done', deletedCount: 4, executedAt: '2026-10-19T01:00:00Z' }).startsWith('Đã xoá 4 mục lúc '))
  assert.ok(statusText({ kind: 'chat', runAt: '2026-10-19T01:00:00Z', deletedCount: 2 }).includes('(đã xoá 2 mục)'))
  assert.ok(statusText({ kind: 'data', runAt: '2026-10-19T01:00:00Z' }).startsWith('Sẽ xoá lúc '))
})
