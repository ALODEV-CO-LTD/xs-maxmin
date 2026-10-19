// Logic thuần của màn Tính điểm (chép từ ScoringView.vue, không dùng React): lọc/ gom theo ngày, trạng thái kết quả xổ số,
// tính điểm ra một dòng, tổng, ngày mở sẵn. Màn hình (ScoringScreen.tsx) chỉ giữ state và gọi các hàm này.
import { effectiveConfig } from '../../lib/scoringConfig'
import { entryDetail } from '../../lib/scoringSummary'
import { entryStations, regionOf } from '../../lib/lotteryStations'
import { localDateString } from '../../lib/dates'

export const PAGE_DAYS = 10
export const WEEKDAYS = ['Chủ nhật', 'Thứ hai', 'Thứ ba', 'Thứ tư', 'Thứ năm', 'Thứ sáu', 'Thứ bảy']
export const PRESETS = [
  { key: 'today', label: 'Hôm nay' },
  { key: '7', label: '7 ngày' },
  { key: '30', label: '30 ngày' },
  { key: 'all', label: 'Tất cả' },
]

const nf = new Intl.NumberFormat('vi-VN')
export const formatNumber = (n) => nf.format(n)
export const money = (n) => `${nf.format(Math.round(n))} đ`

export function toNumber(str) {
  if (!str) return 0
  const cleaned = String(str).replace(/[^\d.-]/g, '')
  const n = parseFloat(cleaned)
  return Number.isFinite(n) ? n : 0
}

export function dayLabel(iso) {
  const [y, m, d] = iso.split('-').map(Number)
  const wd = WEEKDAYS[new Date(y, m - 1, d).getDay()]
  return { date: `${String(d).padStart(2, '0')}/${String(m).padStart(2, '0')}/${y}`, weekday: wd }
}

export function daysAgo(n, now = new Date()) {
  const d = new Date(now)
  d.setDate(d.getDate() - n)
  return localDateString(d)
}

/** Khoảng ngày của một nút chọn nhanh: [từ, đến]; '' (Tuỳ chọn) = giữ nguyên (trả null). */
export function presetRange(key, now = new Date()) {
  if (key === '') return null
  if (key === 'today') return [daysAgo(0, now), daysAgo(0, now)]
  if (key === '7') return [daysAgo(6, now), daysAgo(0, now)]
  if (key === '30') return [daysAgo(29, now), daysAgo(0, now)]
  return ['', '']
}

/** Giá trị ô "Ngày": một ngày khi từ = đến, còn lại rỗng. */
export const singleDayOf = (from, to) => (from && from === to ? from : '')

/** Chọn ngày: [từ, đến, preset]. Xoá ngày = xem mọi ngày. */
export const rangeForDay = (v) => [v || '', v || '', v ? '' : 'all']

export const lrKey = (date, station) => `${date}|${station}`

/** Số liệu của một khách trong khoảng ngày (và vùng, nếu lọc). Chưa chọn khách = rỗng. */
export function filterEntries(entries, { customer, region = 'all', from = '', to = '' }) {
  if (!customer) return []
  return entries.filter((e) => {
    if (e.customerName !== customer) return false
    if (region !== 'all' && regionOf(e.station).id !== region) return false
    if (from && e.entryDate < from) return false
    if (to && e.entryDate > to) return false
    return true
  })
}

/** 'yes' = mọi đài của ngày đều có kết quả, 'partial' = một phần, 'no' = chưa có đài nào, undefined = chưa tra xong. */
export function lotteryState(date, list, cache) {
  const keys = new Set()
  for (const e of list) for (const st of entryStations(e)) keys.add(lrKey(date, st))
  if (!keys.size) return undefined
  let have = 0
  for (const k of keys) {
    if (!(k in cache)) return undefined
    if (cache[k]) have++
  }
  return have === keys.size ? 'yes' : have > 0 ? 'partial' : 'no'
}

export const configFor = (ctx, betType, station) => effectiveConfig(ctx.rates, ctx.customerRates, betType, regionOf(station).id)

/** Điểm ra của một dòng trên mọi kết quả đã có (mỗi đài một kết quả): tổng. */
export function scoreEntryAll(entry, resultsByStation, ctx) {
  let out = 0
  for (const [station, lr] of resultsByStation) {
    out += entryDetail(entry, lr, configFor(ctx, entry.betType, station), { region: regionOf(station).id, customerRegion: ctx.customerRegion }).out
  }
  return out
}

/** Điểm ra dùng để cộng ngày: giá trị đã lưu của lần tính, hoặc tính trong bộ nhớ từ kết quả đã biết, hoặc số đang lưu. */
export function entryOut(e, status, cache, ctx) {
  if (status?.state === 'saved') return status.value
  const known = entryStations(e).filter((st) => cache[lrKey(e.entryDate, st)])
  return known.length ? scoreEntryAll(e, known.map((st) => [st, cache[lrKey(e.entryDate, st)]]), ctx) : toNumber(e.result)
}

