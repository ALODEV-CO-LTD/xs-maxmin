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
