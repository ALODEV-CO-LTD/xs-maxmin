// QA phản hồi Admin (SupportChat) trên bản Next/Vue: khách gửi chữ + ảnh, admin thấy & trả lời (cả bằng giao diện), huy hiệu, popover.
//   SITE=http://127.0.0.1:8622 PPT=... node tools/e2e/next-support.mjs
import { createRequire } from 'node:module'
import fs from 'node:fs'
const puppeteer = createRequire((process.env.PPT || process.cwd()) + '/')('puppeteer-core')
const SITE = process.env.SITE || 'http://127.0.0.1:8622', API = `http://127.0.0.1:${process.env.BE || 8621}/api`
const FAKE_IP = `10.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}.${1 + Math.floor(Math.random() * 250)}`
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const call = async (m, p, b, t) => { const r = await fetch(API + p, { method: m, headers: { 'content-type': 'application/json', 'x-forwarded-for': FAKE_IP, ...(t ? { authorization: 'Bearer ' + t } : {}) }, body: b ? JSON.stringify(b) : undefined }); return { s: r.status, j: await r.json().catch(() => null) } }
let pass = 0, fail = 0
const ok = (c, n, e = '') => { c ? pass++ : fail++; console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : ' -> ' + e)) }
const a1 = (await call('POST', '/auth/login', { username: '1', password: process.env.ADMIN_PASS || 'Next-admin-Pass-1' })).j
const AT = a1.token || (await call('POST', '/auth/step2', { pendingToken: a1.pendingToken, password: process.env.ADMIN_PASS || 'Next-admin-Pass-1' })).j.token
const username = 'sp' + Date.now().toString(36).slice(-5)
const reg = (await call('POST', '/auth/register', { name: 'Khach SP', username, password: 'Pass-1234', secondPassword: 'Second-1234' })).j
const UT = (await call('POST', '/auth/step2', { pendingToken: reg.pendingToken, password: 'Second-1234' })).j.token
const uid = (await call('GET', '/me', null, UT)).j.id
const br = await puppeteer.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true, args: ['--no-sandbox'] })
const errs = []
async function page(token, role, path) {
  const ctx = await br.createBrowserContext(); const p = await ctx.newPage(); await p.setViewport({ width: 1280, height: 800 })
  p.on('pageerror', (e) => errs.push('pageerror ' + e.message.slice(0, 150)))
  p.on('response', (x) => { if (x.url().includes('/api/') && x.status() >= 400 && ![401, 404].includes(x.status())) errs.push(`HTTP ${x.status()} ${x.url().replace(SITE, '')}`) })
  await p.goto(SITE + '/login', { waitUntil: 'networkidle0' })
  await p.evaluate((t, r) => { localStorage.setItem('xoso_token', t); localStorage.setItem('xoso_role', r) }, token, role)
  await p.goto(SITE + path, { waitUntil: 'networkidle0' }); await sleep(1200); return p
}
try {
  const p = await page(UT, 'user', '/entries')
  ok(!!(await p.$('.support-btn')), 'nút Phản hồi ở thanh trên')
  await call('POST', '/admin/messages/' + uid, { content: 'Chào bạn, Admin đây' }, AT)
  let badge = null; for (let i = 0; i < 16 && badge !== '1'; i++) { await sleep(1000); badge = await p.$eval('.support-badge', (e) => e.innerText.trim()).catch(() => null) }
  ok(badge === '1', 'huy hiệu đỏ 1 trên nút', badge)
  await p.click('.support-btn'); await sleep(1200)
  ok(!!(await p.$('.support-pop')), 'popover mở'); ok(!(await p.$('.support-badge')), 'mở -> mất huy hiệu')
  await p.type('.sp-form input', 'Cảm ơn Admin'); await p.keyboard.press('Enter'); await sleep(1000)
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64'); fs.writeFileSync('/private/tmp/claude-501/sp.png', png)
  await (await p.$('.sp-foot .attach-input')).uploadFile('/private/tmp/claude-501/sp.png'); await sleep(400)
  await p.type('.sp-form input', 'kèm ảnh'); await p.keyboard.press('Enter'); await sleep(1500)
  ok((await p.$$eval('.sp-text', (e) => e.map((x) => x.innerText))).includes('Cảm ơn Admin'), 'khách gửi chữ, hiện trong popover')
  ok((await p.$$('.sp-bubble img, .sp-bubble canvas')).length >= 1, 'ảnh đính kèm hiện trong popover')
  const msgs = (await call('GET', '/admin/messages/' + uid, null, AT)).j
  const list = msgs.messages || msgs
  ok(list.some((m) => m.content === 'Cảm ơn Admin' && m.sender === 'user'), 'admin (API) nhận chữ của khách')
  ok(list.some((m) => m.attachment || m.hasAttachment || m.attachmentName || m.attachment_name), 'admin (API) nhận ảnh', JSON.stringify(list[list.length - 1]).slice(0, 200))
  // admin trả lời qua giao diện
  const ap = await page(AT, 'admin', '/admin/messages?user=' + uid)
  ok((await ap.evaluate(() => document.body.innerText)).includes('Cảm ơn Admin'), 'giao diện admin thấy tin khách')
  await ap.type('.reply-row input[type=text]', 'Admin trả lời qua UI'); await ap.keyboard.press('Enter'); await sleep(1200)
  ok((await ap.evaluate(() => document.body.innerText)).includes('Admin trả lời qua UI'), 'admin gửi trả lời, hiện ở khung admin')
  let top = null; for (let i = 0; i < 14; i++) { await sleep(1000); top = await p.$$eval('.sp-text', (e) => e.map((x) => x.innerText)); if (top.includes('Admin trả lời qua UI')) break }
  ok(top.includes('Admin trả lời qua UI'), 'khách thấy trả lời của admin trong popover (đang mở)')
  await p.keyboard.press('Escape'); await sleep(200); ok(!(await p.$('.support-pop')), 'Esc đóng popover')
  await p.click('.support-btn'); await sleep(500); await p.mouse.click(300, 600); await sleep(200); ok(!(await p.$('.support-pop')), 'bấm ngoài đóng popover')
  await p.setViewport({ width: 390, height: 844 }); await sleep(300); await p.click('.support-btn'); await sleep(600)
  ok(await p.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), 'điện thoại: không tràn ngang')
} catch (e) { fail++; console.log('FAIL exception', e.message) }
console.log(`${pass} pass, ${fail} fail`); for (const e of [...new Set(errs)].slice(0, 10)) console.log('  ' + e)
await br.close(); process.exit(fail ? 1 : 0)
