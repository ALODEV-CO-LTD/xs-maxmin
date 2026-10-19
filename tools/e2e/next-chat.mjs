// QA luồng tin nhắn / bạn bè bằng HAI trình duyệt (hai người dùng) trên backend thử.
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
  const A = await mkUser('qa'), B = await mkUser('qb'), C = await mkUser('qc')
  console.log(`A=${SA} B=${SB}`)
  const pa = await openPage(SA, A), pb = await openPage(SB, B), pc = await openPage(SB, C)
  // ---- kết bạn: gửi lời mời, bên kia chấp nhận ----
  await clickText(pa, 'Tìm kiếm', 'button'); await pa.type('#searchQuery', B.username);
  ok(await waitText(pa, 'Kết bạn'), 'tìm thấy B trong "Người mới"')
  await clickText(pa, 'Kết bạn', '.search-item button')
  ok(await waitText(pa, 'Đã gửi lời mời kết bạn'), 'A gửi lời mời -> thông báo chờ chấp nhận')
  ok((await call('GET', '/me/friends', null, A.token)).j.friends.length === 0, 'chưa là bạn khi chưa chấp nhận')
  await pb.reload({ waitUntil: 'networkidle0' }); await sleep(1500)
  ok(/Lời mời kết bạn/.test(await text(pb)) && (await text(pb)).includes(A.name), 'B thấy lời mời của A')
  await clickText(pb, 'Chấp nhận', 'button'); await sleep(1500)
  ok((await call('GET', '/me/friends', null, B.token)).j.friends.some((f) => f.id === A.me.id), 'B chấp nhận -> thành bạn')
  // C cũng kết bạn với A và B (qua API, để thử nhóm)
  for (const [x, y] of [[C, A], [C, B]]) {
    const r = await call('POST', '/me/friends', { userId: y.me.id }, x.token)
    const reqs = (await call('GET', '/me/friend-requests', null, y.token)).j
    const req = reqs.incoming.find((q) => q.fromId === x.me.id)
    if (req) await call('POST', `/me/friend-requests/${req.id}/accept`, {}, y.token)
  }
  await sleep(500)
  ok((await call('GET', '/me/friends', null, C.token)).j.friends.length === 2, 'C là bạn của A và B (API)')
  for (const p of [pa, pb, pc]) { await p.reload({ waitUntil: 'networkidle0' }); await sleep(1500) }

  // ---- mở hội thoại, nhắn tin hai chiều ----
  console.log((await text(pa)).replace(/\s+/g,' ').slice(0,300)); await clickText(pa, B.name, '.friend-item', false); await sleep(800)
  await clickText(pb, A.name, '.friend-item', false); await sleep(800)
  await send(pa, 'xin chao tu A')
  await sleep(2000); console.log('B:', (await text(pb)).replace(/\s+/g,' ').slice(60,500)); ok(await waitText(pb, 'xin chao tu A'), 'B (đang mở hội thoại) nhận tin của A, giải mã được')
  ok(await waitText(pa, 'xin chao tu A') && !(await text(pa)).includes('chờ xác nhận'), 'A thấy tin đã được xác nhận')
  await send(pb, 'tra loi tu B')
  ok(await waitText(pa, 'tra loi tu B'), 'A nhận tin của B')
  // ---- ghim, trả lời, chuyển tiếp ----
  await ctxMenu(pa, 'tra loi tu B', 'Ghim'); ok(await waitText(pa, '📌'), 'Ghim hiện thanh ghim')
  await ctxMenu(pa, 'tra loi tu B', 'Trả lời'); ok(await waitText(pa, '↪ Trả lời'), 'Trả lời hiện thanh trả lời')
  await send(pa, 'rep1'); await sleep(800)
  ok((await bubbles(pa)).some((b) => b.includes('rep1') && b.includes('tra loi tu B')), 'tin trả lời có trích dẫn (A)')
  ok(await waitText(pb, 'rep1') && (await bubbles(pb)).some((b) => b.includes('rep1') && b.includes('tra loi tu B')), 'B thấy trích dẫn')
  await ctxMenu(pa, 'xin chao tu A', 'Chuyển tiếp'); await sleep(400)
  await clickText(pa, 'User qc', '[aria-label="Chuyển tiếp"] button')
  await sleep(1200)
  ok((await text(pa)).includes('User qc') && (await bubbles(pa)).some((b) => b === 'xin chao tu A'), 'Chuyển tiếp -> A mở hội thoại với C, tin xuất hiện')
  await clickText(pc, A.name, '.friend-item', false); await sleep(800)
  ok((await bubbles(pc)).some((b) => b === 'xin chao tu A'), 'C nhận tin chuyển tiếp (giải mã được)')
  // ---- xoá / chọn ----
  await clickText(pa, B.name, '.friend-item', false); await sleep(600)
  await ctxMenu(pa, 'rep1', 'Xoá'); await sleep(400)
  ok((await text(pa)).includes('khỏi máy này'), 'Xoá hiện hộp xác nhận')
  await clickText(pa, 'Xoá', '[role=alertdialog] button'); await sleep(800)
  ok(!(await bubbles(pa)).some((b) => b.includes('rep1')), 'tin đã xoá biến mất ở A')
  ok((await bubbles(pb)).some((b) => b.includes('rep1')), 'B vẫn giữ bản của mình')
  await ctxMenu(pa, 'xin chao tu A', 'Chọn'); await sleep(300)
  ok(await waitText(pa, 'Đã chọn 1'), 'Chọn -> thanh chọn có "Đã chọn 1"')
  await clickText(pa, 'Chọn tất cả', 'button'); await sleep(200)
  ok(await waitText(pa, 'Đã chọn 2'), 'Chọn tất cả')
  await clickText(pa, 'Hủy', '.selbar button'); await sleep(200)
  ok(await gone(pa, 'Đã chọn'), 'Hủy chọn')
  // ---- ghim: bỏ ghim ----
  await clickText(pa, '✕', '.pin-bar button').catch(() => {}); ok(await gone(pa, '📌'), 'Bỏ ghim (bản Vue lỗi DataCloneError khi ghim -> thanh ghim không hiện)')
  // ---- ảnh ----
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64')
  const fs = await import('node:fs'); const imgPath = '/private/tmp/claude-501/qa.png'; fs.writeFileSync(imgPath, png)
  await (await pa.$('.attach-input')).uploadFile(imgPath); await sleep(500)
  await clickText(pa, 'Gửi', '.send-row button[type=submit]'); await sleep(1500)
  const imgs = (p) => p.evaluate(() => document.querySelectorAll('.msg-bubble img').length)
  ok((await imgs(pa)) >= 1, 'A thấy ảnh đã gửi'); ok(await (async () => { for (let i = 0; i < 20; i++) { if ((await imgs(pb)) >= 1) return true; await sleep(300) } return false })(), 'B nhận ảnh (giải mã được)')
  // ---- offline: B đóng, A gửi ----
  await pb.close(); await sleep(2000) // cùng ngữ cảnh (giữ IndexedDB/khoá), chỉ ngắt WebSocket
  await send(pa, 'luc B offline'); await sleep(2500); console.log('A-off:', (await text(pa)).replace(/\s+/g,' ').slice(-260))
  ok((await text(pa)).includes('Bạn bè đang offline'), 'bạn offline -> báo "Bạn bè đang offline"')
  ok((await text(pa)).includes('Gửi lại'), 'tin lỗi có nút Gửi lại')
  // ---- B mở lại, gửi lại ----
  const pb2 = await pb.browserContext().newPage(); await pb2.setViewport({ width: 1200, height: 850 }); pb2.on('pageerror', (e) => errs.push('B pageerror: ' + e.message.slice(0, 160))); await pb2.goto(SB + '/friends', { waitUntil: 'networkidle0' }); await sleep(1200); await clickText(pb2, A.name, '.friend-item', false); await sleep(1000)
  await clickText(pa, 'Gửi lại', 'button'); ok(await waitText(pb2, 'luc B offline'), 'B online lại -> Gửi lại thành công, B nhận được')
  // ---- nhóm: A tạo nhóm với B và C ----
  await clickText(pa, 'Thêm', 'button'); await clickText(pa, 'Nhóm mới', 'button'); await sleep(300)
  await pa.type('[aria-label="Tạo nhóm"] input[type=text]', 'Nhom QA')
  for (const nm of ['User qb', 'User qc']) await clickText(pa, nm, '[aria-label="Tạo nhóm"] label', false)
  await clickText(pa, 'Tạo nhóm', '[aria-label="Tạo nhóm"] button'); await sleep(1500)
  ok((await text(pa)).includes('Nhom QA'), 'A tạo nhóm')
  await pc.reload({ waitUntil: 'networkidle0' }); await sleep(1500)
  ok((await text(pc)).includes('Nhom QA'), 'C thấy nhóm sau khi được thêm')
  await clickText(pc, 'Nhom QA', '.friend-item', false); await sleep(600)
  await send(pa, 'tin nhom 1')
  ok(await waitText(pc, 'tin nhom 1'), 'C nhận tin nhóm của A')
  await send(pc, 'C tra loi nhom')
  ok(await waitText(pa, 'C tra loi nhom'), 'A nhận tin nhóm của C')
  ok((await bubbles(pa)).some((b) => b.includes('User qc') && b.includes('C tra loi nhom')), 'tin nhóm hiện tên người gửi')
  // ---- toast + huy hiệu khi đang ở trang khác ----
  await pa.goto(SA + '/account', { waitUntil: 'networkidle0' }); await sleep(1500)
  await clickText(pb2, A.name, '.friend-item', false); await send(pb2, 'ping toast'); await sleep(1500)
  ok(await pa.evaluate(() => !!document.querySelector('.msg-toast')), 'A ở trang khác -> hiện toast tin mới')
  ok(await pa.evaluate(() => /^[1-9]/.test(document.querySelector('.nav-badge')?.innerText || '')) && await pa.evaluate(() => /^[1-9]/.test(document.querySelector('.hdr-badge')?.innerText || '')), 'huy hiệu chưa đọc ở menu Bạn bè và chuông')
  await pa.goto(SA + '/friends', { waitUntil: 'networkidle0' }); await sleep(1500)
  ok(await pa.evaluate(() => /^[1-9]/.test(document.querySelector('.friend-item .unread-badge')?.innerText || '')), 'sau tải lại danh sách vẫn nhớ số chưa đọc')
  await clickText(pa, 'User qb', '.friend-item', false); await sleep(1000)
  ok(await pa.evaluate(() => !document.querySelector('.nav-badge')), 'mở hội thoại -> hết huy hiệu')
  await pa.screenshot({ path: SHOTS + '/chat-a.png' })
} catch (e) { fail++; console.log('FAIL exception', e.message) }
console.log(`${pass} pass, ${fail} fail`)
for (const e of [...new Set(errs)].slice(0, 15)) console.log('  ' + e)
await br.close()
process.exit(fail ? 1 : 0)
