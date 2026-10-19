// Khói cho bản web Next.js: mở TỪNG route với đúng vai (khách / admin), ghi lỗi trang, lỗi console, API 4xx/5xx và chụp ảnh.
// Cần: tools/e2e/next-stack.sh start; puppeteer-core (PPT=/đường/dẫn/node_modules/puppeteer-core); SITE, SHOTS (thư mục ảnh).
//   SITE=http://127.0.0.1:8592 SHOTS=/tmp/shots PPT=... node tools/e2e/next-smoke.mjs
import { createRequire } from 'node:module'
// PPT = thư mục chứa node_modules/puppeteer-core (hoặc cài puppeteer-core ở thư mục hiện tại)
const puppeteer = createRequire((process.env.PPT || process.cwd()) + '/')('puppeteer-core')
const SITE = process.env.SITE || 'http://127.0.0.1:8592', API = SITE + '/api', SHOTS = process.env.SHOTS || '.'
const ADMIN_PASS = process.env.ADMIN_PASS || 'Next-admin-Pass-1'
const call = async (m, p, b, t) => { const r = await fetch(API + p, { method: m, headers: { 'content-type': 'application/json', ...(t ? { authorization: 'Bearer ' + t } : {}) }, body: b ? JSON.stringify(b) : undefined }); return { s: r.status, j: await r.json().catch(() => null) } }
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const username = 'smoke' + Date.now().toString(36).slice(-6)
const reg = (await call('POST', '/auth/register', { name: 'Khach Thu', username, password: 'Pass-1234', secondPassword: 'Second-1234' })).j
const user = (await call('POST', '/auth/step2', { pendingToken: reg.pendingToken, password: 'Second-1234' })).j.token
const a1 = (await call('POST', '/auth/login', { username: '1', password: ADMIN_PASS })).j
// the seed admin has no second password: /auth/login answers with the token at once (else do step 2)
const admin = a1.token || (await call('POST', '/auth/step2', { pendingToken: a1.pendingToken, password: ADMIN_PASS })).j.token
await call('POST', '/me/customers', { name: 'An' }, user)
const USER_ROUTES = ['/entries', '/results', '/scoring', '/scoring-settings', '/customers', '/friends', '/account', '/account?tab=packages']
const ADMIN_ROUTES = ['/admin/users', '/admin/stats', '/admin/settings', '/admin/payment-requests', '/admin/messages', '/admin/notices', '/admin/staff']
const br = await puppeteer.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true, args: ['--no-sandbox'] })
let bad = 0
async function walk(role, token, routes) {
  for (const r of routes) {
    const ctx = await br.createBrowserContext(); const p = await ctx.newPage(); await p.setViewport({ width: 1100, height: 800 })
    const errs = []
    p.on('pageerror', (e) => errs.push('pageerror: ' + e.message.slice(0, 160)))
    p.on('console', (m) => { if (m.type() === 'error' && !/navigator\.vibrate/.test(m.text())) errs.push('console: ' + m.text().slice(0, 160)) })
    p.on('response', (x) => { if (x.url().includes('/api/') && x.status() >= 400 && x.status() !== 401 && x.status() !== 404) errs.push(`HTTP ${x.status()} ${x.url().replace(SITE, '')}`) })
    await p.goto(SITE + '/login', { waitUntil: 'networkidle0' })
    await p.evaluate((t, ro) => { localStorage.setItem('xoso_token', t); localStorage.setItem('xoso_role', ro) }, token, role)
    await p.goto(SITE + r, { waitUntil: 'networkidle0' }); await sleep(1200)
    const text = (await p.evaluate(() => document.body.innerText)).replace(/\s+/g, ' ').slice(0, 90)
    const stub = /đang được chuyển từ Vue/.test(text), blank = text.length < 5, wrongUrl = !new URL(p.url()).pathname.startsWith(r.split('?')[0])
    const fail = errs.length || stub || blank || wrongUrl
    if (fail) bad++
    console.log((fail ? 'FAIL ' : 'PASS ') + role + ' ' + r + (wrongUrl ? ' -> redirected to ' + p.url().replace(SITE, '') : '') + (stub ? ' [still a stub]' : '') + (blank ? ' [blank]' : '') + ' | ' + text.slice(0, 50))
    for (const e of [...new Set(errs)].slice(0, 4)) console.log('     ' + e)
    await p.screenshot({ path: `${SHOTS}/${role}-${r.replace(/[^a-z]/gi, '_')}.png` })
    await ctx.close()
  }
}
await walk('user', user, USER_ROUTES)
await walk('admin', admin, ADMIN_ROUTES)
await br.close()
console.log(bad ? `${bad} route(s) with problems` : 'ALL ROUTES OK')
process.exit(bad ? 1 : 0)
