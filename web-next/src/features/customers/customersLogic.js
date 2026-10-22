// Logic thuần của màn Khách hàng (bản Vue: views/CustomersView.vue): gộp danh sách khách với số liệu từ các lượt nhập,
// tìm kiếm không dấu, thêm khách (kèm đài mặc định), thông báo lỗi.
import { fold } from '../../lib/messageParser'

export const OFFLINE_WRITE = 'Đang offline: thêm/xoá khách hàng cần có mạng, vui lòng thử lại khi kết nối lại.'
export const REGION_OPTIONS = [
  { value: '', label: 'Chưa chọn (tính như khách Bắc)' },
  { value: 'mb', label: 'Khách Miền Bắc' },
  { value: 'mn', label: 'Khách Miền Nam / Miền Trung' },
]

// ApiError (lib/api.js) carries a numeric `status` (0 = no connection); any other error does not.
const isApiError = (err) => !!err && typeof err.status === 'number'
/** Message of a failed write: the server's text, the offline note when there is no connection, else `fallback`. */
export const writeError = (err, fallback) => (isApiError(err) ? (err.status === 0 ? OFFLINE_WRITE : err.message) : fallback)
/** Message of a failed single-field save (đài, miền): the server's text or `fallback`. */
export const saveError = (err, fallback) => (isApiError(err) ? err.message : fallback)

export function toNumber(str) {
  if (!str) return 0
  const cleaned = String(str).replace(/[^\d.-]/g, '')
  const n = parseFloat(cleaned)
  return Number.isFinite(n) ? n : 0
}
export const formatNumber = (n) => new Intl.NumberFormat('vi-VN').format(n)

/**
 * The roster first (a customer with no entry yet still shows, 0/0/0, with its roster id so it can be deleted), then the
 * names that only appear in entries (rosterId null). Newest last entry first; customers without entries on top, by name.
 */
export function buildCustomers(roster, entries) {
  const byName = new Map()
  for (const c of roster) {
    byName.set(c.name, { name: c.name, rosterId: c.id, phone: c.phone || '', count: 0, vao: 0, ra: 0, lastDate: null, entries: [] })
  }
  for (const e of entries) {
    const name = e.customerName || '(Không tên)'
    if (!byName.has(name)) byName.set(name, { name, rosterId: null, phone: '', count: 0, vao: 0, ra: 0, lastDate: null, entries: [] })
    const c = byName.get(name)
    c.count += 1
    c.vao += toNumber(e.score)
    c.ra += toNumber(e.result)
    c.entries.push(e)
    if (!c.lastDate || e.entryDate > c.lastDate) c.lastDate = e.entryDate
  }
  const list = [...byName.values()].map((c) => ({ ...c, chenhLech: c.vao - c.ra }))
  list.sort((a, b) => {
    if (!a.lastDate && !b.lastDate) return a.name.localeCompare(b.name, 'vi')
    if (!a.lastDate) return -1
    if (!b.lastDate) return 1
    return a.lastDate < b.lastDate ? 1 : -1
  })
  return list
}

/** Accent-insensitive: "do ngoc" finds "Đỗ Ngọc Mai". */
export function filterCustomers(customers, search) {
  const q = fold(String(search).trim())
  if (!q) return customers
  return customers.filter((c) => fold(c.name).includes(q))
}

export const sortRoster = (list) => [...list].sort((a, b) => a.name.localeCompare(b.name, 'vi'))
export const entriesUrl = (name) => `/entries?customer=${encodeURIComponent(name)}`

/**
 * POST /me/customers, then (when the default station is not Miền Bắc) PATCH the station. Resolves `{ created, warn }`:
 * `warn` is set when the customer was created but the station could not be saved. A failed POST throws.
 */
export async function createCustomer(api, { name, phone, station }) {
  let created = await api.post('/me/customers', { name, phone })
  let warn = ''
  if (station && station !== 'mb') {
    try {
      created = { ...created, ...(await api.patch(`/me/customers/${created.id}`, { defaultStation: station })) }
    } catch (err) {
      warn = `Đã tạo khách nhưng chưa lưu được đài mặc định: ${isApiError(err) ? err.message : 'lỗi mạng'}.`
    }
  }
  return { created, warn }
}

