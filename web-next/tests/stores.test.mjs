// Hành vi các store (notify, privacy, policy, mask, theme, confirm, packageLabels, session, offline) - chạy không cần trình duyệt.
import test from 'node:test'
import assert from 'node:assert/strict'

// ---- minimal browser stand-ins ----
const mem = new Map()
globalThis.localStorage = { getItem: (k) => (mem.has(k) ? mem.get(k) : null), setItem: (k, v) => mem.set(k, String(v)), removeItem: (k) => mem.delete(k) }
const listeners = {}
const target = () => ({ addEventListener: (e, f) => ((listeners[e] ||= new Set()).add(f)), removeEventListener: (e, f) => listeners[e]?.delete(f) })
globalThis.window = { ...target(), location: { pathname: '/entries', search: '', assign() {} }, matchMedia: () => ({ matches: false, ...target() }) }
globalThis.document = { ...target(), hidden: false, visibilityState: 'visible', hasFocus: () => true, documentElement: { dataset: {}, classList: { add() {}, remove() {} } }, title: '' }
Object.defineProperty(globalThis, 'navigator', { value: { onLine: true }, configurable: true })
// scripted backend
let calls = []
let replies = {}
globalThis.fetch = async (url, init = {}) => {
  const key = `${init.method || 'GET'} ${url.replace(/^\/api/, '')}`
  calls.push({ key, body: init.body ? JSON.parse(init.body) : undefined })
  const r = replies[key]
  if (r instanceof Error) throw r
  const { status = 200, body = {} } = r || {}
  return { ok: status < 400, status, text: async () => JSON.stringify(body) }
}
const reset = () => ((calls = []), (replies = {}), mem.clear())

const { useNotifyStore, totalOf, friendUnreadOf, adminSupportUnreadOf, supportUnreadOf } = await import('../src/lib/notifyStore.js')
const { usePrivacyStore } = await import('../src/lib/privacyStore.js')
const { usePolicyStore } = await import('../src/lib/policyStore.js')
const { mask, REVEAL_CHOICES, useMaskStore } = await import('../src/lib/maskStore.js')
const { initTheme, setTheme, toggleTheme, getTheme } = await import('../src/lib/theme.js')
const { showConfirm, resolveConfirm, useConfirmStore } = await import('../src/lib/confirm.js')
const { loadPackageLabels, packageLabel } = await import('../src/lib/packageLabels.js')
const { teardownSession } = await import('../src/lib/session.js')
const { hooks, registerTeardown, setNavigator } = await import('../src/lib/hooks.js')
const { useAuthStore } = await import('../src/lib/authStore.js')
const offline = await import('../src/lib/offline.js')

test('notify: bộ đếm theo khoá và getter tổng', () => {
  const n = useNotifyStore
  n.getState().clearAll()
  n.setState({ unread: { 'friend:a': 2, 'friend:b': 1, support: 3, 'support:u1': 4 }, friendRequests: 2 })
  assert.equal(totalOf(n.getState()), 12)
  assert.equal(friendUnreadOf(n.getState()), 3)
  assert.equal(supportUnreadOf(n.getState()), 3)
  assert.equal(adminSupportUnreadOf(n.getState()), 4)
  n.getState().setFriendRequests(-5)
  assert.equal(n.getState().friendRequests, 0)
})

test('notify: tin nhắn bạn bè tăng bộ đếm, tạo toast, tối đa 3 toast, bấm toast chuyển trang', () => {
  const n = useNotifyStore
  n.getState().clearAll()
  const pushed = []
  setNavigator((to) => pushed.push(to))
  for (let i = 0; i < 5; i++) n.getState().receive({ source: 'friend', from: 'f1', fromName: 'An', preview: 'hi' })
  assert.equal(n.getState().unread['friend:f1'], 5)
  assert.equal(n.getState().toasts.length, 3)
  assert.equal(n.getState().incomingTick, 5)
  const t = n.getState().toasts[0]
  assert.equal(t.to, '/friends?thread=f1')
  n.getState().open(t)
  assert.deepEqual(pushed, ['/friends?thread=f1'])
  assert.ok(!n.getState().toasts.some((x) => x.id === t.id))
  n.getState().clearAll()
})

