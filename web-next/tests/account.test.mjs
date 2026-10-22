// Tài khoản: tabs, kiểm tra biểu mẫu, mã ID, gói & thanh toán, lịch xoá, phiên bản app, biểu đồ thống kê (logic thuần).
import test from 'node:test'
import assert from 'node:assert/strict'
import * as A from '../src/features/account/accountLogic.js'
import { loadMoney } from '../src/features/account/statsLoad.js'
import { moneyByDate } from '../src/lib/statsMoney.js'
import { DEFAULT_RATES } from '../src/lib/scoringConfig.js'
import { buildSeries, periodTotals, rangeTotals } from '../src/lib/statsSeries.js'

test('tabs: admin has no Thống kê / Gói; ?tab= picks the open tab', () => {
  const user = A.tabsFor(false)
  assert.deepEqual(user.map((t) => t.key), ['stats', 'profile', 'devices', 'packages', 'data'])
  const admin = A.tabsFor(true)
  assert.deepEqual(admin.map((t) => t.key), ['profile', 'devices', 'data'])
  assert.equal(A.initialTab(user, null), 'stats')
  assert.equal(A.initialTab(admin, null), 'profile')
  assert.equal(A.initialTab(user, 'packages'), 'packages')
  assert.equal(A.initialTab(admin, 'packages'), 'profile') // not available -> first
  assert.equal(A.initialTab(user, 'security'), 'profile') // old name
  assert.equal(A.initialTab(user, 'zzz'), 'stats')
  assert.deepEqual(A.ALL_TABS.map((t) => t.label), ['Thống kê', 'Hồ sơ', 'Thiết bị & riêng tư', 'Gói & Thanh toán', 'Dữ liệu'])
})

test('tab keys wrap around', () => {
  const t = A.tabsFor(false)
  assert.equal(A.nextTabKey(t, 'data', 'ArrowRight'), 'stats')
  assert.equal(A.nextTabKey(t, 'stats', 'ArrowLeft'), 'data')
  assert.equal(A.nextTabKey(t, 'profile', 'ArrowRight'), 'devices')
  assert.equal(A.nextTabKey(t, 'profile', 'Enter'), null)
})

test('profile check: required name, 3+ chars username, password only when the username changes', () => {
  const user = { username: 'son' }
  assert.equal(A.profileCheck({ name: ' ', username: 'son', currentPassword: '' }, user).error, 'Vui lòng nhập tên hiển thị')
  assert.equal(A.profileCheck({ name: 'A', username: 'ab', currentPassword: '' }, user).error, 'Tên đăng nhập phải có ít nhất 3 ký tự')
  assert.equal(A.profileCheck({ name: 'A', username: 'sonny', currentPassword: '' }, user).error, 'Nhập mật khẩu hiện tại để đổi tên đăng nhập')
  assert.deepEqual(A.profileCheck({ name: ' A ', username: 'son', currentPassword: '' }, user).payload, { name: 'A', username: 'son' })
  assert.deepEqual(A.profileCheck({ name: 'A', username: 'sonny', currentPassword: 'x' }, user).payload, { name: 'A', username: 'sonny', currentPassword: 'x' })
})

test('password forms and wipe wording', () => {
  assert.equal(A.passwordCheck({ currentPassword: '', newPassword: 'a', confirmPassword: 'a' }), 'Vui lòng nhập đầy đủ thông tin')
  assert.equal(A.passwordCheck({ currentPassword: 'o', newPassword: 'a', confirmPassword: 'b' }), 'Mật khẩu mới nhập lại không khớp')
  assert.equal(A.passwordCheck({ currentPassword: 'o', newPassword: 'a', confirmPassword: 'a' }), '')
  assert.equal(A.secondCheck({ currentPassword: 'o', secondPassword: '' }), 'Vui lòng nhập đầy đủ thông tin')
  assert.equal(A.wipeCheck({ currentPassword: 'o', wipePassword: 'w' }), '')
  assert.equal(A.wipeVerb({ hasWipePassword: true }), 'đổi')
  assert.equal(A.wipeVerb({}), 'đặt')
  assert.match(A.deleteAllMessage(), /^CẢNH BÁO: Thao tác này sẽ xoá vĩnh viễn: số liệu đã nhập, .*Bạn có chắc chắn muốn tiếp tục\?$/)
})

