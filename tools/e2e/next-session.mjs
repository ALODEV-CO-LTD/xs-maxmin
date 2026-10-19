// QA đổi tài khoản trong CÙNG trình duyệt qua giao diện đăng nhập thật: không rò chat, mỗi người một kho riêng, đăng nhập lại thấy lại chat (hai người dùng) trên backend thử.
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
  const A = await mkUser('sa'), B = await mkUser('sb')
  await call('POST', '/me/friends', { userId: B.me.id }, A.token); const rq = (await call('GET', '/me/friend-requests', null, B.token)).j.incoming[0]; await call('POST', `/me/friend-requests/${rq.id}/accept`, {}, B.token)
  const pb = await openPage(SB, B)
  // một trình duyệt, đăng nhập bằng form như người dùng thật
  const ctx = await br.createBrowserContext(); const p = await ctx.newPage(); await p.setViewport({ width: 1200, height: 850 })
  p.on('pageerror', (e) => errs.push('pageerror ' + e.message.slice(0, 150)))
  async function uiLogin(u) {
    await p.goto(SA + '/login', { waitUntil: 'networkidle0' })
    await p.type('#username', u.username); await p.type('#password', 'Pass-1234'); await p.keyboard.press('Enter'); await sleep(1500)
    await p.type('#second-password', 'Second-1234'); await p.keyboard.press('Enter'); await sleep(2500)
  }
  await uiLogin(A); ok(new URL(p.url()).pathname !== '/login', 'đăng nhập A bằng form 2 lớp: vào được app', p.url())
  await p.goto(SA + '/friends', { waitUntil: 'networkidle0' }); await sleep(1500)
  await clickText(p, 'User sb', '.friend-item', false); await clickText(pb, 'User sa', '.friend-item', false); await sleep(500)
  await send(p, 'bi mat cua A'); ok(await waitText(pb, 'bi mat cua A'), 'A gửi, B nhận')
  // đăng xuất qua nút ở thanh trên
  await clickText(p, 'Đăng xuất', 'button'); await sleep(400); await clickText(p, 'Đăng xuất', '[role=alertdialog] button'); await sleep(1500)
  ok(new URL(p.url()).pathname === '/login', 'đăng xuất -> về /login')
  // B (là người khác) đăng nhập vào chính trình duyệt đó
  await uiLogin(B); await p.goto(SA + '/friends', { waitUntil: 'networkidle0' }); await sleep(1500)
  ok(!(await text(p)).includes('bi mat cua A'), 'B đăng nhập cùng trình duyệt: không thấy tin của A')
  await clickText(p, 'User sa', '.friend-item', false); await sleep(800)
  ok(!(await text(p)).includes('bi mat cua A'), 'hội thoại với A của B chưa có tin của A (kho riêng)')
  await clickText(p, 'Đăng xuất', 'button'); await sleep(400); await clickText(p, 'Đăng xuất', '[role=alertdialog] button'); await sleep(1500)
  // A đăng nhập lại: tin cũ còn (kho IndexedDB theo người dùng)
  await uiLogin(A); await p.goto(SA + '/friends', { waitUntil: 'networkidle0' }); await sleep(1500)
  await clickText(p, 'User sb', '.friend-item', false); await sleep(1000)
  ok((await text(p)).includes('bi mat cua A'), 'A đăng nhập lại: tin nhắn cũ vẫn còn trên máy này')
  // B đã đăng nhập ở máy thứ hai (trình duyệt dùng chung) nên khoá của B trên máy chủ đã đổi (mỗi tài khoản một khoá, máy sau cùng thắng):
  // A phải thấy cảnh báo "khoá bảo mật đã thay đổi" (giống bản Vue/app).
  ok((await text(p)).includes('đã thay đổi'), 'A được cảnh báo khoá của B đã đổi (B đăng nhập ở máy khác)')
} catch (e) { fail++; console.log('FAIL exception', e.message) }
console.log(`${pass} pass, ${fail} fail`)
for (const e of [...new Set(errs)].slice(0, 15)) console.log('  ' + e)
await br.close()
process.exit(fail ? 1 : 0)