test('notify: đang xem đúng cuộc trò chuyện thì không đếm', () => {
  const n = useNotifyStore
  n.getState().clearAll()
  window.location.pathname = '/friends'
  window.location.search = '?thread=f9'
  const tick = n.getState().incomingTick
  n.getState().receive({ source: 'friend', from: 'f9' })
  assert.equal(n.getState().unread['friend:f9'], undefined)
  assert.equal(n.getState().incomingTick, tick + 1)
  n.setState({ supportVisible: true })
  n.getState().receive({ source: 'support', from: 'x' })
  assert.equal(n.getState().unread.support, undefined)
  window.location.pathname = '/admin/messages'
  window.location.search = '?user=u7'
  n.getState().receive({ source: 'support', from: 'u7' }, { isAdmin: true })
  assert.equal(n.getState().unread['support:u7'], undefined)
  n.getState().receive({ source: 'support', from: 'u8' }, { isAdmin: true })
  assert.equal(n.getState().unread['support:u8'], 1)
  assert.equal(n.getState().toasts.at(-1).to, '/admin/messages?user=u8')
  window.location.pathname = '/entries'
  window.location.search = ''
  n.getState().clearAll()
})

test('notify: refresh giữ bộ đếm bạn bè cục bộ, lấy phần hỗ trợ từ máy chủ; clear báo máy chủ', async () => {
  reset()
  const n = useNotifyStore
  n.setState({ unread: { 'friend:a': 2, support: 9 }, friendRequests: 0 })
  replies['GET /me/unread'] = { body: { support: 1, supportByUser: { u1: 2, u2: 0 }, friendRequests: 3 } }
  await n.getState().refresh()
  assert.deepEqual(n.getState().unread, { 'friend:a': 2, support: 1, 'support:u1': 2 })
  assert.equal(n.getState().friendRequests, 3)
  replies['POST /me/unread/read'] = {}
  n.getState().clear('support:u1')
  assert.equal(n.getState().unread['support:u1'], undefined)
  assert.deepEqual(calls.at(-1), { key: 'POST /me/unread/read', body: { peerId: 'u1' } })
  const marked = []
  hooks.markFriendRead = (id) => marked.push(id)
  n.getState().clear('friend:a')
  assert.deepEqual(marked, ['a'])
  assert.equal(n.getState().unread['friend:a'], undefined)
  n.getState().clearAll()
})

test('notify: thanh toán / kết bạn đẩy toast và tăng tick', () => {
  const n = useNotifyStore
  n.getState().clearAll()
  n.getState().paymentDecided({ status: 'rejected', reason: 'sai số tiền' })
  assert.equal(n.getState().paymentTick, 1)
  assert.equal(n.getState().toasts.at(-1).body, 'Lý do: sai số tiền')
  n.getState().friendRequestReceived({ fromName: 'Bình' })
  assert.equal(n.getState().friendRequests, 1)
  assert.equal(n.getState().toasts.at(-1).title, 'Bình gửi lời mời kết bạn')
  n.getState().friendAcceptedByPeer({ name: 'Chi' })
  assert.equal(n.getState().requestsTick, 2)
  assert.equal(n.getState().lastFriendEvent.type, 'friend-accepted')
  n.getState().clearAll()
})

test('privacy: khoá, mở khoá bằng mật khẩu, lưu cài đặt', async () => {
  reset()
  const p = usePrivacyStore
  p.getState().stop()
  p.getState().saveSettings({ autoLockMinutes: 5, hideLockSeconds: 10 })
  assert.deepEqual(JSON.parse(mem.get('xoso_privacy')), { autoLockMinutes: 5, hideLockSeconds: 10, blurOnHide: true })
  p.getState().lock()
  assert.equal(p.getState().locked, true)
  assert.equal(mem.get('xoso_locked'), '1')
  replies['POST /me/verify-password'] = { status: 403, body: { error: 'Sai mật khẩu' } }
  await assert.rejects(p.getState().unlock('x'), /Sai mật khẩu/)
  assert.equal(p.getState().locked, true)
  replies['POST /me/verify-password'] = { body: {} }
  await p.getState().unlock('ok')
  assert.equal(p.getState().locked, false)
  assert.equal(mem.has('xoso_locked'), false)
})

test('privacy: không khoá khi đang gọi; mặc định máy chủ chỉ áp dụng khi chưa tự chọn', () => {
  reset()
  const p = usePrivacyStore
  p.getState().stop()
  hooks.inCall = () => true
  p.getState().lock()
  assert.equal(p.getState().locked, false)
  hooks.inCall = () => false
  p.setState({ autoLockMinutes: 0 })
  p.getState().applyServerDefault(15)
  assert.equal(p.getState().autoLockMinutes, 15)
  p.getState().saveSettings({ autoLockMinutes: 2 })
  p.getState().applyServerDefault(30)
  assert.equal(p.getState().autoLockMinutes, 2)
})