test('customer codes: limit and payload (empty digits -> server picks)', () => {
  assert.equal(A.atCodeLimit([1, 2, 3, 4, 5], 5), true)
  assert.equal(A.atCodeLimit([1], 5), false)
  assert.deepEqual(A.newCodePayload(' ', ' '), { code: undefined, label: undefined })
  assert.deepEqual(A.newCodePayload(' 123789 ', ' K22 '), { code: '123789', label: 'K22' })
})

test('app version: format, order and https rules', () => {
  const f = (o) => ({ latestVersion: '', minVersion: '', downloadUrl: '', notes: '', ...o })
  assert.equal(A.versionProblem(f({})), '')
  assert.equal(A.versionProblem(f({ latestVersion: '1.2' })), 'Phiên bản mới nhất phải có dạng 1.2.3')
  assert.equal(A.versionProblem(f({ latestVersion: '1.2.3', minVersion: 'x' })), 'Phiên bản tối thiểu phải có dạng 1.2.3')
  assert.equal(A.versionProblem(f({ minVersion: '1.0.0' })), 'Hãy nhập phiên bản mới nhất trước khi đặt phiên bản tối thiểu')
  assert.equal(A.versionProblem(f({ latestVersion: '1.2.0', minVersion: '1.10.0' })), 'Phiên bản tối thiểu không được lớn hơn phiên bản mới nhất')
  assert.equal(A.versionProblem(f({ latestVersion: '1.10.0', minVersion: '1.2.0' })), '') // numeric, not text, order
  assert.equal(A.versionProblem(f({ downloadUrl: 'http://x.vn' })), 'Đường dẫn tải phải bắt đầu bằng https://')
  assert.equal(A.versionProblem(f({ downloadUrl: 'https://x.vn/a.apk' })), '')
  assert.equal(A.versionProblem(f({ notes: 'x'.repeat(501) })), 'Ghi chú tối đa 500 ký tự')
  assert.deepEqual(A.versionForm(null), f({}))
})

test('packages: labels, pending request, VietQR link', () => {
  assert.equal(A.formatVnd(1500000), '1.500.000đ')
  assert.equal(A.formatDate(null), '-')
  assert.equal(A.statusLabel('pending'), 'Đang chờ duyệt')
  assert.equal(A.statusLabel('weird'), 'weird')
  assert.equal(A.statusChipClass('approved'), 'chip-accent')
  assert.equal(A.statusChipClass('cancelled'), '')
  const plans = [{ type: 'm1', label: 'Gói 1 tháng' }]
  assert.equal(A.planLabel(plans, 'm1'), 'Gói 1 tháng')
  assert.equal(A.planLabel(plans, 'zz'), 'zz')
  const reqs = [{ id: 1, status: 'approved' }, { id: 2, status: 'pending', amount: 99000, referenceCode: 'MB123', packageType: 'm1' }]
  assert.equal(A.pendingOf(reqs).id, 2)
  assert.equal(A.pendingOf([reqs[0]]), null)
  const bank = { bankBin: '970422', bankAccountNumber: '0123', bankAccountHolder: 'NGUYEN A' }
  assert.equal(A.qrUrlOf(bank, null, {}), null)
  assert.equal(A.qrUrlOf({ bankAccountNumber: '1' }, reqs[1], {}), null)
  const url = A.qrUrlOf(bank, reqs[1], { username: 'u' })
  assert.ok(url.startsWith('https://img.vietqr.io/image/970422-0123-compact2.png?'))
  assert.ok(url.includes('amount=99000') && url.includes('addInfo=MB123') && url.includes('accountName=NGUYEN+A'))
  assert.ok(A.qrUrlOf(bank, { ...reqs[1], referenceCode: '' }, { username: 'u' }).includes('addInfo=u+m1'))
})

