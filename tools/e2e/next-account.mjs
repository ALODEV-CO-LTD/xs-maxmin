// QA màn Tài khoản: hồ sơ, đổi mật khẩu, mật khẩu lớp hai, mã ID, mã khôi phục, thiết bị & riêng tư, gói & thanh toán, thống kê.
//   SITE=http://127.0.0.1:8622 PPT=... node tools/e2e/next-account.mjs
import { createRequire } from 'node:module'
const puppeteer = createRequire((process.env.PPT || process.cwd()) + '/')('puppeteer-core')
const SITE = process.env.SITE || 'http://127.0.0.1:8622', API = `http://127.0.0.1:${process.env.BE || 8621}/api`
const FAKE_IP = `10.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}.${1 + Math.floor(Math.random() * 250)}`
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const call = async (m, p, b, t) => { const r = await fetch(API + p, { method: m, headers: { 'content-type': 'application/json', 'x-forwarded-for': FAKE_IP, ...(t ? { authorization: 'Bearer ' + t } : {}) }, body: b ? JSON.stringify(b) : undefined }); return { s: r.status, j: await r.json().catch(() => null) } }
let pass = 0, fail = 0
const ok = (c, n, e = '') => { c ? pass++ : fail++; console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : ' -> ' + e)) }
const username = 'ac' + Date.now().toString(36).slice(-5), PW = 'Pass-1234', PW2 = 'Second-1234', NEW = 'NewPass-5678'
const reg = (await call('POST', '/auth/register', { name: 'Khach AC', username, password: PW, secondPassword: PW2 })).j
const token = (await call('POST', '/auth/step2', { pendingToken: reg.pendingToken, password: PW2 })).j.token
const br = await puppeteer.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true, args: ['--no-sandbox'] })
const errs = []
const p = await br.newPage(); await p.setViewport({ width: 1200, height: 900 })
p.on('pageerror', (e) => errs.push('pageerror ' + e.message.slice(0, 150)))
p.on('dialog', async (d) => { errs.push('(dialog ' + d.type() + ': ' + d.message().slice(0, 60) + ')'); await d.accept() })
p.on('response', (x) => { if (x.url().includes('/api/') && x.status() >= 400 && ![401, 404].includes(x.status())) errs.push(`HTTP ${x.status()} ${x.url().replace(SITE, '').slice(0, 70)}`) })
const text = () => p.evaluate(() => document.body.innerText)
const waitText = async (s, ms = 6000) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { if ((await text()).includes(s)) return true; await sleep(200) } return false }
async function clickText(label, sel = 'button') { const h = await p.evaluateHandle((l, s) => [...document.querySelectorAll(s)].find((e) => e.offsetParent && e.innerText.trim() === l) || null, label, sel); const el = h.asElement(); if (!el) throw new Error('no element ' + label); await el.click() }
const fillDialog = async (vals, sel = '[role=dialog] input[type=password]') => { const ins = await p.$$(sel); for (let i = 0; i < vals.length; i++) await ins[i].type(vals[i]) }
try {
  await p.goto(SITE + '/login', { waitUntil: 'networkidle0' })
  await p.evaluate((t) => { localStorage.setItem('xoso_token', t); localStorage.setItem('xoso_role', 'user') }, token)
  await p.goto(SITE + '/account', { waitUntil: 'networkidle0' }); await sleep(1200)
  const tabs = await p.$$eval('[role=tab]', (e) => e.map((x) => x.innerText.trim())); console.log('  tabs:', tabs.join(' | '))
  ok(['Thống kê', 'Hồ sơ'].every((t) => tabs.includes(t)), 'có các tab Thống kê, Hồ sơ')
  // ---- Hồ sơ ----
  await p.click('#acct-tab-profile'); await sleep(500)
  ok((await text()).includes('Khach AC') && (await text()).includes(username), 'hiện tên và tên đăng nhập')
  await clickText('Sửa'); await p.$eval('#profile-name', (e) => e.select()); await p.type('#profile-name', 'Khach Doi Ten')
  await clickText('Lưu'); await sleep(1200)
  ok((await call('GET', '/me', null, token)).j.name === 'Khach Doi Ten', 'sửa tên -> lưu lên máy chủ', JSON.stringify((await call('GET', '/me', null, token)).j.name))
  ok((await text()).includes('Khach Doi Ten'), 'tên mới hiện trên màn hình')
  // ---- Mã ID ----
  const m0 = (await call('GET', '/me/customer-codes', null, token)).j.codes.length
  await clickText('+ Tạo mã mới'); await sleep(1000)
  ok((await call('GET', '/me/customer-codes', null, token)).j.codes.length === m0 + 1, 'tạo Mã ID mới')
  await p.type('input[aria-label="Dãy số mong muốn"]', '246810'); await p.type('input[aria-label="Nhãn"]', 'nhan thu'); await clickText('+ Tạo mã mới'); await sleep(1000)
  ok((await text()).includes('246810') && (await text()).includes('nhan thu'), 'tạo Mã ID tự chọn kèm nhãn')
  const delBtns = await p.$$('.acct-panel:not([hidden]) button'); 
  await clickText('Xoá'); await sleep(400); await clickText('Xoá', '[role=alertdialog] button'); await sleep(1000)
  ok((await call('GET', '/me/customer-codes', null, token)).j.codes.length === m0 + 1, 'xoá một Mã ID')
  // ---- Mật khẩu lớp hai ----
  await clickText('Đổi mật khẩu lớp hai'); await sleep(300)
  await fillDialog([PW, 'Second-9999']); await clickText('Lưu', '[role=dialog] button').catch(async () => { await p.keyboard.press('Enter') }); await sleep(1200)
  ok(await waitText('Đã cập nhật mật khẩu lớp hai'), 'đổi mật khẩu lớp hai')
  await p.keyboard.press('Escape'); await sleep(300)
  // ---- Đổi mật khẩu đăng nhập ----
  await clickText('Đổi mật khẩu'); await sleep(300)
  await fillDialog([PW, NEW, NEW]); await p.keyboard.press('Enter'); await sleep(1500)
  console.log('  (sau đổi mk):', (await text()).split('\n').filter((l) => /mật khẩu|Đã/i.test(l)).slice(0, 4).join(' | '))
  const lg = await call('POST', '/auth/login', { username, password: NEW })
  ok(lg.s === 200 && lg.j.pendingToken, 'đăng nhập bằng mật khẩu mới thành công', JSON.stringify(lg.j).slice(0, 100))
  ok((await call('POST', '/auth/login', { username, password: PW })).s === 401, 'mật khẩu cũ không còn dùng được')
  // phiên hiện tại còn sống?
  const meNow = await call('GET', '/me', null, token); console.log('  phiên cũ sau đổi mk: HTTP', meNow.s)
  await p.keyboard.press('Escape')
  // ---- Thiết bị & riêng tư ----
  await p.goto(SITE + '/account?tab=devices', { waitUntil: 'networkidle0' }); await sleep(1500)
  const tdev = await text(); console.log('  devices:', tdev.split('\n').filter((l) => l.trim()).slice(6, 24).join(' / ').slice(0, 320))
  ok(/Mã khôi phục/.test(tdev) && /riêng tư/i.test(tdev), 'tab Thiết bị có Mã khôi phục + Cài đặt quyền riêng tư')
  // ---- Mã khôi phục: tạo trên giao diện rồi DÙNG THẬT ----
  await p.type('#rc-password', NEW); await clickText('Tạo mã khôi phục').catch(() => clickText('Đổi mã khôi phục')); await sleep(1500)
  const code = await p.$eval('.rc-code', (e) => e.innerText.trim()).catch(() => '')
  ok(/^[A-Z0-9]{4}(-[A-Z0-9]{4}){3}$/.test(code), 'hiện mã khôi phục đúng dạng XXXX-XXXX-XXXX-XXXX')
  await p.click('.rc-code ~ * input[type=checkbox], input[type=checkbox]').catch(() => {}); await clickText('Xong').catch(() => {}); await sleep(500)
  const rec = await call('POST', '/auth/recover', { username, recoveryCode: code, newPassword: 'Recovered-9012' })
  ok(rec.s === 200, 'dùng mã vừa tạo để đặt lại mật khẩu thành công', rec.s + ' ' + JSON.stringify(rec.j).slice(0, 80))
  // sau recover mọi phiên cũ bị thu hồi -> đăng nhập lại để tiếp tục
  const l1 = (await call('POST', '/auth/login', { username, password: 'Recovered-9012' })).j
  const token2 = (await call('POST', '/auth/step2', { pendingToken: l1.pendingToken, password: 'Second-9999' })).j?.token
  ok(!!token2, 'đăng nhập lại với mật khẩu khôi phục + mật khẩu lớp hai mới')
  await p.evaluate((t) => localStorage.setItem('xoso_token', t), token2)
  // ---- Riêng tư ----
  await p.goto(SITE + '/account?tab=devices', { waitUntil: 'networkidle0' }); await sleep(1200)
  await p.select('#priv-idle', await p.$eval('#priv-idle', (e) => [...e.options].pop().value)); await sleep(300)
  const stored = await p.evaluate(() => JSON.stringify(Object.fromEntries(Object.entries(localStorage).filter(([k]) => /priv/i.test(k)))))
  console.log('  priv storage:', stored.slice(0, 120)); ok(stored.length > 5, 'cài đặt riêng tư được lưu trong trình duyệt')
  await p.reload({ waitUntil: 'networkidle0' }); await sleep(1000)
  ok(await p.$eval('#priv-idle', (e) => e.selectedIndex === e.options.length - 1), 'giữ cài đặt riêng tư sau khi tải lại')
  // ---- Thiết bị: thêm phiên thứ hai rồi đăng xuất thiết bị khác ----
  const l2 = (await call('POST', '/auth/login', { username, password: 'Recovered-9012' })).j; const tok3 = (await call('POST', '/auth/step2', { pendingToken: l2.pendingToken, password: 'Second-9999' })).j.token
  await p.reload({ waitUntil: 'networkidle0' }); await sleep(1200)
  ok((await text()).includes('Đăng xuất thiết bị khác'), 'có nút Đăng xuất thiết bị khác khi >1 phiên')
  await clickText('Đăng xuất thiết bị khác'); await sleep(400)
  if (await p.$('[role=alertdialog]')) await clickText('Đăng xuất', '[role=alertdialog] button').catch(() => {}); await sleep(1200)
  ok((await call('GET', '/me', null, tok3)).s === 401, 'phiên khác bị đăng xuất'); ok((await call('GET', '/me', null, token2)).s === 200, 'phiên hiện tại vẫn sống')
  // ---- Gói & thanh toán ----
  await p.goto(SITE + '/account?tab=packages', { waitUntil: 'networkidle0' }); await sleep(1500)
  const pk = await text(); console.log('  packages:', pk.split('\n').filter((l) => l.trim()).slice(10, 30).join(' / ').slice(0, 400))
  ok(/Gói|gói/.test(pk) && !/Không tải được/.test(pk), 'tab Gói & Thanh toán hiển thị danh sách gói')
  await p.screenshot({ path: '/private/tmp/claude-501/shots/acct-packages.png' })
  // ---- Đăng ký gói -> admin duyệt -> khách thấy gói mới ----
  const a1 = (await call('POST', '/auth/login', { username: '1', password: 'Next-admin-Pass-1' })).j
  const AT = a1.token || (await call('POST', '/auth/step2', { pendingToken: a1.pendingToken, password: 'Next-admin-Pass-1' })).j.token
  const before = (await call('GET', '/me', null, token2)).j.packageExpiresAt || (await call('GET', '/me', null, token2)).j.package?.expiresAt
  await clickText('Đăng ký'); await sleep(400); await clickText('Đăng ký', '[role=alertdialog] button'); await sleep(1500)
  ok(await waitText('Đã tạo yêu cầu'), 'đăng ký gói tạo yêu cầu thanh toán')
  const reqs = (await call('GET', '/me/payment-requests', null, token2)).j; const rq = (reqs.requests || reqs)[0]
  ok(!!rq && rq.status === 'pending', 'yêu cầu ở trạng thái chờ', JSON.stringify(rq).slice(0, 120))
  const ap = await call('POST', `/admin/payment-requests/${rq.id}/approve`, {}, AT); ok(ap.s === 200, 'admin duyệt', ap.s + JSON.stringify(ap.j).slice(0, 100))
  await sleep(500); await p.reload({ waitUntil: 'networkidle0' }); await sleep(1500)
  const after = (await call('GET', '/me', null, token2)).j.packageExpiresAt || (await call('GET', '/me', null, token2)).j.package?.expiresAt
  ok(after !== before, 'hạn gói đổi sau khi duyệt'); ok(!/chờ/i.test(await text()) || /Đã duyệt|duyệt/i.test(await text()), 'màn hình phản ánh đã duyệt')
} catch (e) { fail++; console.log('FAIL exception', e.message) }
console.log(`${pass} pass, ${fail} fail`); for (const e of [...new Set(errs)].slice(0, 12)) console.log('  ' + e)
await br.close(); process.exit(fail ? 1 : 0)
