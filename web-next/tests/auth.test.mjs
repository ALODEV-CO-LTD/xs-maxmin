// Đăng nhập / đăng ký (luồng 2 lớp mật khẩu, khôi phục, mã hỗ trợ) và khung app (menu, nút Quay lại, nhãn đồng bộ, dấu mờ).
import test from 'node:test'
import assert from 'node:assert/strict'

const mem = new Map()
globalThis.localStorage = { getItem: (k) => (mem.has(k) ? mem.get(k) : null), setItem: (k, v) => mem.set(k, String(v)), removeItem: (k) => mem.delete(k) }
let calls = []
let replies = {}
globalThis.fetch = async (url, init = {}) => {
  const key = `${init.method || 'GET'} ${url.replace(/^\/api/, '')}`
  calls.push({ key, body: init.body ? JSON.parse(init.body) : undefined })
  const r = replies[key]
  if (!r) throw new Error('no reply for ' + key)
  const { status = 200, body = {} } = r
  return { ok: status < 400, status, text: async () => JSON.stringify(body) }
}
const reset = () => ((calls = []), (replies = {}), mem.clear())

const F = await import('../src/lib/authFlow.js')
const { useAuthStore } = await import('../src/lib/authStore.js')
const { linksFor } = await import('../src/lib/navLinks.js')
const { syncLabel } = await import('../src/lib/offline.js')
const { watermarkTile, watermarkStyle } = await import('../src/lib/watermark.js')
const { backTargetOf } = await import('../src/lib/routes.ts')

// ---- redirect ----
test('safeRedirect: chỉ theo đường dẫn trong trang, không ra ngoài và không quay lại trang đăng nhập', () => {
  assert.equal(F.safeRedirect('/entries?x=1'), '/entries?x=1')
  assert.equal(F.safeRedirect('//evil.com'), null)
  assert.equal(F.safeRedirect('https://evil.com'), null)
  assert.equal(F.safeRedirect('/\\evil.com'), null)
  assert.equal(F.safeRedirect('/login?redirect=/entries'), null)
  assert.equal(F.safeRedirect(''), null)
  assert.equal(F.safeRedirect(undefined), null)
})

// ---- login stages ----
test('loginStageOf: done có hoặc không có trường stage; hai lớp; xoá dữ liệu; lạ', () => {
  assert.deepEqual(F.loginStageOf({ stage: 'done', token: 't', role: 'user' }), { kind: 'done', token: 't', role: 'user' })
  assert.deepEqual(F.loginStageOf({ token: 't2', role: 'admin' }), { kind: 'done', token: 't2', role: 'admin' })
  assert.deepEqual(F.loginStageOf({ stage: 'second_password_required', pendingToken: 'p' }), { kind: 'second_password', pendingToken: 'p' })
  assert.deepEqual(F.loginStageOf({ stage: 'wipe_confirmation_required', wipeToken: 'w' }), { kind: 'wipe_confirm', wipeToken: 'w' })
  assert.equal(F.loginStageOf({ stage: '???' }).kind, 'unknown')
  assert.equal(F.loginStageOf(null).kind, 'unknown')
})

test('đăng nhập hai lớp: bước 1 -> mật khẩu lớp hai -> lưu phiên', async () => {
  reset()
  useAuthStore.getState().init()
  assert.equal(F.credentialsProblem(' ', 'x'), 'Vui lòng nhập tên đăng nhập và mật khẩu')
  assert.equal(F.credentialsProblem('a', ''), 'Vui lòng nhập tên đăng nhập và mật khẩu')
  assert.equal(F.credentialsProblem('a', 'b'), '')
  replies['POST /auth/login'] = { body: { stage: 'second_password_required', pendingToken: 'pend' } }
  const s1 = F.loginStageOf(await F.loginStep1('  an  ', 'pw'))
  assert.equal(s1.kind, 'second_password')
  assert.deepEqual(calls[0].body, { username: 'an', password: 'pw' }) // tên đăng nhập được cắt khoảng trắng
  assert.equal(F.secondPasswordProblem(''), 'Vui lòng nhập mật khẩu lớp hai')
  replies['POST /auth/step2'] = { body: { token: 'jwt', role: 'user' } }
  const s2 = F.loginStageOf(await F.loginStep2(s1.pendingToken, 'pw2'))
  assert.deepEqual(calls[1].body, { pendingToken: 'pend', password: 'pw2' })
  useAuthStore.getState().login(s2.token, s2.role)
  assert.equal(useAuthStore.getState().token, 'jwt')
  assert.equal(mem.get('xoso_token'), 'jwt')
  assert.equal(mem.get('xoso_role'), 'user')
})

test('đăng nhập sai: lỗi của máy chủ hiện nguyên văn, lỗi lạ hiện câu chung', async () => {
  reset()
  replies['POST /auth/login'] = { status: 401, body: { error: 'Sai tên đăng nhập hoặc mật khẩu' } }
  await assert.rejects(F.loginStep1('a', 'b'), (e) => F.errMsg(e) === 'Sai tên đăng nhập hoặc mật khẩu')
  assert.equal(F.errMsg(new Error('x')), F.GENERIC_ERROR)
  assert.equal(useAuthStore.getState().token, 'jwt') // 401 ở /auth/ chỉ là sai mật khẩu: không xoá phiên đang có
})