test('deletion schedule: repeat value, default first run, validation', () => {
  const base = { customerName: '', dateFrom: '', dateTo: '', repeat: 'none', customN: 2, customUnit: 'day', keepDays: 0, runAt: '2026-10-20T08:00', password: 'pw' }
  assert.equal(A.repeatValue(base), null)
  assert.deepEqual(A.repeatValue({ ...base, repeat: '1w' }), { every: 1, unit: 'week' })
  assert.deepEqual(A.repeatValue({ ...base, repeat: '10d' }), { every: 10, unit: 'day' })
  assert.deepEqual(A.repeatValue({ ...base, repeat: '1m' }), { every: 1, unit: 'month' })
  assert.deepEqual(A.repeatValue({ ...base, repeat: 'custom', customN: '3.7', customUnit: 'week' }), { every: 3, unit: 'week' })
  const now = new Date(2026, 9, 19, 9, 30)
  assert.equal(A.defaultRunAt(base, now), '2026-10-20T09:30') // one-off: tomorrow
  assert.equal(A.defaultRunAt({ ...base, repeat: '1w' }, now), '2026-10-26T09:30')
  assert.equal(A.defaultRunAt({ ...base, repeat: '10d' }, now), '2026-10-29T09:30')
  assert.equal(A.defaultRunAt({ ...base, repeat: '1m' }, now), '2026-11-19T09:30')
  assert.equal(A.defaultRunAt({ ...base, repeat: 'custom', customN: 0 }, now), '2026-10-20T09:30') // invalid every -> like one-off

  assert.equal(A.scheduleCheck({ ...base, runAt: '' }).error, 'Vui lòng chọn thời điểm xoá')
  assert.equal(A.scheduleCheck({ ...base, repeat: 'custom', customN: 400 }).error, 'Chu kỳ lặp phải từ 1 đến 365')
  assert.equal(A.scheduleCheck({ ...base, keepDays: 4000 }).error, 'Số ngày giữ lại phải từ 0 đến 3650')
  assert.equal(A.scheduleCheck({ ...base, password: '' }).error, 'Nhập mật khẩu đăng nhập để xác nhận')
  const one = A.scheduleCheck({ ...base, customerName: 'An', dateFrom: '2026-10-01', dateTo: '2026-10-10', keepDays: 5 })
  assert.deepEqual(Object.keys(one.body).sort(), ['customerName', 'dateFrom', 'dateTo', 'keepDays', 'kind', 'runAt'])
  assert.equal(one.body.runAt, new Date('2026-10-20T08:00').toISOString())
  const rep = A.scheduleCheck({ ...base, repeat: '1w', dateFrom: '2026-10-01' })
  assert.deepEqual(rep.body.repeat, { every: 1, unit: 'week' })
  assert.equal(rep.body.dateFrom, undefined) // a repeating schedule never carries dates
  assert.equal(rep.body.keepDays, undefined)
})

test('deletion schedule: texts', () => {
  assert.equal(A.describeSchedule({ kind: 'data', customerName: 'An', dateFrom: '2026-10-01', keepDays: 7 }), 'Số liệu đã nhập của khách "An", ngày 2026-10-01 đến ..., giữ lại 7 ngày gần nhất')
  assert.equal(A.describeSchedule({ kind: 'data' }), 'Số liệu đã nhập của mọi khách, mọi ngày')
  assert.equal(A.describeSchedule({ kind: 'chat', chatScope: 'images', ttlSeconds: 86400, friendName: 'Lan' }), 'Ảnh cũ hơn 1 ngày trong cuộc trò chuyện với Lan')
  assert.equal(A.describeSchedule({ kind: 'chat', ttlSeconds: 5 }), 'Tin nhắn & tệp cũ hơn 5 giây trong cuộc trò chuyện với ?')
  assert.equal(A.repeatText({ every: 2, unit: 'week' }), '2 tuần')
  assert.equal(A.repeatText(null), '')
  assert.match(A.scheduleStatusText({ status: 'done', deletedCount: 4, executedAt: '2026-10-19T01:00:00Z' }), /^Đã xoá 4 mục lúc /)
  assert.match(A.scheduleStatusText({ status: 'pending', kind: 'chat', runAt: '2026-10-19T01:00:00Z', deletedCount: 2 }), /^Đang áp dụng từ .* \(đã xoá 2 mục\)$/)
  assert.match(A.scheduleStatusText({ status: 'pending', kind: 'data', runAt: '2026-10-19T01:00:00Z' }), /^Sẽ xoá lúc /)
  const body = { runAt: '2026-10-20T01:00:00.000Z' }
  // the server's text already complete: shown as is + the cancel hint
  const full = A.scheduleConfirmMessage({ scopeText: 'Xoá mọi số liệu, lặp lại mỗi 1 tuần, lần đầu lúc 20/10, xoá ngay 3 mục' }, { every: 1, unit: 'week' }, body)
  assert.equal(full, 'CẢNH BÁO: Xoá mọi số liệu, lặp lại mỗi 1 tuần, lần đầu lúc 20/10, xoá ngay 3 mục\n\nBạn có thể huỷ lịch trước thời điểm này.')
  // older server: the missing pieces are added
  const old = A.scheduleConfirmMessage({ scopeText: 'Xoá số liệu', willDeleteNow: 9 }, { every: 1, unit: 'week' }, body)
  assert.match(old, /Lặp lại mỗi 1 tuần\./)
  assert.match(old, /Thời điểm xoá lần đầu: /)
  assert.match(old, /Nếu chạy ngay bây giờ sẽ xoá 9 số liệu\./)
  assert.match(A.scheduleConfirmMessage({ scopeText: 'x' }, null, body), /Thời điểm xoá: /)
})

