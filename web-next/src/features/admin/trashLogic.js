// Pure helpers of the Admin Thùng rác (/admin/trash) and "Khôi phục dữ liệu một khách" (Cài đặt > Sao lưu).
// Same texts as the app (app/lib/features/admin/trash/trash_logic.dart, settings/restore_customer.dart).

export const TRASH_KIND_LABELS = {
  user: 'Tài khoản khách hàng',
  staff: 'Tài khoản nhân viên',
  announcement: 'Thông báo',
  package: 'Gói dịch vụ',
  setting: 'Cài đặt',
}
export const trashKindLabel = (kind) => TRASH_KIND_LABELS[kind] || kind

/** Icon (components/svgIcons.ts or Lucide) of a kind of trash item. */
export const TRASH_KIND_ICONS = { user: 'users', staff: 'user-admin', announcement: 'megaphone', package: 'pay', setting: 'settings' }
export const trashKindIcon = (kind) => TRASH_KIND_ICONS[kind] || 'settings'

const COUNT_NAMES = {
  customers: 'khách hàng',
  data_entries: 'số liệu',
  lottery_results: 'kết quả xổ số',
  customer_syntax_templates: 'mẫu cú pháp',
  deletion_schedules: 'lịch xoá',
  transactions: 'giao dịch',
  payment_requests: 'yêu cầu thanh toán',
  messages: 'tin nhắn hỗ trợ',
  direct_messages: 'tin phản hồi',
  friendships: 'bạn bè',
  friend_requests: 'lời mời kết bạn',
  customer_codes: 'mã ID',
  retired_codes: 'mã ID cũ',
  message_reads: 'dấu đã đọc',
  e2ee_devices: 'thiết bị nhắn tin',
  recovery_requests: 'yêu cầu khôi phục',
  call_logs: 'cuộc gọi',
  announcements: 'thông báo',
  packages: 'gói',
  settings: 'mục cài đặt',
}

/** "2 khách hàng · 19 số liệu · 85 kết quả xổ số" in a fixed order; tables this screen does not know show their own name. */
export function countsSummary(counts) {
  const c = counts || {}
  const known = Object.keys(COUNT_NAMES).filter((k) => Number(c[k]) > 0).map((k) => `${Number(c[k])} ${COUNT_NAMES[k]}`)
  const others = Object.keys(c).filter((k) => !(k in COUNT_NAMES) && Number(c[k]) > 0).map((k) => `${Number(c[k])} ${k}`)
  return [...known, ...others].join(' · ')
}

/** "Còn 3 ngày" / "Còn dưới 1 ngày". */
export const timeLeft = (daysLeft) => (Number(daysLeft) <= 1 ? 'Còn dưới 1 ngày' : `Còn ${Number(daysLeft)} ngày`)

/** A backup the Admin can restore one customer from: made in the app ("manual") or the server's daily one ("cron"). */
export const backupSourceLabel = (source) => (source === 'cron' ? 'Tự động hằng ngày' : 'Tạo trong app')

/** Customers of the picked backup that match the search box (user name or name, no accents / case needed). */
export function filterBackupCustomers(list, query) {
  const q = String(query || '').trim().toLowerCase()
  const title = (c) => (c.name ? `${c.username} (${c.name})` : c.username)
  return (list || []).filter((c) => !q || title(c).toLowerCase().includes(q))
}
export const customerTitle = (c) => (c.name ? `${c.username} (${c.name})` : c.username)

/** The "replace" mode needs the Admin to type the user name; "merge" needs nothing. An account that no longer exists can't be restored here. */
export function canRestoreCustomer({ customer, replace, confirmText, working }) {
  if (!customer || customer.now == null || working) return false
  if (!replace) return true
  return String(confirmText || '').trim().toLowerCase() === String(customer.username).toLowerCase()
}

/** The result line after POST /admin/backups/restore-user. */
export function restoreResultText(customer, written, safetyBackup) {
  const sum = countsSummary(written)
  return `Đã khôi phục cho ${customerTitle(customer)}: ${sum ? `đã ghi ${sum}` : 'không có dòng nào cần thêm'}. Đã tạo thêm bản sao lưu an toàn ${safetyBackup} trước khi làm.`
}
