// Pure helpers of Quản lý khách hàng (/admin/users) and the recovery-request queue.

/** Random password that passes the server policy (8+ chars, not a common/sequential one). `bytes`: 10 random uint32. */
export function generatePassword(bytes) {
  const letters = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ'
  const digits = '23456789'
  const all = letters + digits
  const buf = bytes ?? crypto.getRandomValues(new Uint32Array(10))
  return [...buf].map((n, i) => (i === 3 || i === 7 ? digits[n % digits.length] : all[n % all.length])).join('')
}

export const listPath = (q) => `/admin/users${q ? `?q=${encodeURIComponent(q)}` : ''}`

export const statusLabel = (s) => (s === 'active' ? 'Hoạt động' : 'Hết hạn')

export const supportNoteOf = (kind) =>
  kind === 'code' ? 'Đã cấp mã khôi phục mới (mã cũ không còn dùng được).' : 'Đã gỡ mọi khoá đăng nhập/xác thực/khôi phục của tài khoản.'
export const supportBody = (kind) => (kind === 'code' ? { reissueRecoveryCode: true } : { clearLockouts: true })

/** Confirm-dialog options for locking / unlocking an account. */
export function lockConfirm(user) {
  const locking = !user.accountLocked
  return {
    title: locking ? 'Khoá tài khoản' : 'Mở khoá tài khoản',
    message: locking ? `Khoá tài khoản "${user.name}"? Khách hàng sẽ không đăng nhập được.` : `Mở khoá tài khoản "${user.name}"?`,
    confirmText: locking ? 'Khoá' : 'Mở khoá',
    danger: locking,
  }
}

/** Merge a PATCH answer into the list row of the same user. */
export const mergeRow = (list, updated) => list.map((s) => (s.id === updated.id ? { ...s, ...updated } : s))

/** Short label for the unread chip on a request / session. */
export const RECOVERY_STATUS = { pending: 'Chờ duyệt', approved: 'Đã cấp mã', expired: 'Mã hết hạn' }