test('privacy: start() khoá lại sau khi tải lại và khi quá thời gian rảnh; stop() dọn dẹp', () => {
  reset()
  const p = usePrivacyStore
  p.getState().stop()
  mem.set('xoso_locked', '1')
  p.getState().start()
  assert.equal(p.getState().locked, true)
  assert.ok(listeners.keydown?.size > 0)
  p.getState().stop()
  assert.equal(p.getState().locked, false)
  assert.equal(listeners.keydown?.size || 0, 0)
  mem.set('xoso_privacy', JSON.stringify({ autoLockMinutes: 1 }))
  mem.set('xoso_last_active', String(Date.now() - 120000))
  p.getState().start()
  assert.equal(p.getState().locked, true)
  p.getState().stop()
})

test('privacy: làm mờ khi rời trang chỉ khi chính sách cho phép', () => {
  reset()
  const p = usePrivacyStore
  p.getState().stop()
  p.getState().start()
  const fire = (ev) => [...(listeners[ev] || [])].forEach((f) => f())
  fire('blur')
  assert.equal(p.getState().away, false)
  p.getState().setBlurPolicy(true)
  fire('blur')
  assert.equal(p.getState().away, true)
  fire('focus')
  assert.equal(p.getState().away, false)
  p.getState().stop()
})

test('policy: load đọc /me/policy và đẩy sang privacy; lỗi giữ mặc định an toàn', async () => {
  reset()
  usePrivacyStore.getState().stop()
  usePrivacyStore.setState({ autoLockMinutes: 0 })
  replies['GET /me/policy'] = { body: { watermarkEnabled: true, screenshotGuardEnabled: false, blurOnHideEnabled: true, autoLockMinutes: 7 } }
  await usePolicyStore.getState().load()
  const s = usePolicyStore.getState()
  assert.deepEqual([s.watermarkEnabled, s.screenshotGuardEnabled, s.blurOnHideEnabled, s.autoLockMinutes, s.loaded], [true, false, true, 7, true])
  assert.equal(usePrivacyStore.getState().blurPolicy, true)
  assert.equal(usePrivacyStore.getState().autoLockMinutes, 7)
  usePolicyStore.setState({ watermarkEnabled: false, loaded: false })
  replies['GET /me/policy'] = new Error('down')
  await usePolicyStore.getState().load()
  assert.equal(usePolicyStore.getState().loaded, false)
  assert.equal(usePolicyStore.getState().watermarkEnabled, false)
})

test('mask: luôn hiển thị số liệu; thời gian rảnh chỉ nhận các lựa chọn hợp lệ', () => {
  assert.equal(mask.masked(), false)
  mask.setRevealSeconds(60)
  assert.equal(useMaskStore.getState().revealSeconds, 60)
  assert.equal(mem.get('xoso_mask_reveal_seconds'), '60')
  mask.setRevealSeconds(7)
  assert.equal(useMaskStore.getState().revealSeconds, 60)
  assert.deepEqual(REVEAL_CHOICES, [10, 20, 30, 60, 300])
})

test('mask: mở xem rồi tự che sau thời gian rảnh, che ngay khi mất focus', async () => {
  window.__MASK_TEST = { revealMs: 50 }
  mask.attach()
  mask.reveal()
  assert.equal(useMaskStore.getState().revealed, true)
  await new Promise((r) => setTimeout(r, 90))
  assert.equal(useMaskStore.getState().revealed, false)
  mask.reveal()
  ;[...listeners.blur].forEach((f) => f())
  assert.equal(useMaskStore.getState().revealed, false)
  mask.detach()
  assert.equal(listeners.pointerdown?.size || 0, 0)
  delete window.__MASK_TEST
})

test('theme: lưu lựa chọn, áp lên <html>, đổi qua lại', () => {
  reset()
  initTheme()
  assert.equal(getTheme(), 'light')
  toggleTheme()
  assert.equal(getTheme(), 'dark')
  assert.equal(document.documentElement.dataset.theme, 'dark')
  assert.equal(mem.get('xoso_theme'), 'dark')
  setTheme('light')
  assert.equal(document.documentElement.dataset.theme, 'light')
})