test('mật khẩu xoá dữ liệu: bước xác nhận riêng, gọi confirm-wipe với wipeToken', async () => {
  reset()
  replies['POST /auth/step2'] = { body: { stage: 'wipe_confirmation_required', wipeToken: 'wt' } }
  const s = F.loginStageOf(await F.loginStep2('p', 'wipe-pw'))
  assert.equal(s.kind, 'wipe_confirm')
  replies['POST /auth/confirm-wipe'] = { body: {} }
  await F.confirmWipe(s.wipeToken)
  assert.deepEqual(calls.at(-1), { key: 'POST /auth/confirm-wipe', body: { wipeToken: 'wt' } })
})

// ---- recovery ----
test('khôi phục bằng mã: kiểm tra đủ trường, mật khẩu nhập lại khớp; gửi mã đã cắt khoảng trắng', async () => {
  reset()
  const f = { username: 'an', code: 'AAAA-BBBB', newPassword: 'n', confirm: 'n' }
  assert.equal(F.recoverProblem({ ...f, username: ' ' }), 'Vui lòng nhập tên đăng nhập và mã khôi phục')
  assert.equal(F.recoverProblem({ ...f, code: '' }), 'Vui lòng nhập tên đăng nhập và mã khôi phục')
  assert.equal(F.recoverProblem({ ...f, newPassword: '', confirm: '' }), 'Vui lòng nhập mật khẩu mới')
  assert.equal(F.recoverProblem({ ...f, confirm: 'x' }), 'Mật khẩu nhập lại không khớp')
  assert.equal(F.recoverProblem(f), '')
  replies['POST /auth/recover'] = { body: { recoveryCode: 'NEW-CODE' } }
  const res = await F.recoverWithCode({ ...f, username: ' an ', code: ' AAAA-BBBB ' })
  assert.equal(res.recoveryCode, 'NEW-CODE')
  assert.deepEqual(calls[0].body, { username: 'an', recoveryCode: 'AAAA-BBBB', newPassword: 'n' })
})

test('nhờ Admin hỗ trợ rồi dùng mã hỗ trợ', async () => {
  reset()
  assert.equal(F.helpProblem(' '), 'Vui lòng nhập tên đăng nhập')
  replies['POST /auth/recovery-request'] = { body: { message: 'Đã gửi' } }
  assert.equal((await F.requestHelp('an', ' ghi chú ')).message, 'Đã gửi')
  assert.deepEqual(calls[0].body, { username: 'an', note: 'ghi chú' })
  const f = { username: 'an', ticket: 'T-1', newPassword: 'n', confirm: 'n' }
  assert.equal(F.ticketProblem({ ...f, ticket: '' }), 'Vui lòng nhập tên đăng nhập và mã hỗ trợ')
  assert.equal(F.ticketProblem({ ...f, confirm: '' }), 'Mật khẩu nhập lại không khớp')
  assert.equal(F.ticketProblem(f), '')
  replies['POST /auth/recover-with-ticket'] = { body: { recoveryCode: 'C2' } }
  assert.equal((await F.recoverWithTicket(f)).recoveryCode, 'C2')
  assert.deepEqual(calls[1].body, { username: 'an', ticket: 'T-1', newPassword: 'n' })
})

// ---- register ----
const ok = { name: 'An', username: 'an123', password: 'p', confirmPassword: 'p', secondPassword: 's', wipePassword: '', wipeOpen: false }
test('đăng ký: kiểm tra từng trường theo luật của máy chủ', () => {
  const clean = F.registerFieldErrors(ok)
  assert.ok(Object.values(clean).every((v) => v === ''))
  assert.equal(F.registerFieldErrors({ ...ok, name: ' ' }).name, 'Vui lòng nhập tên hiển thị')
  assert.equal(F.registerFieldErrors({ ...ok, username: 'ab' }).username, 'Tên đăng nhập phải có ít nhất 3 ký tự')
  assert.equal(F.registerFieldErrors({ ...ok, password: '' }).password, 'Vui lòng nhập mật khẩu')
  assert.equal(F.registerFieldErrors({ ...ok, password: 'é'.repeat(40) }).password, 'Mật khẩu quá dài (tối đa 72 ký tự)') // 80 byte
  assert.equal(F.registerFieldErrors({ ...ok, confirmPassword: '' }).confirmPassword, 'Vui lòng nhập lại mật khẩu')
  assert.equal(F.registerFieldErrors({ ...ok, confirmPassword: 'q' }).confirmPassword, 'Mật khẩu xác nhận không khớp')
  assert.equal(F.registerFieldErrors({ ...ok, secondPassword: '' }).secondPassword, 'Vui lòng nhập mật khẩu')
})

