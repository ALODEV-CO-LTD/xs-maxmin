// Pure logic of the Tài khoản screen (port of the <script> parts of AccountView.vue, PrivacySettings.vue,
// AppVersionPanel.vue, PackagesView.vue, DeletionSchedules.vue, AccountStats.vue, StatsChart.vue). No React here so
// tests/account.test.mjs can run it in node.
import { tickEvery, tickIndices } from '../../lib/statsSeries.js'

// ---------- tabs ----------
export const ALL_TABS = [
  { key: 'stats', label: 'Thống kê' },
  { key: 'profile', label: 'Hồ sơ' },
  { key: 'devices', label: 'Thiết bị & riêng tư' },
  { key: 'packages', label: 'Gói & Thanh toán' },
  { key: 'data', label: 'Dữ liệu' },
]
// Thống kê and Gói & Thanh toán are for customer accounts only (an admin has no customers, entries or package).
export function tabsFor(isAdmin) {
  return ALL_TABS.filter((t) => !['stats', 'packages'].includes(t.key) || !isAdmin)
}
// ?tab= -> the open tab ('security' was the old name of Hồ sơ).
export function initialTab(tabs, queryTab) {
  return tabs.some((t) => t.key === queryTab) ? queryTab : queryTab === 'security' ? 'profile' : tabs[0].key
}
// Arrow keys move between tabs (wrapping); null for any other key.
export function nextTabKey(tabs, current, key) {
  const i = tabs.findIndex((t) => t.key === current)
  const next = key === 'ArrowRight' ? i + 1 : key === 'ArrowLeft' ? i - 1 : null
  if (next === null) return null
  return tabs[(next + tabs.length) % tabs.length].key
}

export function fmtSeen(iso) {
  return iso ? new Date(iso).toLocaleString('vi-VN') : '-'
}

// ---------- profile / passwords ----------
export const usernameChanged = (form, user) => form.username.trim() !== (user?.username || '')

// Returns { error } or { payload }.
export function profileCheck(form, user) {
  const name = form.name.trim()
  const username = form.username.trim()
  const changed = username !== (user?.username || '')
  if (!name) return { error: 'Vui lòng nhập tên hiển thị' }
  if (username.length < 3) return { error: 'Tên đăng nhập phải có ít nhất 3 ký tự' }
  if (changed && !form.currentPassword) return { error: 'Nhập mật khẩu hiện tại để đổi tên đăng nhập' }
  const payload = { name, username }
  if (changed) payload.currentPassword = form.currentPassword
  return { payload }
}

export function passwordCheck(f) {
  if (!f.currentPassword || !f.newPassword) return 'Vui lòng nhập đầy đủ thông tin'
  if (f.newPassword !== f.confirmPassword) return 'Mật khẩu mới nhập lại không khớp'
  return ''
}
export const secondCheck = (f) => (!f.currentPassword || !f.secondPassword ? 'Vui lòng nhập đầy đủ thông tin' : '')
export const wipeCheck = (f) => (!f.currentPassword || !f.wipePassword ? 'Vui lòng nhập đầy đủ thông tin' : '')
export const wipeVerb = (user) => (user?.hasWipePassword ? 'đổi' : 'đặt')

// Must match backend/lib/src/data_wipe.dart (the single definition of the scope).
export const WIPE_DELETES = 'số liệu đã nhập, danh sách khách hàng, mẫu cú pháp, lịch xoá tự động, nhật ký cuộc gọi, tin nhắn phản hồi với Admin, lịch sử giao dịch và các yêu cầu thanh toán chưa duyệt'
export const WIPE_KEEPS = 'Tài khoản, gói dịch vụ, danh sách bạn bè, tin nhắn trò chuyện với bạn bè, Mã ID và cấu hình tính điểm được giữ nguyên.'
export const deleteAllMessage = () => `CẢNH BÁO: Thao tác này sẽ xoá vĩnh viễn: ${WIPE_DELETES}. ${WIPE_KEEPS} Bạn có chắc chắn muốn tiếp tục?`

// ---------- customer codes ----------
export const atCodeLimit = (codes, maxCodes) => codes.length >= maxCodes
// Empty digits -> the server picks a random unique one.
export const newCodePayload = (code, label) => ({ code: code.trim() || undefined, label: label.trim() || undefined })