test('stats: tones, delta, bar plot geometry', () => {
  assert.equal(A.statTone('profit', -1), 'neg')
  assert.equal(A.statTone('profit', 0), 'pos')
  assert.equal(A.statTone('vao', -1), '')
  assert.equal(A.barTone('vao', 5), 'main')
  assert.equal(A.barTone('profit', -5), 'neg')
  assert.equal(A.signed(1500), '+1.500')
  assert.equal(A.signed(-1500), '-1.500')
  assert.deepEqual(A.deltaOf({ current: 150, previous: 100 }), { delta: 50, pct: 50 })
  assert.deepEqual(A.deltaOf({ current: 10, previous: 0 }), { delta: 10, pct: null })
  assert.deepEqual(A.deltaOf({ current: 10, previous: null }), { delta: null, pct: null })
  assert.deepEqual(A.STAT_METRICS.map((m) => m.label), ['Tiền gửi', 'Tiền trúng', 'Lợi nhuận'])
  assert.deepEqual(A.STAT_UNITS.map((u) => u.range), ['30 ngày gần nhất', '12 tuần gần nhất', '12 tháng gần nhất', '5 năm gần nhất'])

  const series = Array.from({ length: 30 }, (_, i) => ({ key: 'k' + i, label: String(i), full: 'd' + i, value: i === 3 ? -50 : i * 10 }))
  const p = A.barPlot(series, 'profit', 640)
  assert.equal(p.bars.length, 30)
  assert.ok(p.bars.every((b) => b.w === p.bars[0].w && b.w >= 3 && b.w <= 26))
  assert.equal(p.ticks.length, 3) // max, 0, min (a negative value exists)
  assert.ok(p.bars[3].y >= p.zeroY - 0.001) // negative bar hangs below the zero line
  assert.ok(p.bars[10].y + p.bars[10].h <= p.zeroY + 0.001)
  const flat = A.barPlot([{ key: 'a', label: 'a', full: 'a', value: 0 }], 'vao', 300)
  assert.equal(flat.bars[0].h, 0) // zero value: no bar
  // same bar width whatever the period count, as long as there are at most 30 bars
  const w5 = A.barPlot(series.slice(0, 5), 'vao', 640).bars[0].w
  const w30 = A.barPlot(series, 'vao', 640).bars[0].w
  assert.equal(w5, w30) // sized for the densest period (30), so switching the period never resizes the bars
  assert.equal(A.tipLeftPct(0, 640), '16%')
  assert.equal(A.tipLeftPct(640, 640), '84%')
})

test('stats chart labels and numbers (StatsChart)', () => {
  assert.equal(A.niceMax(0), 4)
  assert.equal(A.niceMax(1.2), 2)
  assert.equal(A.niceMax(37), 50)
  assert.equal(A.niceMax(870), 1000)
  assert.equal(A.shortDate('2026'), '2026')
  assert.equal(A.shortDate('2026-10'), '10/26')
  assert.equal(A.shortDate('2026-10-19'), '19/10')
  assert.equal(A.longDate('2026'), 'Năm 2026')
  assert.equal(A.longDate('2026-10'), 'Tháng 10/2026')
  assert.equal(A.longDate('2026-10-19'), '19/10/2026')
  assert.equal(A.longDate('2026-10-19', 'week'), 'Tuần 19/10 – 25/10/2026')
  assert.equal(A.shortValue(2_500_000, true), '2.5tr')
  assert.equal(A.shortValue(12_000, true), '12k')
  assert.equal(A.shortValue(950, true), '950')
  assert.equal(A.shortValue(2.26, false), '2.3')
  assert.equal(A.fullValue(1234567, true), '1.234.567 đ')
  assert.equal(A.fullValue(7, false), '7')
  const pts = Array.from({ length: 30 }, (_, i) => ({ date: `2026-09-${String(i + 1).padStart(2, '0')}`, value: i }))
  const labels = A.chartLabels(pts, 280)
  assert.equal(labels.at(-1).i, 29) // the last point is always labelled
  assert.ok(labels.length < 30)
})

