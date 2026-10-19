// QA danh sách hội thoại: Sửa -> lưu trữ / xoá cuộc trò chuyện, tìm kiếm trong danh sách, lời mời chéo tự thành bạn, sắp xếp theo tin mới (hai người dùng) trên backend thử.
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
  const A = await mkUser('ea'), B = await mkUser('eb'), C = await mkUser('ec')
  // lời mời chéo: A mời B, B mời A -> thành bạn ngay
  const r1 = await call('POST', '/me/friends', { userId: B.me.id }, A.token); const r2 = await call('POST', '/me/friends', { userId: A.me.id }, B.token)
  ok(r1.j.status === 'pending' && r2.j.status === 'friends', 'lời mời chéo -> thành bạn ngay', JSON.stringify([r1.j, r2.j]).slice(0, 160))
  await call('POST', '/me/friends', { userId: C.me.id }, A.token); const rq = (await call('GET', '/me/friend-requests', null, C.token)).j.incoming[0]; await call('POST', `/me/friend-requests/${rq.id}/accept`, {}, C.token)
  const pb = await openPage(SB, B), pc = await openPage(SB, C); const pa = await openPage(SA, A)
  for (const q of [pb, pc]) { await q.reload({ waitUntil: 'networkidle0' }); await sleep(1200) } // A đã đăng khoá
  await clickText(pa, 'User eb', '.friend-item', false); await clickText(pb, 'User ea', '.friend-item', false); await sleep(500)
  await send(pb, 'eb nhan truoc'); await waitText(pa, 'eb nhan truoc')
  await clickText(pa, 'User ec', '.friend-item', false); await clickText(pc, 'User ea', '.friend-item', false); await sleep(500)
  await send(pc, 'ec nhan sau'); await waitText(pa, 'ec nhan sau')
  await pa.reload({ waitUntil: 'networkidle0' }); await sleep(1500)
  const order = await pa.$$eval('.friend-item strong', (e) => e.map((x) => x.innerText.replace(/\s+/g, ' ').trim()))
  console.log('  thứ tự:', order.join(' > ')); ok(order[0].startsWith('User ec') && order[1].startsWith('User eb'), 'hội thoại có tin mới nhất lên đầu')
  // tìm trong danh sách
  await clickText(pa, 'Tìm kiếm', 'button'); await pa.type('#searchQuery', 'eb'); await sleep(900)
  ok(await pa.$$eval('.friend-item', (e) => e.length) === 1, 'tìm kiếm lọc danh sách bạn bè theo tên')
  await clickText(pa, 'Đóng', 'button'); await sleep(300)
  // Sửa -> lưu trữ B
  await clickText(pa, 'Sửa', 'button'); await sleep(300)
  await pa.evaluate(() => { const row = [...document.querySelectorAll('.friend-item')].find((e) => e.innerText.includes('User eb')); row.querySelector('.pick').click() }); await sleep(200)
  await clickText(pa, 'Lưu trữ (1)', 'button'); await sleep(600); await clickText(pa, 'Xong', 'button').catch(() => {})
  ok(!(await pa.$$eval('.friend-item', (e) => e.map((x) => x.innerText).join()).then((t) => t.includes('User eb'))), 'lưu trữ -> biến khỏi danh sách chính')
  ok((await text(pa)).includes('Đã lưu trữ (1)'), 'có mục "Đã lưu trữ (1)"')
  await clickText(pa, 'Đã lưu trữ (1)', 'button'); await sleep(400)
  ok((await text(pa)).includes('User eb'), 'mở Đã lưu trữ thấy lại')
  await clickText(pa, 'Sửa', 'button'); await pa.evaluate(() => document.querySelector('.friend-item .pick').click()); await clickText(pa, 'Bỏ lưu trữ (1)', 'button'); await sleep(500); await clickText(pa, 'Xong', 'button').catch(() => {})
  await clickText(pa, '← Về tin nhắn', 'button').catch(() => {}); await sleep(300)
  ok((await text(pa)).includes('User eb'), 'bỏ lưu trữ -> về danh sách')
  // Sửa -> xoá cuộc trò chuyện với C (xoá tin trên máy này)
  await clickText(pa, 'Sửa', 'button'); await sleep(300)
  await pa.evaluate(() => { const row = [...document.querySelectorAll('.friend-item')].find((e) => e.innerText.includes('User ec')); row.querySelector('.pick').click() })
  await clickText(pa, 'Xoá (1)', 'button'); await sleep(400); await clickText(pa, 'Xoá', '[role=alertdialog] button'); await sleep(1000); await clickText(pa, 'Xong', 'button').catch(() => {})
  await clickText(pa, 'User ec', '.friend-item', false); await sleep(800)
  ok(!(await text(pa)).includes('ec nhan sau'), 'xoá cuộc trò chuyện -> tin nhắn mất trên máy này')
  ok((await call('GET', '/me/friends', null, A.token)).j.friends.some((f) => f.id === C.me.id), 'nhưng vẫn là bạn bè trên máy chủ')
} catch (e) { fail++; console.log('FAIL exception', e.message) }
console.log(`${pass} pass, ${fail} fail`)
for (const e of [...new Set(errs)].slice(0, 15)) console.log('  ' + e)
await br.close()
process.exit(fail ? 1 : 0)
