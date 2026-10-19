// Sign-in / sign-up flow of the public pages (port of the script parts of LoginView.vue and RegisterView.vue), kept
// free of React so the rules can be unit-tested:
//   - POST /auth/login can answer 3 stages: 'done' (token+role), 'second_password_required' (ask the layer-2
//     password, POST /auth/step2, which can itself answer done or 'wipe_confirmation_required'), and
//     'wipe_confirmation_required' (explicit destructive confirm, then POST /auth/confirm-wipe).
//   - "Quên mật khẩu": username + mã khôi phục + new password (POST /auth/recover); then the NEW code is shown once.
//     Lost the code too: POST /auth/recovery-request, then POST /auth/recover-with-ticket (admin-assisted, A06).
//   - POST /auth/register always requires a second password, plus an optional wipe password; the backend always
//     answers 'second_password_required', so the page asks for the just-set second password and calls /auth/step2.
import { api, ApiError } from './api'

export const GENERIC_ERROR = 'Đã xảy ra lỗi, vui lòng thử lại'
export const errMsg = (e) => (e instanceof ApiError ? e.message : GENERIC_ERROR)

/** `?redirect=` is only followed when it is a path of this site (never another origin, never back to the auth pages). */
export function safeRedirect(r) {
  if (typeof r !== 'string' || !r.startsWith('/') || r.startsWith('//') || r.startsWith('/\\')) return null
  if (r === '/login' || r.startsWith('/login?') || r === '/register' || r.startsWith('/register?')) return null
  return r
}

/** What a login / step2 answer means. Step 1 success is {stage:'done', token, role}; step2 success is just {token, role}
 *  with no 'stage' field at all - either is "done". */
export function loginStageOf(res) {
  if (res?.stage === 'done' || res?.token) return { kind: 'done', token: res.token, role: res.role }
  if (res?.stage === 'second_password_required') return { kind: 'second_password', pendingToken: res.pendingToken }
  if (res?.stage === 'wipe_confirmation_required') return { kind: 'wipe_confirm', wipeToken: res.wipeToken }
  return { kind: 'unknown' }
}

export const UNKNOWN_RESPONSE = 'Phản hồi không xác định từ máy chủ'

export function credentialsProblem(username, password) {
  return !username.trim() || !password ? 'Vui lòng nhập tên đăng nhập và mật khẩu' : ''
}
export const secondPasswordProblem = (p) => (p ? '' : 'Vui lòng nhập mật khẩu lớp hai')

function newPasswordProblem(newPassword, confirm) {
  if (!newPassword) return 'Vui lòng nhập mật khẩu mới'
  if (newPassword !== confirm) return 'Mật khẩu nhập lại không khớp'
  return ''
}
export function recoverProblem({ username, code, newPassword, confirm }) {
  if (!username.trim() || !code.trim()) return 'Vui lòng nhập tên đăng nhập và mã khôi phục'
  return newPasswordProblem(newPassword, confirm)
}
export function ticketProblem({ username, ticket, newPassword, confirm }) {
  if (!username.trim() || !ticket.trim()) return 'Vui lòng nhập tên đăng nhập và mã hỗ trợ'
  return newPasswordProblem(newPassword, confirm)
}
export const helpProblem = (username) => (username.trim() ? '' : 'Vui lòng nhập tên đăng nhập')

// ---- calls (each resolves the server answer; callers catch ApiError -> errMsg) ----
export const loginStep1 = (username, password) => api.post('/auth/login', { username: username.trim(), password })
export const loginStep2 = (pendingToken, password) => api.post('/auth/step2', { pendingToken, password })
export const confirmWipe = (wipeToken) => api.post('/auth/confirm-wipe', { wipeToken })
export const recoverWithCode = ({ username, code, newPassword }) =>
  api.post('/auth/recover', { username: username.trim(), recoveryCode: code.trim(), newPassword })
export const requestHelp = (username, note) => api.post('/auth/recovery-request', { username: username.trim(), note: note.trim() })
export const recoverWithTicket = ({ username, ticket, newPassword }) =>
  api.post('/auth/recover-with-ticket', { username: username.trim(), ticket: ticket.trim(), newPassword })

// ---- registration ----
/** Any non-empty password is fine (up to bcrypt's 72 bytes) - see backend password_policy.dart. */
export const passwordProblem = (v) =>
  !v ? 'Vui lòng nhập mật khẩu' : new TextEncoder().encode(v).length > 72 ? 'Mật khẩu quá dài (tối đa 72 ký tự)' : ''

/** Inline validation; rules mirror the backend (routes/api/auth/register.dart). '' = valid. */
export function registerFieldErrors({ name, username, password, confirmPassword, secondPassword, wipePassword, wipeOpen }) {
  const wipeProblem = () => {
    if (!wipeOpen || !wipePassword) return ''
    const p = passwordProblem(wipePassword)
    if (p) return p
    return wipePassword === password || wipePassword === secondPassword ? 'Mật khẩu xoá dữ liệu phải khác 2 mật khẩu còn lại' : ''
  }
  return {
    name: name.trim() ? '' : 'Vui lòng nhập tên hiển thị',
    username: username.trim().length >= 3 ? '' : 'Tên đăng nhập phải có ít nhất 3 ký tự',
    password: passwordProblem(password),
    confirmPassword: !confirmPassword ? 'Vui lòng nhập lại mật khẩu' : confirmPassword !== password ? 'Mật khẩu xác nhận không khớp' : '',
    secondPassword: passwordProblem(secondPassword),
    wipePassword: wipeProblem(),
  }
}
export const REGISTER_ACCOUNT_FIELDS = ['name', 'username', 'password', 'confirmPassword']
export const REGISTER_SECURITY_FIELDS = ['secondPassword', 'wipePassword']
export const REGISTER_FIELD_IDS = {
  name: 'name',
  username: 'reg-username',
  password: 'reg-password',
  confirmPassword: 'reg-confirm-password',
  secondPassword: 'reg-second-password',
  wipePassword: 'reg-wipe-password',
}

export const registerAccount = ({ name, username, password, secondPassword, wipePassword }) =>
  api.post('/auth/register', {
    name: name.trim(),
    username: username.trim(),
    password,
    secondPassword,
    wipePassword: wipePassword || undefined,
  })

/** Answer of the final step2 of a fresh registration. Returns {token, role} or {error}. A freshly registered account
 *  cannot yet have a matching wipe password, but a wipe stage is handled defensively. */
export function registerStep2Result(res) {
  if (res?.token) return { token: res.token, role: res.role }
  return { error: res?.stage === 'wipe_confirmation_required' ? 'Mật khẩu không khớp với mật khẩu lớp hai vừa đặt' : UNKNOWN_RESPONSE }
}
