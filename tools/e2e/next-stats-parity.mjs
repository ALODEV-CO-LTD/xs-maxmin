// So số liệu tab Thống kê (/account) giữa bản Next và bản Vue trên CÙNG một tài khoản/dữ liệu.
//   NEXT=http://127.0.0.1:8622 VUE=http://127.0.0.1:8623 PPT=... node tools/e2e/next-stats-parity.mjs
import { createRequire } from 'node:module'
const puppeteer = createRequire((process.env.PPT || process.cwd()) + '/')('puppeteer-core')
const NEXT = process.env.NEXT || 'http://127.0.0.1:8622', VUE = process.env.VUE || 'http://127.0.0.1:8623', API = `http://127.0.0.1:${process.env.BE || 8621}/api`
const FAKE_IP = `10.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}.${1 + Math.floor(Math.random() * 250)}`
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const call = async (m, p, b, t) => { const r = await fetch(API + p, { method: m, headers: { 'content-type': 'application/json', 'x-forwarded-for': FAKE_IP, ...(t ? { authorization: 'Bearer ' + t } : {}) }, body: b ? JSON.stringify(b) : undefined }); return { s: r.status, j: await r.json().catch(() => null) } }
const username = 'st' + Date.now().toString(36).slice(-5)
const reg = (await call('POST', '/auth/register', { name: 'Khach ST', username, password: 'Pass-1234', secondPassword: 'Second-1234' })).j
const T = (await call('POST', '/auth/step2', { pendingToken: reg.pendingToken, password: 'Second-1234' })).j.token
// gói hết hạn thì không nhập được: đặt gói qua admin nếu cần
const me = (await call('GET', '/me', null, T)).j
await call('POST', '/me/customers', { name: 'An' }, T); await call('POST', '/me/customers', { name: 'Binh' }, T)
const today = new Date(); const d = (n) => new Date(today.getTime() - n * 86400000).toISOString().slice(0, 10)
for (const [c, n, v, s, b] of [['An', 0, '12', '3', 'de'], ['An', 1, '34', '5', 'de'], ['Binh', 1, '56', '2', 'de'], ['Binh', 9, '78', '4', 'de'], ['An', 40, '90', '7', 'de']]) {
  const r = await call('POST', '/me/entries', { customerName: c, entryDate: d(n), value: v, score: s, betType: b, station: 'mb' }, T)
  if (r.s >= 300) console.log('seed entry failed', r.s, JSON.stringify(r.j).slice(0, 120))
}
const br = await puppeteer.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true, args: ['--no-sandbox'] })
async function grab(site, px) {
  const p = await br.newPage(); await p.setViewport({ width: 1200, height: 900 })
  await p.goto(site + '/login', { waitUntil: 'networkidle0' }); await p.evaluate((t) => { localStorage.setItem('xoso_token', t); localStorage.setItem('xoso_role', 'user') }, T)
  await p.goto(site + '/account?tab=stats', { waitUntil: 'networkidle0' }); await sleep(3000)
  const out = []
  const labels = await p.$$eval(`.${px}seg-opt`, (e) => e.map((x) => x.innerText.trim()))
  const metrics = labels.slice(0, 3), units = labels.slice(3)
  for (const m of metrics) for (const u of units) {
    const clk = async (l) => { const h = await p.evaluateHandle((l, sel) => [...document.querySelectorAll(sel)].find((e) => e.innerText.trim() === l), l, `.${px}seg-opt`); await h.asElement().click() }
    await clk(m); await clk(u); await sleep(250)
    out.push(`${m}/${u}: ` + (await p.$eval(`.${px ? 'st-' : ''}summary`, (e) => e.innerText.replace(/\s+/g, ' ').trim())) + ' | bars=' + (await p.$$eval(`.${px}chart rect`, (e) => e.length)) + ' | axis=' + (await p.$$eval(`.${px}axis`, (e) => e.map((x) => x.textContent).join(','))))
  }
  out.push('PAGE: ' + (await p.evaluate(() => document.body.innerText)).replace(/\s+/g, ' ').slice(-300))
  await p.close(); return out
}
const a = await grab(NEXT, 'st-'), b = await grab(VUE, '')
let diff = 0
a.forEach((l, i) => { if (l !== b[i]) { diff++; console.log('DIFF\n  next: ' + l + '\n  vue : ' + b[i]) } })
console.log(`${a.length - diff}/${a.length} dòng giống nhau`); console.log(a[0]); console.log(a[a.length - 2])
await br.close(); process.exit(diff ? 1 : 0)
