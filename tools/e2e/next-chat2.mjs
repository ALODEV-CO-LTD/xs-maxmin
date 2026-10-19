// QA phần 2 (nhóm, Nhập số từ chat, quản lý bạn bè, tự xoá, lưu trữ) bằng HAI/BA trình duyệt (hai người dùng) trên backend thử.
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
  const A = await mkUser('ma'), B = await mkUser('mb'), C = await mkUser('mc')
  // kết bạn A-B, A-C, B-C qua API (UI đã kiểm ở next-chat.mjs)
  for (const [x, y] of [[A, B], [A, C], [B, C]]) {
    await call('POST', '/me/friends', { userId: y.me.id }, x.token)
    const req = (await call('GET', '/me/friend-requests', null, y.token)).j.incoming.find((q) => q.fromId === x.me.id)
    await call('POST', `/me/friend-requests/${req.id}/accept`, {}, y.token)
  }
  const pa = await openPage(SA, A), pb = await openPage(SB, B), pc = await openPage(SB, C)
  await pa.reload({ waitUntil: 'networkidle0' }); await sleep(1500) // B, C đã đăng khoá công khai khi mở trang
  // ---- nhóm: tạo, đổi tên, thêm/xoá thành viên, rời ----
  await clickText(pa, 'Thêm', 'button'); await clickText(pa, 'Nhóm mới', 'button'); await sleep(300)
  await pa.type('[aria-label="Tạo nhóm"] input[type=text]', 'Nhom Hai')
  await clickText(pa, 'User mb', '[aria-label="Tạo nhóm"] label', false)
  ok(await pa.$eval('[aria-label="Tạo nhóm"] .group-actions .btn-primary', (e) => e.disabled), 'tạo nhóm cần ít nhất 2 bạn (đang chọn 1 -> nút bị khoá)')
  await clickText(pa, 'User mc', '[aria-label="Tạo nhóm"] label', false)
  await clickText(pa, 'Tạo nhóm', '[aria-label="Tạo nhóm"] button'); await sleep(1500)
  for (const p of [pb, pc]) { await p.reload({ waitUntil: 'networkidle0' }); await sleep(1500) }
  ok((await text(pb)).includes('Nhom Hai') && (await text(pc)).includes('Nhom Hai'), 'B và C đều thấy nhóm')
  await clickText(pb, 'Nhom Hai', '.friend-item', false); await clickText(pc, 'Nhom Hai', '.friend-item', false); await sleep(500)
  await send(pa, 'hello nhom'); ok(await waitText(pb, 'hello nhom') && await waitText(pc, 'hello nhom'), 'tin nhóm tới cả B và C')
  await send(pb, 'B noi'); ok(await waitText(pc, 'B noi') && await waitText(pa, 'B noi'), 'tin của B tới A và C (B chung nhóm, kể cả C chỉ là bạn B)')
  // đổi tên (người tạo)
  await pa.click('.gear'); await sleep(300)
  await pa.$eval('[aria-label="Cài đặt nhóm"] .set-field input', (e) => e.select()); await pa.type('[aria-label="Cài đặt nhóm"] .set-field input', 'Nhom Doi Ten')
  await clickText(pa, 'Lưu', '[aria-label="Cài đặt nhóm"] button'); await sleep(1500)
  ok((await text(pa)).includes('Nhom Doi Ten'), 'người tạo đổi tên nhóm')
  await pb.reload({ waitUntil: 'networkidle0' }); await sleep(1200)
  await send(pa, 'sau doi ten'); await sleep(1500)
  await pb.reload({ waitUntil: 'networkidle0' }); await sleep(1500)
  ok((await text(pb)).includes('Nhom Doi Ten'), 'B thấy tên mới sau tin kế tiếp')
  // B không phải người tạo: không có ô đổi tên / xoá
  await clickText(pb, 'Nhom Doi Ten', '.friend-item', false); await sleep(500); await pb.click('.gear'); await sleep(300)
  ok(!(await pb.$('[aria-label="Cài đặt nhóm"] .set-field')) && !(await text(pb)).includes('Thêm thành viên'), 'thành viên thường không đổi tên/thêm người')
  await clickText(pb, 'Đóng', '[aria-label="Cài đặt nhóm"] button'); await sleep(200)
  // A xoá C khỏi nhóm
  await pa.click('.gear'); await sleep(300)
  await pa.click('[aria-label^="Xoá User mc"]'); await sleep(300); await clickText(pa, 'Xoá', '[role=alertdialog] button'); await sleep(1500)
  ok(!(await text(pa)).includes('3 thành viên') || (await text(pa)).includes('2 thành viên'), 'xoá thành viên -> còn 2')
  await pc.reload({ waitUntil: 'networkidle0' }); await sleep(1500)
  ok(!(await text(pc)).includes('Nhom Doi Ten') && !(await text(pc)).includes('Nhom Hai'), 'C bị xoá -> nhóm biến khỏi danh sách của C')
  await pa.keyboard.press('Escape'); await clickText(pa, 'Đóng', '[aria-label="Cài đặt nhóm"] button').catch(() => {})
  // B rời nhóm
  await pb.click('.gear').catch(() => {}); await sleep(300)
  if (!(await pb.$('[aria-label="Cài đặt nhóm"]'))) await pb.click('.gear'); await sleep(300)
  await clickText(pb, 'Rời nhóm', '[aria-label="Cài đặt nhóm"] button'); await sleep(300); await clickText(pb, 'Rời nhóm', '[role=alertdialog] button'); await sleep(1500)
  ok(!(await text(pb)).includes('Nhom Doi Ten'), 'B rời nhóm -> nhóm mất ở B')
  // ---- Nhập số từ chat ----
  await clickText(pa, 'User mb', '.friend-item', false); await sleep(500)
  await clickText(pb, 'User ma', '.friend-item', false); await sleep(500)
  await send(pb, 'de 12 34 x 10'); await waitText(pa, 'de 12 34 x 10')
  await call('POST', '/me/customers', { name: 'Khach X' }, A.token)
  await clickText(pa, 'Nhập số', '.calc-btn'); await sleep(300)
  await pa.click('.msg.picking .pick'); await sleep(300)
  ok(await waitText(pa, 'Nhập số (1)'), 'chọn tin -> nút "Nhập số (1)"')
  await clickText(pa, 'Nhập số (1)', '.calc-btn'); await sleep(2500)
  ok(new URL(pa.url()).pathname.startsWith('/entries'), 'chuyển sang màn Nhập số', pa.url())
  const val = await pa.evaluate(() => [...document.querySelectorAll('textarea, input[type=text]')].map((e) => e.value).join('|'))
  // (nội dung điền sẵn chỉ hiện sau khi chọn khách ở màn Nhập số - thuộc phạm vi phiên Nhập số; ở đây chỉ kiểm chuyển màn)
  // ---- kết bạn: từ chối / huỷ lời mời / mã ID ----
  const D = await mkUser('md'), E = await mkUser('me')
  await call('POST', '/me/friends', { userId: D.me.id }, A.token)
  const pd = await openPage(SB, D)
  ok((await text(pd)).includes('Lời mời kết bạn') && (await text(pd)).includes(A.name), 'D thấy lời mời của A')
  await clickText(pd, 'Từ chối', 'button'); await sleep(1200)
  ok((await call('GET', '/me/friend-requests', null, D.token)).j.incoming.length === 0 && (await call('GET', '/me/friends', null, D.token)).j.friends.length === 0, 'từ chối -> không thành bạn')
  // A gửi lại rồi huỷ
  const F = await mkUser('mf'); await call('POST', '/me/friends', { userId: F.me.id }, A.token)
  await pa.goto(SA + '/friends', { waitUntil: 'networkidle0' }); await sleep(1500)
  ok((await text(pa)).includes('Đã gửi lời mời, chờ chấp nhận'), 'A thấy lời mời đã gửi')
  await clickText(pa, 'Huỷ lời mời', 'button'); await sleep(1200)
  ok((await call('GET', '/me/friend-requests', null, A.token)).j.outgoing.length === 0, 'huỷ lời mời')
  // kết bạn qua Mã ID
  const code = (await call('POST', '/me/customer-codes', {}, E.token)).j
  const pe = await openPage(SB, E)
  await clickText(pa, 'Tìm kiếm', 'button'); await pa.type('#searchQuery', code.code); await sleep(1500)
  ok(await waitText(pa, E.name), 'tìm bằng Mã ID ra đúng người')
  await clickText(pa, 'Kết bạn', '.search-item button'); await sleep(1200)
  await pe.reload({ waitUntil: 'networkidle0' }); await sleep(1500)
  ok((await text(pe)).includes('Lời mời kết bạn') && (await text(pe)).includes(A.name), 'E nhận lời mời qua Mã ID')
  // ---- tên hiển thị riêng, xoá khỏi bạn bè ----
  await clickText(pa, 'Đóng', 'button').catch(() => {}); await pa.goto(SA + '/friends', { waitUntil: 'networkidle0' }); await sleep(1500)
  await clickText(pa, 'User mb', '.friend-item', false); await sleep(500); await pa.click('.gear'); await sleep(300)
  await pa.type('[aria-label="Cài đặt cuộc trò chuyện"] .set-field input', 'Biet Danh B'); await clickText(pa, 'Lưu', '[aria-label="Cài đặt cuộc trò chuyện"] button'); await sleep(800)
  ok((await text(pa)).includes('Biet Danh B'), 'đặt tên hiển thị riêng')
  // tự xoá
  await pa.click('.gear'); await sleep(300); await clickText(pa, 'Cài đặt tự xoá', '[aria-label="Cài đặt cuộc trò chuyện"] button'); await sleep(500)
  ok(await pa.evaluate(() => !!document.querySelector('.retention-form')), 'mở cài đặt tự xoá')
  console.log('  retention:', (await pa.$eval('.retention', (e) => e.innerText.replace(/\s+/g, ' '))).slice(0, 200))
  // xoá khỏi bạn bè
  await pa.click('.gear'); await sleep(300); await clickText(pa, 'Xoá khỏi bạn bè', '[aria-label="Cài đặt cuộc trò chuyện"] button'); await sleep(400)
  await clickText(pa, 'Xoá', '[role=alertdialog] button').catch(async () => console.log('  (dialog)', (await text(pa)).slice(-200))); await sleep(1500)
  ok(!(await call('GET', '/me/friends', null, A.token)).j.friends.some((f) => f.id === B.me.id), 'xoá khỏi bạn bè (máy chủ)')
  await pa.screenshot({ path: SHOTS + '/chat2-a.png' })
} catch (e) { fail++; console.log('FAIL exception', e.message) }
console.log(`${pass} pass, ${fail} fail`)
for (const e of [...new Set(errs)].slice(0, 15)) console.log('  ' + e)
await br.close()
process.exit(fail ? 1 : 0)
