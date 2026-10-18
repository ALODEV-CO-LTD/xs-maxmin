// Audit 18/10 - security checks 3(a)-(h) through real HTTP/WebSocket.
// node audit1810-http.mjs <port> <sqlitePath>   (backend started with XOSO_SEED_DEMO=1 XOSO_ADMIN_PASSWORD=Test-Admin-1)
import { execFileSync } from 'node:child_process'
const [port, dbPath] = [process.argv[2] || '8537', process.argv[3]]
const B = `http://127.0.0.1:${port}`
const sql = (q) => execFileSync('sqlite3', [dbPath, q]).toString().trim()
const results = []
const rec = (name, ok, ev) => { results.push({ name, ok }); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}  | ${ev}`) }
async function req(method, path, { token, body, headers = {}, raw } = {}) {
  const r = await fetch(B + path, {
    method,
    headers: { ...(body !== undefined || raw ? { 'content-type': 'application/json' } : {}), ...(token ? { authorization: `Bearer ${token}` } : {}), ...headers },
    body: raw ?? (body !== undefined ? JSON.stringify(body) : undefined),
    signal: AbortSignal.timeout(20000),
  })
  let j = null; try { j = await r.json() } catch {}
  return { s: r.status, j }
}
async function login(u, p, headers) { const r = await req('POST', '/api/auth/login', { body: { username: u, password: p }, headers }); return { ...r, token: r.j?.token } }
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const admin = (await login('1', 'Test-Admin-1')).token
const demo = { 2: '1235', 3: '1236', 4: '1237', 5: '1238', 6: '1239' }
const tok = {}
for (const u of [2, 3, 4]) tok[u] = (await login(String(u), demo[u])).token
console.log('tokens', Object.fromEntries(Object.entries(tok).map(([k, v]) => [k, !!v])), 'admin', !!admin)

// ---- (a) malformed WS frames
function openWs(token) {
  return new Promise((res, rej) => {
    const ws = new WebSocket(`ws://127.0.0.1:${port}/api/ws/calls?token=${token}`)
    ws.closeInfo = null
    ws.addEventListener('open', () => res(ws))
    ws.addEventListener('close', (e) => { ws.closeInfo = { code: e.code, at: Date.now() } })
    ws.addEventListener('error', () => rej(new Error('ws error')))
  })
}
{
  const ws = await openWs(tok[2])
  for (const f of ['{"to":5}', '{"type":7}', '[]', 'null', '"x"', '{"to":{},"type":[]}', 'x'.repeat(5 * 1024 * 1024), '{"type":"offer","to":"' + 'y'.repeat(3 * 1024 * 1024) + '"}']) { try { ws.send(f) } catch {} await sleep(150) }
  await sleep(500)
  const alive = await req('GET', '/api/app-version')
  const me = await req('GET', '/api/me', { token: tok[2] })
  rec('3a ws malformed frames: server alive', alive.s === 200 && me.s === 200, `after 8 junk frames GET /api/app-version=${alive.s}, /api/me=${me.s}, ws closeInfo=${JSON.stringify(ws.closeInfo)}`)
  ws.close()
}

// ---- (b) revoke while socket open
const fcm = (n) => 'f' + String(n).padStart(3, '0') + 'A'.repeat(110)
for (const [u, how] of [[3, 'logout'], [4, 'password']]) {
  // password change revokes every OTHER session (the caller's own stays), so for it the socket lives on a 2nd login
  const t = how === 'logout' ? tok[u] : (await login(String(u), demo[u])).token
  const tokenStr = fcm(u)
  const pr = await req('POST', '/api/me/push-token', { token: t, body: { platform: 'android', token: tokenStr } })
  const before = sql(`select count(*) from push_tokens where token='${tokenStr}'`)
  const ws = await openWs(t)
  const t0 = Date.now()
  let rv
  if (how === 'logout') rv = await req('DELETE', '/api/me/sessions/current', { token: t })
  else rv = await req('POST', '/api/me/password', { token: tok[u], body: { currentPassword: demo[u], newPassword: 'New-Pass-9876x' } })
  // password change may revoke only other sessions; also revoke all other sessions from a 2nd login to be fair
  let waited = 0
  while (!ws.closeInfo && Date.now() - t0 < 40000) await sleep(500)
  const after = sql(`select count(*) from push_tokens where token='${tokenStr}'`)
  const dt = ws.closeInfo ? ((ws.closeInfo.at - t0) / 1000).toFixed(1) : 'never'
  rec(`3b ${how}: ws closed 4401 within 35s + push token removed`, ws.closeInfo?.code === 4401 && Number(dt) <= 35 && before === '1' && after === '0',
    `push-token reg=${pr.s}, rows before=${before} after=${after}, revoke=${rv.s}, ws close code=${ws.closeInfo?.code} after ${dt}s`)
}

// ---- (c) settings allowlist
{
  const out = {}
  for (const k of ['POLICY.tokenDays', 'policy.tokenDays', 'maintenance_enabled', 'bank_name']) out[k] = (await req('PUT', '/api/admin/settings', { token: admin, body: { [k]: k === 'bank_name' ? 'TestBank' : '5' } })).s
  const rows = sql(`select group_concat(key) from settings where key in ('POLICY.tokenDays','policy.tokenDays','maintenance_enabled')`)
  rec('3c settings allowlist', out['bank_name'] === 200 && out['POLICY.tokenDays'] >= 400 && out['policy.tokenDays'] >= 400 && out['maintenance_enabled'] >= 400 && rows === '', `statuses=${JSON.stringify(out)}, forbidden keys in settings table='${rows}'`)
  const cap = await req('PUT', '/api/admin/settings', { token: admin, body: { max_virtual_ids: 10 } })
}