// ---------- privacy ----------
export const IDLE_OPTIONS = [
  { value: 0, label: 'Tắt' },
  { value: 1, label: '1 phút' },
  { value: 5, label: '5 phút' },
  { value: 15, label: '15 phút' },
  { value: 30, label: '30 phút' },
]
export const HIDE_OPTIONS = [
  { value: 0, label: 'Tắt' },
  { value: 30, label: 'Sau 30 giây' },
  { value: 60, label: 'Sau 1 phút' },
  { value: 300, label: 'Sau 5 phút' },
]

// ---------- app version (admin) ----------
const VERSION = /^\d{1,4}\.\d{1,4}\.\d{1,4}$/
const parts = (v) => v.split('.').map(Number)
export function cmpVersion(a, b) {
  const x = parts(a)
  const y = parts(b)
  for (let i = 0; i < 3; i++) if (x[i] !== y[i]) return x[i] < y[i] ? -1 : 1
  return 0
}
export function versionProblem(form) {
  const l = form.latestVersion.trim()
  const m = form.minVersion.trim()
  if (l && !VERSION.test(l)) return 'Phiên bản mới nhất phải có dạng 1.2.3'
  if (m && !VERSION.test(m)) return 'Phiên bản tối thiểu phải có dạng 1.2.3'
  if (m && !l) return 'Hãy nhập phiên bản mới nhất trước khi đặt phiên bản tối thiểu'
  if (l && m && cmpVersion(m, l) > 0) return 'Phiên bản tối thiểu không được lớn hơn phiên bản mới nhất'
  const u = form.downloadUrl.trim()
  if (u && !/^https:\/\/\S+$/.test(u)) return 'Đường dẫn tải phải bắt đầu bằng https://'
  if (form.notes.length > 500) return 'Ghi chú tối đa 500 ký tự'
  return ''
}
export const versionForm = (res) => ({
  latestVersion: res?.latestVersion || '',
  minVersion: res?.minVersion || '',
  downloadUrl: res?.downloadUrl || '',
  notes: res?.notes || '',
})

// ---------- packages & payments ----------
export const formatVnd = (n) => new Intl.NumberFormat('vi-VN').format(n) + 'đ'
export const formatDate = (iso) => (iso ? new Date(iso).toLocaleDateString('vi-VN') : '-')
export const formatDateTime = (iso) => (iso ? new Date(iso).toLocaleString('vi-VN') : '-')
export const statusLabel = (status) => ({ pending: 'Đang chờ duyệt', approved: 'Đã duyệt', rejected: 'Bị từ chối', cancelled: 'Đã huỷ' })[status] || status
export const statusChipClass = (status) => ({ pending: 'chip-warning', approved: 'chip-accent', rejected: 'chip-danger', cancelled: '' })[status] || ''
export const planLabel = (plans, type) => plans.find((p) => p.type === type)?.label || type
export const pendingOf = (requests) => requests.find((r) => r.status === 'pending') || null

// VietQR quick-pay image: only once there is a pending purchase (an amount) and the bank has a BIN + account number.
export function qrUrlOf(info, req, user) {
  if (!info?.bankBin || !info?.bankAccountNumber || !req) return null
  const params = new URLSearchParams({
    amount: String(req.amount),
    addInfo: req.referenceCode || `${user?.username || ''} ${req.packageType}`.trim(),
    accountName: info.bankAccountHolder || '',
  })
  return `https://img.vietqr.io/image/${info.bankBin}-${info.bankAccountNumber}-compact2.png?${params}`
}

// ---------- scheduled deletion ----------
export const TTL_TEXT = { 3600: '1 giờ', 86400: '1 ngày', 604800: '7 ngày', 2592000: '30 ngày' }
export const UNIT_TEXT = { day: 'ngày', week: 'tuần', month: 'tháng' }
export const repeatText = (r) => (r ? `${r.every} ${UNIT_TEXT[r.unit] || r.unit}` : '')
export const fmtTime = (iso) => (iso ? new Date(iso).toLocaleString('vi-VN') : '')