test('loadMoney: customers + entries + rates + results, 4 workers, failures count as "chưa tính"', async () => {
  const calls = []
  const api = {
    get: async (p) => {
      calls.push(p)
      if (p === '/me/scoring-settings') return { rates: {} } // empty -> DEFAULT_RATES
      if (p.startsWith('/lottery-results?date=2026-10-11')) return { result: null }
      throw new Error('offline')
    },
  }
  const entries = [{ id: '1', customerName: 'An', entryDate: '2026-10-11', value: '12', score: '100', result: '0', betType: 'lo', station: 'mb' }]
  const out = await loadMoney({
    api,
    cachedGet: async () => ({ customers: [{ name: 'An', scoringRates: null, homeRegion: null }] }),
    loadAllEntries: async () => ({ entries }),
    loadStations: async () => { throw new Error('x') }, // a stations failure is ignored
    DEFAULT_RATES,
    moneyByDate,
  })
  assert.equal(out.plays, 1)
  assert.equal(out.customers, 1)
  assert.ok(calls.some((c) => c.startsWith('/lottery-results?date=2026-10-11&station=')))
  const day = out.byDate['2026-10-11']
  assert.ok(day.sent > 0)
  assert.equal(day.settled, 0) // no result -> not in the profit
  assert.ok(day.pending > 0)
})

test('series for the chart follow the picked metric', () => {
  const byDate = { '2026-10-18': { sent: 100, settled: 80, won: 30, pending: 0, pendingLots: 0 } }
  const mk = (metric) => rangeTotals(Object.entries(byDate).map(([entryDate, m]) => ({ entryDate, score: String(metric === 'profit' ? m.settled : m.sent), result: String(m.won) })), { unit: 'day', metric, now: new Date(2026, 9, 19) })
  assert.ok(buildSeries([], { unit: 'day', metric: 'vao', now: new Date(2026, 9, 19) }).length === 30)
  assert.equal(typeof mk('vao').current, 'number')
})

test('Tổng quan: ngày là hôm nay, tuần là tuần này, tháng là tháng này, năm là năm nay; so với kỳ liền trước', () => {
  const now = new Date(2026, 9, 21) // thứ Tư 21/10/2026
  const es = [
    { entryDate: '2026-10-21', score: '100', result: '30' }, // hôm nay
    { entryDate: '2026-10-20', score: '40', result: '0' }, // hôm qua = cùng tuần, cùng tháng
    { entryDate: '2026-10-15', score: '10', result: '0' }, // tuần trước
    { entryDate: '2026-09-30', score: '5', result: '0' }, // tháng trước
    { entryDate: '2025-06-01', score: '7', result: '0' }, // năm trước
  ]
  assert.deepEqual(periodTotals(es, { unit: 'day', metric: 'vao', now }), { current: 100, previous: 40 })
  assert.deepEqual(periodTotals(es, { unit: 'day', metric: 'profit', now }), { current: 70, previous: 40 })
  assert.deepEqual(periodTotals(es, { unit: 'week', metric: 'vao', now }), { current: 140, previous: 10 })
  assert.deepEqual(periodTotals(es, { unit: 'month', metric: 'vao', now }), { current: 150, previous: 5 })
  assert.deepEqual(periodTotals(es, { unit: 'year', metric: 'ra', now }), { current: 30, previous: 0 })
  assert.equal(periodTotals(es, { unit: 'year', metric: 'ra', now }).previous, 0 || 0)
  // kỳ trước không có số liệu: không so sánh
  assert.equal(periodTotals([{ entryDate: '2026-10-21', score: '5', result: '0' }], { unit: 'day', metric: 'vao', now }).previous, null)
  assert.deepEqual(A.STAT_UNITS.map((u) => u.current), ['Hôm nay', 'Tuần này', 'Tháng này', 'Năm nay'])
})
