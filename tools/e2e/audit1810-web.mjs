// Audit 18/10 - web checks (puppeteer-core). Needs: backend with XOSO_SEED_DEMO=1 XOSO_ADMIN_PASSWORD=Test-Admin-1,
// frontend/dist served by serve.mjs. node audit1810-web.mjs <webPort> <backendPort> <sqlitePath> <puppeteerDir>
import { createRequire } from 'node:module'
import { execFileSync } from 'node:child_process'
const [webPort, bePort, dbPath, pupDir] = process.argv.slice(2)
const require = createRequire(pupDir + '/')
const puppeteer = require('puppeteer-core')
const W = `http://127.0.0.1:${webPort}`, B = `http://127.0.0.1:${bePort}`
const sql = (q) => execFileSync('sqlite3', [dbPath, q]).toString().trim()
const results = []
const rec = (n, ok, ev) => { results.push(ok); console.log(`${ok ? 'PASS' : 'FAIL'}  ${n}  | ${ev}`) }
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
async function api(method, path, token, body) {
  const r = await fetch(B + '/api' + path, { method, headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) }, body: body ? JSON.stringify(body) : undefined })
  let j = null; try { j = await r.json() } catch {}
  return { s: r.status, j }
}
const loginApi = async (u, p) => (await api('POST', '/auth/login', null, { username: u, password: p })).j.token
const admin = await loginApi('1', 'Test-Admin-1')
const A = { u: '3', p: '1236' }, Bu = { u: '4', p: '1237' }
const tA = await loginApi(A.u, A.p), tB = await loginApi(Bu.u, Bu.p)
const meA = (await api('GET', '/me', tA)).j
await api('POST', '/me/customers', tB, { name: 'Khach B', phone: '0900000001' })
const browser = await puppeteer.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: 'new', args: ['--no-sandbox'] })
const page = await browser.newPage()
await page.setViewport({ width: 1280, height: 900 })
page.on('pageerror', (e) => console.log('pageerror', e.message))
const path = () => { const u = new URL(page.url()); return u.pathname + u.search }
async function uiLogin(u, p) {
  await page.goto(W + '/login', { waitUntil: 'networkidle0' })
  await page.type('#username', u); await page.type('#password', p)
  await Promise.all([page.waitForFunction(() => !location.pathname.startsWith('/login'), { timeout: 15000 }), page.click('button[type=submit]')])
  await sleep(1500)
}
const clickText = (t, last = false) => page.evaluate((t, last) => {
  const bs = [...document.querySelectorAll('button')].filter((b) => b.textContent.trim() === t && b.offsetParent)
  const b = last ? bs[bs.length - 1] : bs[0]; if (b) { b.click(); return true } return false
}, t, last)
const badges = () => page.evaluate(() => [...document.querySelectorAll('.hdr-badge,.nav-badge')].map((e) => e.textContent.trim()))

// ---- 5.1/5.2 logout then second user: no stale badge
await uiLogin(A.u, A.p)
const sent = await api('POST', `/admin/messages/${meA.id}`, admin, { content: 'xin chao A' })
let bA = []
for (let i = 0; i < 25 && !bA.length; i++) { await sleep(1000); bA = await badges() }
rec('5 A gets support unread badge', bA.length > 0, `admin msg status=${sent.s}, badges=${JSON.stringify(bA)}`)
await clickText('Đăng xuất'); await sleep(500); await clickText('Đăng xuất', true); await sleep(1500)
rec('5 explicit logout -> clean /login (no ?redirect=)', path() === '/login', `url=${path()}`)
await page.type('#username', Bu.u); await page.type('#password', Bu.p)
await Promise.all([page.waitForFunction(() => !location.pathname.startsWith('/login'), { timeout: 15000 }), page.click('button[type=submit]')])
await sleep(4000)
const bB = await badges()
const stale = await page.evaluate(() => JSON.stringify([localStorage.getItem('xoso_token') ? 1 : 0]))
rec('5 second user on same tab has no badge from A', bB.length === 0, `B badges=${JSON.stringify(bB)} (A had ${JSON.stringify(bA)})`)

// ---- 5.3 offline queue (B)
await page.goto(W + '/entries', { waitUntil: 'networkidle0' }); await sleep(1500)
await page.evaluate(() => { const b = [...document.querySelectorAll('.rail-item')].find((x) => /Khach B/.test(x.textContent)); b?.click() })
await sleep(500)
const before = sql(`select count(*) from data_entries e join users u on u.id=e.user_id where u.username='4'`)
await page.type('.mr-number', '47'); await page.type('input[aria-label^="Điểm vào dòng"]', '9')
await page.setOfflineMode(true); await sleep(500)
await clickText('Thêm số liệu'); await sleep(1500)
const pendingNotice = await page.evaluate(() => document.body.innerText.includes('Đang offline'))
const midCount = sql(`select count(*) from data_entries e join users u on u.id=e.user_id where u.username='4'`)
await page.setOfflineMode(false)
let after = before
for (let i = 0; i < 30 && after === before; i++) { await sleep(1000); after = sql(`select count(*) from data_entries e join users u on u.id=e.user_id where u.username='4'`) }
await sleep(5000)
const final = sql(`select count(*) from data_entries e join users u on u.id=e.user_id where u.username='4' and e.value='47'`)
const total = sql(`select count(*) from data_entries e join users u on u.id=e.user_id where u.username='4'`)
rec('5 offline entry reaches server exactly once', pendingNotice && midCount === before && final === '1' && Number(total) === Number(before) + 1, `offline notice=${pendingNotice}, rows before=${before} while offline=${midCount} after reconnect value=47 rows=${final}, total=${total}`)

// ---- 5.4 service worker never caches /api/
const sw = await page.evaluate(async () => {
  const reg = await navigator.serviceWorker?.getRegistration()
  await fetch('/api/me', { headers: { authorization: 'Bearer ' + localStorage.getItem('xoso_token') } })
  const out = []
  for (const k of await caches.keys()) { const c = await caches.open(k); for (const r of await c.keys()) out.push(new URL(r.url).pathname) }
  return { reg: !!reg, active: !!reg?.active, urls: out }
})
rec('5 service worker active and no /api/ in any cache', sw.reg && sw.urls.length > 0 && !sw.urls.some((u) => u.startsWith('/api/')), `registered=${sw.reg} cached=${sw.urls.length} entries, api entries=${sw.urls.filter((u) => u.startsWith('/api/')).length}`)

// ---- 5.5 invalid / expired token -> /login?redirect=
await page.evaluate(() => { localStorage.setItem('xoso_token', 'garbage.invalid.token'); localStorage.setItem('xoso_role', 'user') })
await page.goto(W + '/entries', { waitUntil: 'networkidle0' }); await sleep(2500)
rec('5 invalid token -> /login?redirect=', path().startsWith('/login') && /redirect=/.test(path()), `url=${path()}`)
// really expired: revoke the live session server-side while logged in
await page.evaluate(() => localStorage.clear())
await uiLogin(Bu.u, Bu.p)
const tok = await page.evaluate(() => localStorage.getItem('xoso_token'))
await api('DELETE', '/me/sessions/current', tok)
await page.goto(W + '/customers', { waitUntil: 'networkidle0' }); await sleep(2500)
rec('5 revoked/expired session -> /login?redirect=', path().startsWith('/login') && /redirect=/.test(path()), `url=${path()}`)

await browser.close()
console.log('SUMMARY', results.filter(Boolean).length, 'pass', results.filter((x) => !x).length, 'fail')
