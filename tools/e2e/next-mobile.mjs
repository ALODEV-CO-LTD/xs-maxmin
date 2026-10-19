// QA giao diện điện thoại (390px): danh sách <-> hội thoại, tràn ngang, nút Quay lại, màn Tài khoản (hai người dùng) trên backend thử.
//   SITE_A=http://127.0.0.1:8622 SITE_B=http://127.0.0.1:8622 PPT=/đường/dẫn node tools/e2e/next-chat.mjs
// SITE_A/SITE_B có thể là bản Next (8622) hoặc bản Vue (8623) để thử chéo giao thức. Backend: BE (mặc định 8621).
import { createRequire } from 'node:module'
const puppeteer = createRequire((process.env.PPT || process.cwd()) + '/')('puppeteer-core')
const SA = process.env.SITE_A || 'http://127.0.0.1:8622', SB = process.env.SITE_B || SA
const API = `http://127.0.0.1:${process.env.BE || 8621}/api`
const SHOTS = process.env.SHOTS || '/private/tmp/claude-501/shots'
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const call = async (m, p, b, t) => { const r = await fetch(API + p, { method: m, headers: { 'content-type': 'application/json', 'x-forwarded-for': FAKE_IP, ...(t ? { authorization: 'Bearer ' + t } : {}) }, body: b ? JSON.stringify(b) : undefined }); return { s: r.status, j: await r.json().catch(() => null) } }
// backend thử giới hạn 10 lần đăng ký/giờ/IP: mỗi lần chạy dùng một IP giả (backend tin x-forwarded-for từ loopback)
const FAKE_IP = `10.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}.${1 + Math.floor(Math.random() * 250)}`
let pass = 0, fail = 0
const ok = (c, n, extra = '') => { c ? pass++ : fail++; console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : ' ' + extra)) }
async function mkUser(tag) {
  const username = tag + Date.now().toString(36).slice(-5)
  const reg = (await call('POST', '/auth/register', { name: 'User ' + tag, username, password: 'Pass-1234', secondPassword: 'Second-1234' })).j
  const token = (await call('POST', '/auth/step2', { pendingToken: reg.pendingToken, password: 'Second-1234' })).j.token
  const me = (await call('GET', '/me', null, token)).j
  return { username, token, me, name: 'User ' + tag }
}
const br = await puppeteer.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true, args: ['--no-sandbox', '--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream'] })
const errs = []
async function openPage(site, u, path = '/friends') {
  const ctx = await br.createBrowserContext(); const p = await ctx.newPage(); await p.setViewport({ width: 1200, height: 850 })
  p.on('pageerror', (e) => errs.push(`${u.name} pageerror: ${e.message.slice(0, 160)}`))
  p.on('console', (m) => { if (m.type() === 'error' && !/vibrate/.test(m.text())) errs.push(`${u.name} console: ${m.text().slice(0, 160)}`) })
  p.on('response', (x) => { if (x.url().includes('/api/') && x.status() >= 400 && ![401, 404].includes(x.status())) errs.push(`${u.name} HTTP ${x.status()} ${x.url().replace(site, '').slice(0, 80)}`) })
  await p.goto(site + '/login', { waitUntil: 'networkidle0' })
  await p.evaluate((t) => { localStorage.setItem('xoso_token', t); localStorage.setItem('xoso_role', 'user') }, u.token)
  await p.goto(site + path, { waitUntil: 'networkidle0' }); await sleep(1500)
  p.ctx = ctx
  return p
}
// helpers on a page
const text = (p) => p.evaluate(() => document.body.innerText)
async function clickText(p, label, sel = 'button, a, [role=menuitem]', exact = true) {
  const h = await p.evaluateHandle((label, sel, exact) => [...document.querySelectorAll(sel)].find((e) => { const t = e.innerText?.trim(); return exact ? t === label : t?.includes(label) }) || null, label, sel, exact)
  const el = h.asElement(); if (!el) throw new Error('no element: ' + label)
  await el.click()
}
async function waitText(p, s, ms = 8000) { const t0 = Date.now(); while (Date.now() - t0 < ms) { if ((await text(p)).includes(s)) return true; await sleep(200) } return false }
async function gone(p, s, ms = 5000) { const t0 = Date.now(); while (Date.now() - t0 < ms) { if (!(await text(p)).includes(s)) return true; await sleep(200) } return false }
async function send(p, msg) { await p.click('.send-row input[type=text]'); await p.type('.send-row input[type=text]', msg); await p.keyboard.press('Enter') }
async function ctxMenu(p, msgText, item) {
  const h = await p.evaluateHandle((t) => [...document.querySelectorAll('.msg-bubble')].reverse().find((e) => e.innerText.includes(t)), msgText)
  const el = h.asElement(); if (!el) throw new Error('no bubble: ' + msgText)
  const b = await el.boundingBox(); await p.mouse.click(b.x + 5, b.y + 5, { button: 'right' }); await sleep(250)
  await clickText(p, item, '[role=menuitem]')
}
const bubbles = (p) => p.evaluate(() => [...document.querySelectorAll('.msg-bubble')].map((e) => e.innerText.replace(/\s+/g, ' ').trim()))