test('đăng ký: mật khẩu xoá dữ liệu không bắt buộc, nhưng nếu có phải khác hai mật khẩu kia', () => {
  assert.equal(F.registerFieldErrors({ ...ok, wipePassword: 'zz', wipeOpen: false }).wipePassword, '') // ô đang đóng
  assert.equal(F.registerFieldErrors({ ...ok, wipeOpen: true, wipePassword: '' }).wipePassword, '')
  const same = 'Mật khẩu xoá dữ liệu phải khác 2 mật khẩu còn lại'
  assert.equal(F.registerFieldErrors({ ...ok, wipeOpen: true, wipePassword: 'p' }).wipePassword, same)
  assert.equal(F.registerFieldErrors({ ...ok, wipeOpen: true, wipePassword: 's' }).wipePassword, same)
  assert.equal(F.registerFieldErrors({ ...ok, wipeOpen: true, wipePassword: 'w' }).wipePassword, '')
})

test('đăng ký: gửi dữ liệu đã cắt, bỏ wipePassword rỗng; luôn đòi mật khẩu lớp hai rồi step2', async () => {
  reset()
  replies['POST /auth/register'] = { body: { stage: 'second_password_required', pendingToken: 'pt', recoveryCode: 'RC' } }
  const res = await F.registerAccount({ name: ' An ', username: ' an123 ', password: 'p', secondPassword: 's', wipePassword: '' })
  assert.equal(res.recoveryCode, 'RC')
  assert.deepEqual(calls[0].body, { name: 'An', username: 'an123', password: 'p', secondPassword: 's' })
  replies['POST /auth/step2'] = { body: { token: 'jwt', role: 'user' } }
  assert.deepEqual(F.registerStep2Result(await F.loginStep2('pt', 's')), { token: 'jwt', role: 'user' })
  assert.match(F.registerStep2Result({ stage: 'wipe_confirmation_required' }).error, /không khớp/)
  assert.equal(F.registerStep2Result({}).error, F.UNKNOWN_RESPONSE)
  assert.deepEqual(F.REGISTER_ACCOUNT_FIELDS.concat(F.REGISTER_SECURITY_FIELDS).every((f) => F.REGISTER_FIELD_IDS[f]), true)
})

// ---- shell ----
test('menu: khách thấy 7 mục; admin chỉ thấy mục đúng quyền, "Phân quyền" chỉ cho root', () => {
  const none = () => false
  assert.deepEqual(linksFor(false, false, none).map((l) => l.path), ['/entries', '/results', '/scoring', '/customers', '/scoring-settings', '/friends', '/account'])
  const can = (perms) => (p) => (Array.isArray(p) ? p : [p]).some((x) => perms.includes(x))
  assert.deepEqual(linksFor(true, false, can(['stats.view', 'support.messages'])).map((l) => l.path), ['/admin/stats', '/admin/messages', '/account'])
  assert.deepEqual(linksFor(true, false, can(['announcements.manage'])).map((l) => l.path), ['/admin/notices', '/account'])
  assert.ok(linksFor(true, true, () => true).some((l) => l.path === '/admin/staff'))
  assert.ok(!linksFor(true, false, () => true).some((l) => l.path === '/admin/staff'))
})

test('nút Quay lại: Khách hàng mở từ Nhập số quay về Nhập số', () => {
  assert.deepEqual(backTargetOf('/customers', new URLSearchParams('from=entries')), { path: '/entries', title: 'Nhập số' })
  assert.equal(backTargetOf('/customers', new URLSearchParams('')), null)
  assert.equal(backTargetOf('/entries', new URLSearchParams('from=entries')), null)
})

test('chip đồng bộ: nhãn theo trạng thái', () => {
  assert.equal(syncLabel({ syncing: true, online: true, pending: 3 }), 'Đang đồng bộ...')
  assert.equal(syncLabel({ syncing: false, online: false, pending: 0 }), 'Offline')
  assert.equal(syncLabel({ syncing: false, online: false, pending: 2 }), 'Offline · 2 chờ đồng bộ')
  assert.equal(syncLabel({ syncing: false, online: true, pending: 2 }), '2 chờ đồng bộ')
  assert.equal(syncLabel({ syncing: false, online: true, pending: 0 }), '')
})

test('dấu mờ người xem: có tên, tài khoản, giờ, 4 số cuối id; ký tự đặc biệt được thoát; không có người dùng thì không vẽ', () => {
  assert.equal(watermarkTile(null, new Date(), false), '')
  const t = decodeURIComponent(watermarkTile({ name: 'A<b>', username: 'an', id: 'user-12345678' }, new Date(2026, 9, 18, 7, 5), false))
  assert.match(t, /A&lt;b&gt; · an/)
  assert.match(t, /07:05 18\/10\/2026 · 5678/)
  assert.match(t, /rgba\(30,41,59,0.20\)/)
  assert.match(decodeURIComponent(watermarkTile({ name: 'a', username: 'b', id: '1' }, new Date(), true)), /rgba\(255,255,255,0.15\)/)
  const css = watermarkStyle('url(x)')
  assert.match(css, /pointer-events:none!important/)
  assert.match(css, /background-image:url\(x\)!important/)
})