// The chosen repeat as the API's { every, unit } (null = one-off).
export function repeatValue(form) {
  switch (form.repeat) {
    case '1w':
      return { every: 1, unit: 'week' }
    case '10d':
      return { every: 10, unit: 'day' }
    case '1m':
      return { every: 1, unit: 'month' }
    case 'custom':
      return { every: Math.trunc(Number(form.customN)) || 0, unit: form.customUnit }
    default:
      return null
  }
}
export function addCycle(date, r) {
  const d = new Date(date)
  if (!r) d.setDate(d.getDate() + 1)
  else if (r.unit === 'day') d.setDate(d.getDate() + r.every)
  else if (r.unit === 'week') d.setDate(d.getDate() + 7 * r.every)
  else d.setMonth(d.getMonth() + r.every)
  return d
}
export function toLocalInput(d) {
  const p = (n) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`
}
// Default first run = now + one cycle, until the user types their own.
export function defaultRunAt(form, now = new Date()) {
  const r = repeatValue(form)
  return toLocalInput(addCycle(now, r && r.every > 0 ? r : null))
}
export function describeSchedule(s) {
  if (s.kind === 'chat') {
    const what = s.chatScope === 'images' ? 'Ảnh' : 'Tin nhắn & tệp'
    return `${what} cũ hơn ${TTL_TEXT[s.ttlSeconds] || s.ttlSeconds + ' giây'} trong cuộc trò chuyện với ${s.friendName || '?'}`
  }
  const who = s.customerName ? `khách "${s.customerName}"` : 'mọi khách'
  const range = s.dateFrom || s.dateTo ? `, ngày ${s.dateFrom || '...'} đến ${s.dateTo || '...'}` : ', mọi ngày'
  const keep = s.keepDays > 0 ? `, giữ lại ${s.keepDays} ngày gần nhất` : ''
  return `Số liệu đã nhập của ${who}${range}${keep}`
}
export function scheduleStatusText(s) {
  if (s.status === 'done') return `Đã xoá ${s.deletedCount} mục lúc ${fmtTime(s.executedAt)}`
  if (s.kind === 'chat') return `Đang áp dụng từ ${fmtTime(s.runAt)}${s.deletedCount ? ` (đã xoá ${s.deletedCount} mục)` : ''}`
  return `Sẽ xoá lúc ${fmtTime(s.runAt)}`
}
// Returns { error } or { body, repeat, keep }.
export function scheduleCheck(form) {
  if (!form.runAt) return { error: 'Vui lòng chọn thời điểm xoá' }
  const repeat = repeatValue(form)
  if (form.repeat === 'custom' && (!repeat.every || repeat.every < 1 || repeat.every > 365)) return { error: 'Chu kỳ lặp phải từ 1 đến 365' }
  const keep = Math.trunc(Number(form.keepDays) || 0)
  if (keep < 0 || keep > 3650) return { error: 'Số ngày giữ lại phải từ 0 đến 3650' }
  if (!form.password) return { error: 'Nhập mật khẩu đăng nhập để xác nhận' }
  const body = { kind: 'data', customerName: form.customerName || undefined, runAt: new Date(form.runAt).toISOString() }
  if (repeat) body.repeat = repeat
  else {
    body.dateFrom = form.dateFrom || undefined
    body.dateTo = form.dateTo || undefined
  }
  if (keep > 0) body.keepDays = keep
  return { body, repeat, keep }
}
// The confirm text: the server's scopeText as is; lines are only added when it lacks the information (older server).
export function scheduleConfirmMessage(preview, repeat, body) {
  const scope = preview.scopeText || ''
  const lines = [`CẢNH BÁO: ${scope}`]
  if (repeat && !/lặp/i.test(scope)) lines.push(`Lặp lại mỗi ${repeatText(repeat)}.`)
  if (!/lần đầu|lúc \d/i.test(scope)) lines.push(`Thời điểm xoá${repeat ? ' lần đầu' : ''}: ${fmtTime(preview.runAt || body.runAt)}.`)
  if (typeof preview.willDeleteNow === 'number' && !/xoá ngay|xóa ngay|chạy ngay/i.test(scope)) lines.push(`Nếu chạy ngay bây giờ sẽ xoá ${preview.willDeleteNow} số liệu.`)
  lines.push('Bạn có thể huỷ lịch trước thời điểm này.')
  return lines.join('\n\n')
}

// ---------- statistics ----------
export const fmtNum = (n) => new Intl.NumberFormat('vi-VN').format(n)
export const signed = (n) => (n > 0 ? '+' : '') + fmtNum(n)

export const STAT_UNITS = [
  { key: 'day', label: 'Ngày', range: '30 ngày gần nhất', prev: '30 ngày trước đó', current: 'Hôm nay', before: 'hôm qua' },
  { key: 'week', label: 'Tuần', range: '12 tuần gần nhất', prev: '12 tuần trước đó', current: 'Tuần này', before: 'tuần trước' },
  { key: 'month', label: 'Tháng', range: '12 tháng gần nhất', prev: '12 tháng trước đó', current: 'Tháng này', before: 'tháng trước' },
  { key: 'year', label: 'Năm', range: '5 năm gần nhất', prev: '5 năm trước đó', current: 'Năm nay', before: 'năm trước' },
]
export const STAT_METRICS = [
  { key: 'vao', label: 'Tiền gửi' },
  { key: 'ra', label: 'Tiền trúng' },
  { key: 'profit', label: 'Lợi nhuận' },
]
export const statTone = (metric, n) => (metric === 'profit' ? (n >= 0 ? 'pos' : 'neg') : '')
export const barTone = (metric, v) => (metric === 'profit' ? (v < 0 ? 'neg' : 'pos') : 'main')

export function deltaOf(totals) {
  const delta = totals.previous === null ? null : totals.current - totals.previous
  const pct = totals.previous ? Math.round((delta / Math.abs(totals.previous)) * 100) : null
  return { delta, pct }
}

export const BAR_H = 210
export const BAR_PAD = { l: 46, r: 8, t: 10, b: 26 }
const DENSE_BARS = 30
// Geometry of the Thống kê bar chart at pixel width W. Same bar width for every period (sized for the densest one).
export function barPlot(series, metric, W, H = BAR_H, PAD = BAR_PAD) {
  const vals = series.map((p) => p.value)
  let max = Math.max(0, ...vals)
  const min = Math.min(0, ...vals)
  if (max === min) max = min + 1
  const innerH = H - PAD.t - PAD.b
  const innerW = W - PAD.l - PAD.r
  const y = (v) => PAD.t + ((max - v) / (max - min)) * innerH
  const step = innerW / series.length
  const bw = Math.min(26, Math.max(3, (innerW / Math.max(DENSE_BARS, series.length)) * 0.62))
  const bars = series.map((p, i) => {
    const cx = PAD.l + step * i + step / 2
    const y0 = y(0)
    const y1 = y(p.value)
    return { ...p, x: cx - bw / 2, w: bw, cx, y: Math.min(y0, y1), h: Math.max(Math.abs(y0 - y1), p.value ? 1.5 : 0), hx: PAD.l + step * i, hw: step }
  })
  const tv = min < 0 ? [max, 0, min] : [max, max / 2, 0]
  // drop a tick label that would sit on top of one already placed (tiny negative min next to 0)
  const ticks = []
  for (const v of tv) {
    const ty = y(v)
    if (v === 0 || !ticks.some((t) => Math.abs(t.y - ty) < 12)) ticks.push({ v, y: ty })
  }
  const shown = new Set(tickIndices(series.length, tickEvery(series.length, innerW)))
  return { bars, ticks, zeroY: y(0), shown, step }
}
export const tipLeftPct = (cx, W) => `${Math.min(Math.max((cx / W) * 100, 16), 84)}%`

// StatsChart (generic chart, used by the admin statistics screen)
export function niceMax(v) {
  if (v <= 0) return 4
  const p = 10 ** Math.floor(Math.log10(v))
  const n = v / p
  return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10) * p
}
export function shortDate(k) {
  if (k.length === 4) return k
  return k.length === 7 ? `${k.slice(5)}/${k.slice(2, 4)}` : `${k.slice(8)}/${k.slice(5, 7)}`
}
export function longDate(k, unit = 'day') {
  if (k.length === 4) return `Năm ${k}`
  if (k.length === 7) return `Tháng ${k.slice(5)}/${k.slice(0, 4)}`
  if (unit === 'week') {
    const mon = new Date(+k.slice(0, 4), +k.slice(5, 7) - 1, +k.slice(8, 10))
    const sun = new Date(mon.getFullYear(), mon.getMonth(), mon.getDate() + 6)
    const f = (d) => `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}`
    return `Tuần ${f(mon)} – ${f(sun)}/${sun.getFullYear()}`
  }
  return `${k.slice(8)}/${k.slice(5, 7)}/${k.slice(0, 4)}`
}
export function shortValue(v, money) {
  if (!money) return String(+v.toFixed(1))
  if (v >= 1e6) return `${+(v / 1e6).toFixed(1)}tr`
  if (v >= 1e3) return `${+(v / 1e3).toFixed(0)}k`
  return String(v)
}
export const fullValue = (v, money) => (money ? Number(v).toLocaleString('vi-VN') + ' đ' : String(v))
export function chartLabels(points, plotW) {
  const n = points.length
  const every = Math.ceil(n / Math.max(3, Math.floor(plotW / 70)))
  return points.map((d, i) => ({ i, text: shortDate(d.date) })).filter((l) => l.i % every === 0 || l.i === n - 1)
}