export const removeConfirm = (name) => ({
  title: 'Xoá khách hàng',
  message: `Xoá "${name}" khỏi danh sách khách hàng? Số liệu đã nhập của khách này vẫn được giữ nguyên.`,
  confirmText: 'Xoá',
  danger: true,
})

// ---- Tiền, bộ lọc và sắp xếp (giống app: customers_controller.dart) --------------------------------------------------------

/** Gắn tiền của từng khách (đồng) vào danh sách: sent = tiền vào, won = tiền ra, profit = lợi nhuận trên các ngày đã có kết quả. */
export function attachMoney(customers, money) {
  return customers.map((c) => {
    const m = money?.[c.name]
    return { ...c, money: !!money, sent: m?.sent || 0, won: m?.won || 0, settled: m?.settled || 0, profit: (m?.settled || 0) - (m?.won || 0) }
  })
}

export const SORTS = [
  { value: 'recent', label: 'Gần đây nhất' },
  { value: 'sentDesc', label: 'Tiền vào nhiều nhất' },
  { value: 'sentAsc', label: 'Tiền vào ít nhất' },
  { value: 'wonDesc', label: 'Tiền ra nhiều nhất' },
  { value: 'wonAsc', label: 'Tiền ra ít nhất' },
  { value: 'profitDesc', label: 'Lợi nhuận nhiều nhất' },
  { value: 'profitAsc', label: 'Lợi nhuận ít nhất' },
  { value: 'nameAsc', label: 'Tên A → Z' },
]
export const RESULT_FILTERS = [
  { value: '', label: 'Tất cả' },
  { value: 'profit', label: 'Lãi' },
  { value: 'loss', label: 'Lỗ' },
  { value: 'noData', label: 'Chưa có số liệu' },
]
export const REGION_FILTERS = [
  { value: '', label: 'Mọi miền' },
  { value: 'mb', label: 'Miền Bắc' },
  { value: 'mn', label: 'Miền Nam / Trung' },
]

/** Lãi / lỗ chỉ xét khách có số liệu; "Chưa có số liệu" là khách chưa có lượt nhập nào; miền theo miền riêng của khách. */
/** @param {(c: any) => string | null} [regionOf] */
export function filterByView(list, { result = '', region = '' } = {}, regionOf) {
  return list.filter((c) => {
    if (result === 'profit' && !(c.count > 0 && c.profit > 0)) return false
    if (result === 'loss' && !(c.count > 0 && c.profit < 0)) return false
    if (result === 'noData' && c.count > 0) return false
    return !region || (regionOf ? regionOf(c) : null) === region
  })
}

/** `recent` giữ nguyên thứ tự (ngày nhập gần nhất trước); các kiểu khác sắp theo khoá rồi theo tên cho ổn định. */
export function sortCustomers(list, sort = 'recent') {
  if (sort === 'recent') return list
  const byName = (a, b) => a.name.localeCompare(b.name, 'vi')
  const out = [...list]
  if (sort === 'nameAsc') return out.sort(byName)
  const field = sort.startsWith('sent') ? 'sent' : sort.startsWith('won') ? 'won' : 'profit'
  const desc = sort.endsWith('Desc')
  return out.sort((a, b) => (desc ? b[field] - a[field] : a[field] - b[field]) || byName(a, b))
}

/** Số mục đang áp dụng (kiểu sắp xếp khác mặc định, lọc kết quả, lọc miền) để ghi trên nút Bộ lọc. */
export const activeViewCount = ({ sort = 'recent', result = '', region = '' } = {}) => (sort !== 'recent' ? 1 : 0) + (result ? 1 : 0) + (region ? 1 : 0)

/** Tiền đồng có dấu phân cách; số âm giữ dấu trừ. */
export const formatMoney = (n) => `${formatNumber(Math.round(n))}đ`
