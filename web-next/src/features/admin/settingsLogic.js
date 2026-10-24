// Pure helpers of Cài đặt hệ thống (/admin/settings): bank list, package formatting, tabs, security policy maths.

// BIN codes per Napas/VietQR - identify the bank on transfers and render the VietQR quick-pay code for customers.
export const BANKS = [
  { bin: '970436', name: 'Vietcombank' },
  { bin: '970415', name: 'VietinBank' },
  { bin: '970418', name: 'BIDV' },
  { bin: '970405', name: 'Agribank' },
  { bin: '970422', name: 'MB Bank' },
  { bin: '970407', name: 'Techcombank' },
  { bin: '970416', name: 'ACB' },
  { bin: '970432', name: 'VPBank' },
  { bin: '970423', name: 'TPBank' },
  { bin: '970403', name: 'Sacombank' },
  { bin: '970437', name: 'HDBank' },
  { bin: '970443', name: 'SHB' },
  { bin: '970431', name: 'Eximbank' },
  { bin: '970426', name: 'MSB' },
  { bin: '970448', name: 'OCB' },
  { bin: '970440', name: 'SeABank' },
  { bin: '970441', name: 'VIB' },
  { bin: '970449', name: 'LienVietPostBank (LPBank)' },
  { bin: '970429', name: 'SCB' },
  { bin: '970406', name: 'DongA Bank' },
]
export const bankFields = [
  { key: 'bank_account_number', label: 'Số tài khoản' },
  { key: 'bank_account_holder', label: 'Chủ tài khoản' },
]
export const bankKeys = ['bank_name', 'bank_bin', 'bank_account_number', 'bank_account_holder', 'max_virtual_ids']
// Internal one-time markers set by the server; not settings, so never listed.
export const INTERNAL_KEYS = ['unread_epoch', 'e2ee_friend_chat_purged', 'perm_split_maintenance']

export const EVENT_LABELS = {
  login_failed: 'Đăng nhập sai',
  login_locked: 'Khoá tạm đăng nhập',
  session_revoked: 'Thu hồi phiên',
  data_wiped: 'Xoá dữ liệu',
  app_version_changed: 'Đổi phiên bản ứng dụng',
}

export const formatVnd = (v) => Number(v).toLocaleString('vi-VN') + ' đ'
export function formatDuration(d) {
  if (d % 365 === 0) return `${d} ngày (${d / 365} năm)`
  if (d % 30 === 0) return `${d} ngày (${d / 30} tháng)`
  return `${d} ngày`
}

/** Settings keys shown generically in the "Khoá khác" tab (everything with no dedicated form). */
export const otherKeysOf = (raw) =>
  Object.keys(raw).filter((k) => !k.startsWith('package_price_') && !k.startsWith('app_') && !bankKeys.includes(k) && !INTERNAL_KEYS.includes(k))

export const bankFormOf = (raw) => ({
  bank_bin: raw.bank_bin ?? '',
  bank_account_number: raw.bank_account_number ?? '',
  bank_account_holder: raw.bank_account_holder ?? '',
})

/** Body of PUT /admin/settings for the bank form, or { error }. */
export function bankPayload(bank) {
  const acc = bank.bank_account_number.trim()
  const holder = bank.bank_account_holder.trim()
  const bin = bank.bank_bin
  if (!bin || !acc || !holder) return { error: 'Vui lòng chọn ngân hàng và nhập đầy đủ số tài khoản, chủ tài khoản' }
  return { body: { bank_bin: bin, bank_name: BANKS.find((b) => b.bin === bin)?.name || '', bank_account_number: acc, bank_account_holder: holder } }
}

export const maxIdsPayload = (v) => ({ max_virtual_ids: String(v).trim() || '5' })

export const packageBody = (f) => ({ label: f.label.trim(), durationDays: Number(f.durationDays), priceVnd: Number(f.priceVnd) })

/** A package that accounts / requests / transactions already use cannot be deleted (hide it instead). */
export const packageInUse = (p) => p.usage.users + p.usage.requests + p.usage.transactions > 0

/** Tabs by right (A07): settings.manage, security.view, security.policy, backups.manage. */
export function settingsTabs({ canSettings, canSecurity, canPolicy, canBackups, hasOther }) {
  return [
    ...(canSettings
      ? [
          { key: 'payment', label: 'Thanh toán' },
          { key: 'prices', label: 'Gói dịch vụ' },
          { key: 'limits', label: 'Giới hạn ID' },
          { key: 'appversion', label: 'Phiên bản ứng dụng' },
        ]
      : []),
    ...(canSecurity ? [{ key: 'security', label: 'Nhật ký bảo mật' }] : []),
    ...(canPolicy ? [{ key: 'policy', label: 'Chính sách bảo mật' }] : []),
    ...(canBackups ? [{ key: 'backups', label: 'Sao lưu' }] : []),
    ...(canSettings && hasOther ? [{ key: 'other', label: 'Khoá khác' }] : []),
  ]
}

// ---- Chính sách bảo mật ----
export const POLICY_DEFAULT = {
  loginFreeAttempts: 5,
  loginBaseLockSeconds: 30,
  loginMaxLockSeconds: 900,
  tokenDays: 30,
  autoLockMinutes: 0,
  hideLockSeconds: 0,
  watermarkEnabled: false,
  screenshotGuardEnabled: true,
  blurOnHideEnabled: false,
}
export const mins = (s) => (s % 60 === 0 && s >= 60 ? `${s / 60} phút` : `${s} giây`)
/** "30 giây → 1 phút → 2 phút → 4 phút": the first four consecutive lockouts. */
export function lockExample(base, max) {
  const out = []
  let s = base
  for (let i = 0; i < 4; i++) {
    out.push(mins(Math.min(s, max)))
    s *= 2
  }
  return out.join(' → ')
}
/** PUT body: booleans stay booleans, everything else becomes a number. */
export function policyBody(form) {
  const body = {}
  for (const k of Object.keys(form)) body[k] = typeof form[k] === 'boolean' ? !!form[k] : Number(form[k])
  return body
}

export function formatSize(bytes) {
  if (bytes >= 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`
  return `${Math.max(1, Math.round(bytes / 1024))} KB`
}