/** Mọi ngày trong khoảng, mới nhất trước, kèm số liệu. `settled` = đã có kết quả xổ số (đủ hoặc một phần). */
export function buildDays(rangeEntries, cache, statuses, ctx) {
  const map = new Map()
  for (const e of rangeEntries) {
    if (!map.has(e.entryDate)) map.set(e.entryDate, [])
    map.get(e.entryDate).push(e)
  }
  return [...map.keys()]
    .sort((a, b) => (a < b ? 1 : a > b ? -1 : 0))
    .map((date) => {
      const list = map.get(date)
      const lot = lotteryState(date, list, cache)
      let totalIn = 0
      let totalOut = 0
      for (const e of list) {
        totalIn += toNumber(e.score)
        totalOut += entryOut(e, statuses[e.id], cache, ctx)
      }
      return { date, entries: list, lottery: lot, settled: lot === 'yes' || lot === 'partial', totalIn, totalOut, profit: totalOut - totalIn }
    })
}

/** onlyMissing = chỉ những ngày chưa có kết quả xổ số. */
export const filterMissing = (allDays, onlyMissing) => (onlyMissing ? allDays.filter((d) => d.lottery === 'no') : allDays)

export function totalsOf(days) {
  let rows = 0
  let totalIn = 0
  let settledIn = 0
  let settledOut = 0
  for (const d of days) {
    rows += d.entries.length
    totalIn += d.totalIn
    if (d.settled) {
      settledIn += d.totalIn
      settledOut += d.totalOut
    }
  }
  return { days: days.length, rows, totalIn, settledOut, profit: settledOut - settledIn, hasSettled: days.some((d) => d.settled) }
}

/** Ngày mở: theo lựa chọn của người dùng, mặc định chỉ ngày mới nhất mở. */
export function isOpen(openState, date, days) {
  if (date in openState) return openState[date]
  return days.length > 0 && days[0].date === date
}

/** Khóa của danh sách ngày đang mở + hiển thị: đổi khóa thì tính lại các ngày đó. */
export const openKey = (visibleDays, days, openState, customer, calcVersion) =>
  visibleDays.filter((d) => isOpen(openState, d.date, days)).map((d) => d.date).join('|') + `#${customer}#${calcVersion}`

/** Tên khu vực/đài hiển thị trên dòng: "Miền Trung" hoặc tên một đài. deps = { isRegionCode, regionOf, stationName }. */
export function areaName(code, deps) {
  if (!code || code === 'mb') return 'Miền Bắc'
  return deps.isRegionCode(code) ? deps.regionOf(code).name : deps.stationName(code)
}

/** Dòng tóm tắt khi chưa có ngày nào (đúng chữ bản Vue). */
export function emptyMessage({ onlyMissing, rangeCount, customerHasEntries }) {
  if (onlyMissing) return 'Không có ngày nào thiếu kết quả xổ số trong khoảng này. Bỏ chọn ô lọc để xem toàn bộ lịch sử.'
  if (rangeCount === 0 && customerHasEntries) return 'Không có số liệu nào trong khoảng ngày này. Chọn "Tất cả" để xem lịch sử.'
  return 'Khách hàng này chưa có số liệu nào.'
}

/** Thông báo sau khi chuyển từ Nhập số sang (?customer=&date=&added=). */
export function addedNotice(customer, date, added) {
  return `Đã thêm ${added} số liệu cho ${customer}${date ? ` ngày ${String(date).split('-').reverse().join('/')}` : ''}. Điểm ra được tính theo kết quả xổ số đã nhập.`
}

/**
 * Tính điểm ra của một dòng: tra kết quả từng đài, cộng điểm, và chỉ lưu (PATCH) khi khác số đã lưu.
 * deps = { fetchLottery(date, station), patch(id, body) }. Trả { status, updated }; updated = dòng mới từ máy chủ (nếu có lưu).
 */
export async function computeOne(entry, ctx, deps) {
  const results = []
  for (const st of entryStations(entry)) {
    const lr = await deps.fetchLottery(entry.entryDate, st)
    if (lr) results.push([st, lr])
  }
  if (!results.length) return { status: { state: 'no-lottery', value: null } }
  const value = scoreEntryAll(entry, results, ctx)
  // Đã lưu đúng số này thì không ghi lại.
  if (entry.result !== null && entry.result !== undefined && entry.result !== '' && toNumber(entry.result) === value) {
    return { status: { state: 'saved', value } }
  }
  try {
    const updated = await deps.patch(entry.id, { result: String(value) })
    return { status: { state: 'saved', value }, updated }
  } catch (err) {
    return { status: { state: 'error', value, error: err.message || 'Không lưu được' } }
  }
}