// ---- (d) body limit + register rate
{
  const big = await req('POST', '/api/auth/login', { raw: JSON.stringify({ username: 'a', password: 'p'.repeat(20 * 1024) }) })
  rec('3d 20KB login body -> 413', big.s === 413, `status=${big.s}`)
}

// ---- (e) client IP
{
  const U = '5'
  const statuses = { A: [], B: [] }
  for (let i = 0; i < 6; i++) statuses.A.push((await login(U, 'wrong-' + i, { 'cf-connecting-ip': '203.0.113.10' })).s)
  const bWrong = (await login(U, 'wrong-b', { 'cf-connecting-ip': '203.0.113.20' })).s
  const bRight = (await login(U, demo[5], { 'cf-connecting-ip': '203.0.113.20' })).s
  const aRight = (await login(U, demo[5], { 'cf-connecting-ip': '203.0.113.10' })).s
  const noHdr = (await login('2', demo[2])).s
  rec('3e client IP via CF-Connecting-IP', statuses.A.includes(429) && bWrong === 401 && bRight === 200 && aRight === 429 && noHdr === 200,
    `A wrong x6=${statuses.A}; B wrong=${bWrong}, B right=${bRight}; A right(after lock)=${aRight}; no header login=${noHdr}`)
}

// ---- (f) customer-code sweep
{
  const taken = sql(`select code from customer_codes limit 1`)
  const seq = []
  for (let i = 0; i < 80; i++) { const r = await req('POST', '/api/me/customer-codes', { token: tok[2], body: { code: taken }, headers: { 'cf-connecting-ip': '198.51.100.7' } }); seq.push(r.s); if (r.s === 429) break }
  const first429 = seq.indexOf(429) + 1
  // delete never-used code (other user, other ip)
  const t5 = (await login('6', demo[6], { 'cf-connecting-ip': '198.51.100.99' })).token
  const c = await req('POST', '/api/me/customer-codes', { token: t5, body: {}, headers: { 'cf-connecting-ip': '198.51.100.99' } })
  const id = c.j?.id, code = c.j?.code
  const d = await req('DELETE', `/api/me/customer-codes/${id}`, { token: t5, headers: { 'cf-connecting-ip': '198.51.100.99' } })
  const rc = sql(`select count(*) from retired_codes where code='${code}'`)
  rec('3f sweep -> 429', first429 > 0, `taken code POSTs: ${seq.length} tries, first 429 on try ${first429} (statuses ${[...new Set(seq)]})`)
  rec('3f unused code delete leaves no retired_codes row', c.s === 201 || c.s === 200 ? d.s === 200 && rc === '0' : false, `create=${c.s} code=${code} delete=${d.s} retired rows=${rc}`)
}

// ---- (g) lottery date
{
  const r = await req('POST', '/api/lottery-results', { token: tok[2], body: { drawDate: '2026-10-18 00:00', station: 'mb' } })
  rec('3g drawDate with time -> 400 (date error)', r.s === 400 && /Ngày không hợp lệ/.test(r.j?.error || ''), `status=${r.s} body=${JSON.stringify(r.j)}`)
}

// ---- (h) delete staff who decided a payment
{
  const sname = 'staff' + Date.now().toString(36)
  const st = await req('POST', '/api/admin/staff', { token: admin, body: { name: 'Staff T', username: sname, password: 'Staff-Pass-12345', permissions: ['payments.manage'] } })
  const sTok = (await login(sname, 'Staff-Pass-12345')).token
  const pk = await req('GET', '/api/me/packages', { token: tok[2] })
  const code = pk.j?.packages?.[0]?.code ?? pk.j?.packages?.[0]?.type ?? pk.j?.packages?.[0]?.id
  const pu = await req('POST', '/api/me/packages/purchase', { token: tok[2], body: { packageType: code } })
  const prId = sql(`select id from payment_requests where status='pending' order by created_at desc limit 1`)
  const ap = await req('POST', `/api/admin/payment-requests/${prId}/approve`, { token: sTok, body: {} })
  const dec = sql(`select decided_by from payment_requests where id='${prId}'`)
  const del = await req('DELETE', `/api/admin/staff/${st.j?.id}`, { token: admin })
  rec('3h delete staff who decided a payment', st.s === 201 && ap.s === 200 && dec === st.j?.id && del.s === 200, `staff=${st.s} purchase=${pu.s} approve=${ap.s} decided_by set=${dec === st.j?.id} delete=${del.s} ${JSON.stringify(del.j)}`)
}

// ---- (d2) register rate: 11th -> 429 (run last; IP-limited)
{
  const seq = []
  for (let i = 0; i < 11; i++) {
    const r = await req('POST', '/api/auth/register', { body: { name: 'R' + i, username: 'reg' + Date.now().toString(36) + i, password: 'Reg-Pass-12345', secondPassword: '4821', wipePassword: 'Wipe-Pass-5555' } })
    seq.push(r.s)
  }
  rec('3d 11th registration same IP in 1h -> 429', seq[10] === 429 && !seq.slice(0, 10).includes(429), `statuses=${seq}`)
}
console.log('\nSUMMARY', results.filter((r) => r.ok).length, 'pass', results.filter((r) => !r.ok).length, 'fail')
