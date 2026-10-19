// QA cuộc gọi thoại (CallOverlay + callStore) giữa hai trình duyệt, micro giả của Chrome.
//   SITE_A=http://127.0.0.1:8622 SITE_B=http://127.0.0.1:8622 PPT=... node tools/e2e/next-call.mjs
import { createRequire } from 'node:module'
const puppeteer = createRequire((process.env.PPT || process.cwd()) + '/')('puppeteer-core')
const SA = process.env.SITE_A || 'http://127.0.0.1:8622', SB = process.env.SITE_B || SA, API = `http://127.0.0.1:${process.env.BE || 8621}/api`
const FAKE_IP = `10.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}.${1 + Math.floor(Math.random() * 250)}`
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const call = async (m, p, b, t) => { const r = await fetch(API + p, { method: m, headers: { 'content-type': 'application/json', 'x-forwarded-for': FAKE_IP, ...(t ? { authorization: 'Bearer ' + t } : {}) }, body: b ? JSON.stringify(b) : undefined }); return { s: r.status, j: await r.json().catch(() => null) } }
let pass = 0, fail = 0
const ok = (c, n, e = '') => { c ? pass++ : fail++; console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : ' -> ' + e)) }
async function mk(tag) { const username = tag + Date.now().toString(36).slice(-5); const r = (await call('POST', '/auth/register', { name: 'User ' + tag, username, password: 'Pass-1234', secondPassword: 'Second-1234' })).j; const token = (await call('POST', '/auth/step2', { pendingToken: r.pendingToken, password: 'Second-1234' })).j.token; return { token, me: (await call('GET', '/me', null, token)).j, name: 'User ' + tag } }
const br = await puppeteer.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true, args: ['--no-sandbox', '--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream', '--autoplay-policy=no-user-gesture-required'] })
const errs = []
async function page(site, u, path) {
  const ctx = await br.createBrowserContext(); const p = await ctx.newPage(); await p.setViewport({ width: 1200, height: 850 })
  p.on('pageerror', (e) => errs.push(u.name + ' pageerror ' + e.message.slice(0, 150)))
  p.on('console', (m) => { if (m.type() === 'error' && !/vibrate|401/.test(m.text())) errs.push(u.name + ' console ' + m.text().slice(0, 150)) })
  await p.goto(site + '/login', { waitUntil: 'networkidle0' })
  await p.evaluate((t) => { localStorage.setItem('xoso_token', t); localStorage.setItem('xoso_role', 'user') }, u.token)
  await p.goto(site + path, { waitUntil: 'networkidle0' }); await sleep(1500); p.ctx = ctx; return p
}
const text = (p) => p.evaluate(() => document.body.innerText)
async function waitText(p, s, ms = 10000) { const t0 = Date.now(); while (Date.now() - t0 < ms) { if ((await text(p)).includes(s)) return true; await sleep(200) } return false }
async function gone(p, s, ms = 6000) { const t0 = Date.now(); while (Date.now() - t0 < ms) { if (!(await text(p)).includes(s)) return true; await sleep(200) } return false }
async function clickText(p, label, sel = 'button') { const h = await p.evaluateHandle((l, s) => [...document.querySelectorAll(s)].find((e) => e.innerText.trim().includes(l)) || null, label, sel); const el = h.asElement(); if (!el) throw new Error('no element ' + label); await el.click() }
try {
  const A = await mk('ca'), B = await mk('cb')
  const r = await call('POST', '/me/friends', { userId: B.me.id }, A.token)
  const req = (await call('GET', '/me/friend-requests', null, B.token)).j.incoming.find((q) => q.fromId === A.me.id)
  await call('POST', `/me/friend-requests/${req.id}/accept`, {}, B.token)
  const pa = await page(SA, A, '/friends'), pb = await page(SB, B, '/account')
  await clickText(pa, B.name, '.friend-item'); await sleep(800)
  const callBtn = '.call-buttons button'
  ok(!!(await pa.$(callBtn)), 'có nút Gọi thoại trong hội thoại')
  // 1. gọi - nghe máy - tắt mic - kết thúc
  await pa.click(callBtn)
  ok(await waitText(pa, 'Đang gọi...') || await waitText(pa, 'Đang đổ chuông'), 'A thấy "Đang gọi/đổ chuông"')
  ok(await waitText(pb, 'Cuộc gọi thoại đến...'), 'B (đang ở trang khác) thấy cuộc gọi đến')
  await clickText(pb, 'Nghe máy'); 
  const t0 = Date.now(); let conn = false; while (Date.now() - t0 < 15000) { if (/\d\d:\d\d/.test(await pa.$eval('.call-sub', (e) => e.innerText).catch(() => '')) && /\d\d:\d\d/.test(await pb.$eval('.call-sub', (e) => e.innerText).catch(() => ''))) { conn = true; break } await sleep(300) }
  ok(conn, 'cả hai vào cuộc gọi, đồng hồ chạy (WebRTC nối được)')
  await sleep(2500)
  const t1 = await pa.$eval('.call-sub', (e) => e.innerText); ok(t1 !== '00:00', 'đồng hồ tăng', t1)
  const rtc = await pa.evaluate(() => (window.__pc ? window.__pc.connectionState : 'n/a')); console.log('  (pc state:', rtc, ')')
  await clickText(pa, 'Tắt mic', 'button.btn-ghost').catch(() => console.log('  (không tìm nút Tắt mic theo chữ)'))
  await pa.screenshot({ path: '/private/tmp/claude-501/shots/call-a.png' })
  await clickText(pa, 'Kết thúc'); 
  ok(await gone(pa, 'Kết thúc') && await gone(pb, 'Kết thúc'), 'A kết thúc -> cả hai về trạng thái rảnh')
  // 2. B từ chối
  await sleep(800); await pa.click(callBtn); ok(await waitText(pb, 'Cuộc gọi thoại đến...'), 'cuộc gọi thứ hai tới B')
  await clickText(pb, 'Từ chối'); await sleep(1500)
  ok(await gone(pb, 'Cuộc gọi thoại đến...'), 'B từ chối -> overlay đóng ở B')
  ok(await gone(pa, 'Đang gọi...') || (await text(pa)).includes('Đóng'), 'A thấy kết thúc/đóng', (await text(pa)).slice(-120))
  if ((await text(pa)).includes('Đóng')) await clickText(pa, 'Đóng')
  // 3. A huỷ trước khi B nghe -> B nhỡ
  await sleep(800); await pa.click(callBtn); await waitText(pb, 'Cuộc gọi thoại đến...'); await clickText(pa, 'Huỷ'); await sleep(1500)
  ok(await gone(pb, 'Cuộc gọi thoại đến...'), 'A huỷ -> overlay ở B biến mất')

  await pb.goto(SB + '/friends', { waitUntil: 'networkidle0' }); await sleep(1500)
  ok(await pb.evaluate(() => !!document.querySelector('.missed-badge')), 'B thấy huy hiệu cuộc gọi nhỡ trong danh sách')
  await clickText(pb, A.name, '.friend-item'); await sleep(1200)
  const t = await text(pb); ok(/nhỡ/i.test(t), 'nhật ký cuộc gọi có dòng nhỡ'); ok(/từ chối|Từ chối/i.test(t), 'nhật ký có dòng từ chối'); ok(/\d+:\d\d|phút|giây/.test(t), 'nhật ký có thời lượng cuộc gọi đã nghe')
  console.log('  log:', t.split('\n').filter((l) => /gọi|nhỡ|chối/i.test(l)).join(' | ').slice(0, 300))
  // 4. gọi khi B offline
  await pb.close(); await sleep(2000); await pa.click(callBtn).catch(() => {}); await sleep(2500)
  const ta = await text(pa); ok(/offline|không|lỗi|Đóng/i.test(ta), 'gọi người offline -> báo lỗi/không gọi được', ta.slice(-150))
} catch (e) { fail++; console.log('FAIL exception', e.message) }
console.log(`${pass} pass, ${fail} fail`); for (const e of [...new Set(errs)].slice(0, 10)) console.log('  ' + e)
await br.close(); process.exit(fail ? 1 : 0)