try {
  const A = await mkUser('ra'), B = await mkUser('rb')
  await call('POST', '/me/friends', { userId: B.me.id }, A.token); const rq = (await call('GET', '/me/friend-requests', null, B.token)).j.incoming[0]; await call('POST', `/me/friend-requests/${rq.id}/accept`, {}, B.token)
  const pb = await openPage(SB, B); const pa = await openPage(SA, A)
  for (const p of [pa, pb]) { await p.setViewport({ width: 390, height: 844, isMobile: true, hasTouch: true }); await p.reload({ waitUntil: 'networkidle0' }); await sleep(1500) }
  const noOverflow = (p) => p.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)
  ok(await noOverflow(pa), 'danh sách: không tràn ngang')
  ok(!(await pa.$('.thread-body')) || !(await pa.evaluate(() => { const e = document.querySelector('.thread-pane'); return e && e.offsetParent !== null && getComputedStyle(e).display !== 'none' })), 'điện thoại: chưa chọn thì chỉ thấy danh sách')
  await pa.tap('.friend-item'); await sleep(800)
  ok(await pa.evaluate(() => !!document.querySelector('.thread-body') && document.querySelector('.thread-body').offsetParent !== null), 'chạm bạn -> mở hội thoại')
  ok(await noOverflow(pa), 'hội thoại: không tràn ngang')
  await pb.tap('.friend-item'); await sleep(600)
  await pa.type('.send-row input[type=text]', 'tin tu dien thoai'); await pa.tap('.send-row button[type=submit]')
  ok(await waitText(pb, 'tin tu dien thoai'), 'gửi trên điện thoại, bên kia nhận')
  await pa.screenshot({ path: SHOTS + '/mobile-thread.png' })
  // nhấn giữ mở menu tin nhắn
  const b = await (await pa.$('.msg-bubble')).boundingBox()
  await pa.touchscreen.touchStart(b.x + 10, b.y + 10); await sleep(700); const menuWhileHeld = await pa.evaluate(() => !!document.querySelector('[role=menu]')); await pa.touchscreen.touchEnd(); await sleep(300)
  console.log('  menu khi còn giữ:', menuWhileHeld, '| sau khi nhả:', await pa.evaluate(() => !!document.querySelector('[role=menu]')))
  ok(menuWhileHeld, 'nhấn giữ tin nhắn mở menu (Trả lời/Ghim/...)')
  await pa.screenshot({ path: SHOTS + '/mobile-menu.png' })
  await pa.keyboard.press('Escape'); await pa.mouse.click(5, 5).catch(() => {}); await sleep(300)
  await pa.tap('.back-btn').catch(() => {}); await sleep(500)
  ok(await pa.evaluate(() => !!document.querySelector('.friend-item') && document.querySelector('.friend-item').offsetParent !== null), 'Quay lại -> về danh sách')
  await pa.goto(SA + '/account', { waitUntil: 'networkidle0' }); await sleep(1200)
  ok(await noOverflow(pa), '/account: không tràn ngang'); await pa.screenshot({ path: SHOTS + '/mobile-account.png' })
  await pa.tap('#acct-tab-profile'); await sleep(400)
  ok(await pa.evaluate(() => [...document.querySelectorAll('button')].some((e) => e.offsetParent && /Đăng xuất/.test(e.innerText))), '/account: có nút Đăng xuất trên điện thoại (tab Hồ sơ)')
} catch (e) { fail++; console.log('FAIL exception', e.message) }
console.log(`${pass} pass, ${fail} fail`)
for (const e of [...new Set(errs)].slice(0, 15)) console.log('  ' + e)
await br.close()
process.exit(fail ? 1 : 0)