test('confirm: trả về true/false, mở hộp thứ hai thì huỷ hộp trước', async () => {
  const a = showConfirm({ title: 'Xoá?', danger: true })
  assert.equal(useConfirmStore.getState().open, true)
  assert.equal(useConfirmStore.getState().danger, true)
  const b = showConfirm({ message: 'm' })
  assert.equal(await a, false)
  assert.equal(useConfirmStore.getState().title, 'Xác nhận')
  resolveConfirm(true)
  assert.equal(await b, true)
  assert.equal(useConfirmStore.getState().open, false)
})

test('packageLabels: nhãn cố định + danh mục từ máy chủ', async () => {
  reset()
  assert.equal(packageLabel('trial'), 'Dùng thử 30 ngày')
  assert.equal(packageLabel('p1'), 'p1')
  replies['GET /me/packages?all=1'] = { body: { packages: [{ type: 'p1', label: '1 tháng' }] } }
  await loadPackageLabels()
  assert.equal(packageLabel('p1'), '1 tháng')
})

test('session: teardownSession xoá thông báo và chạy cả những bước dọn khác dù một bước lỗi', () => {
  useNotifyStore.setState({ unread: { support: 1 }, toasts: [{ id: 1 }], friendRequests: 2 })
  const ran = []
  const off1 = registerTeardown(() => { throw new Error('boom') })
  const off2 = registerTeardown(() => ran.push('call'))
  teardownSession()
  off1(); off2()
  assert.deepEqual(ran, ['call'])
  assert.deepEqual(useNotifyStore.getState().unread, {})
  assert.deepEqual(useNotifyStore.getState().toasts, [])
  assert.equal(useNotifyStore.getState().friendRequests, 0)
})

// ---- offline (no IndexedDB here: the network path, the error path and the sync state) ----
const jwt = (sub) => `x.${Buffer.from(JSON.stringify({ sub })).toString('base64')}.y`

test('offline: trạng thái đồng bộ - xung đột và lỗi được thêm / bỏ đúng', () => {
  const s = offline.useSyncStore
  s.setState({ conflicts: [], failures: [{ id: 'a', message: 'm' }, { id: 'b', message: 'n' }] })
  offline.addConflict({ id: 'e1' }, { value: 1 }, { value: 2 })
  assert.deepEqual(s.getState().conflicts, [{ opId: null, entryId: 'e1', mine: { value: 1 }, server: { value: 2 } }])
  assert.equal(offline.syncState.conflicts.length, 1)
  offline.dismissFailure('a')
  assert.deepEqual(s.getState().failures.map((f) => f.id), ['b'])
})

test('offline: cachedGet trả dữ liệu mới và đánh dấu online; lỗi nghiệp vụ được ném lại', async () => {
  reset()
  useAuthStore.setState({ token: jwt('u1') })
  replies['GET /me/profile'] = { body: { name: 'A' } }
  assert.deepEqual(await offline.cachedGet('/me/profile'), { name: 'A' })
  assert.equal(offline.syncState.online, true)
  replies['GET /me/profile'] = { status: 500, body: { error: 'hỏng' } }
  await assert.rejects(offline.cachedGet('/me/profile'), /hỏng/)
  assert.equal(offline.syncState.online, true)
})

test('offline: tạo bản ghi online gửi kèm clientId', async () => {
  reset()
  useAuthStore.setState({ token: jwt('u1') })
  replies['POST /me/entries'] = { body: { id: 'srv1', value: '12' } }
  const { entry, queued } = await offline.createEntry({ value: '12' })
  assert.equal(queued, false)
  assert.equal(entry.id, 'srv1')
  assert.ok(calls[0].body.clientId)
  replies['POST /me/entries'] = { status: 403, body: { error: 'Hết hạn mức' } }
  await assert.rejects(offline.createEntry({ value: '1' }), /Hết hạn mức/)
})

test('notify: toast "Phản hồi" mở popover thay vì chuyển trang', async () => {
  const { goTo, FEEDBACK } = await import('../src/lib/notifyStore.js')
  const pushed = []
  setNavigator((to) => pushed.push(to))
  useNotifyStore.setState({ supportOpen: false })
  goTo(FEEDBACK)
  assert.equal(useNotifyStore.getState().supportOpen, true)
  assert.deepEqual(pushed, [])
  goTo('/friends')
  assert.deepEqual(pushed, ['/friends'])
})
