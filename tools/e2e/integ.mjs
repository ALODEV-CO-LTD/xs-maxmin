const B = 'http://127.0.0.1:4173/api'
let pass = 0, fail = 0
const ok = (c, n, e = '') => { c ? pass++ : fail++; console.log((c ? 'PASS ' : 'FAIL ') + n + (c ? '' : '  -> ' + e)) }
const call = async (method, p, body, tok) => { const r = await fetch(B + p, { method, headers: { 'content-type': 'application/json', ...(tok ? { authorization: 'Bearer ' + tok } : {}) }, body: body === undefined ? undefined : (typeof body === 'string' ? body : JSON.stringify(body)) }); let d = null; try { d = await r.json() } catch {} ; return { s: r.status, d } }
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const x = Date.now().toString(36).slice(-6); const U = 'int' + x, PW = 'Smoke#Test123', PW2 = 'Brand#New4567', SEC = '2468'

console.log('--- register / login / policy')
let r = await call('POST', '/auth/register', { name: 'T', username: 'w' + U, password: '12345678', secondPassword: SEC }); ok(r.s === 400, 'weak password (12345678) rejected at register', JSON.stringify(r))
r = await call('POST', '/auth/register', { username: 5, password: 'x' }); ok(r.s === 400, 'wrong-typed body -> 400 (not 500)', String(r.s))
r = await call('POST', '/auth/register', { name: 'T', username: U, password: PW, secondPassword: SEC }); ok(r.s === 200 || r.s === 201, 'strong register ok', JSON.stringify(r).slice(0, 80)); const rec1 = r.d.recoveryCode
const login = () => call('POST', '/auth/login', { username: U, password: PW })
let l = await login(); ok(l.d.stage === 'second_password_required', 'login -> second password stage')
r = await call('POST', '/auth/step2', { pendingToken: l.d.pendingToken, password: 'wrong' }); ok(r.s === 401, 'wrong second password 401')
r = await call('POST', '/auth/step2', { pendingToken: l.d.pendingToken, password: SEC }); ok(r.s === 200 && !!r.d.token, 'same pendingToken still usable after a wrong try', JSON.stringify(r).slice(0, 80)); const S1 = r.d.token
r = await call('POST', '/auth/step2', { pendingToken: l.d.pendingToken, password: SEC }); ok(r.s === 401, 'pendingToken is one-time after success', String(r.s))
r = await call('GET', '/me', undefined, l.d.pendingToken); ok(r.s === 401, 'pendingToken as Bearer -> 401', String(r.s))
l = await login(); r = await call('POST', '/auth/step2', { pendingToken: l.d.pendingToken, password: SEC }); const S2 = r.d.token

console.log('--- change password')
r = await call('POST', '/me/password', { currentPassword: 'nope-nope', newPassword: PW2 }, S1); ok(r.s === 401, 'wrong current password -> 401', String(r.s))
r = await call('POST', '/me/password', { currentPassword: PW, newPassword: '123456789' }, S1); ok(r.s === 400, 'weak new password rejected', JSON.stringify(r))
r = await call('POST', '/me/password', { currentPassword: PW, newPassword: PW2 }, S1); ok(r.s === 200, 'password changed', JSON.stringify(r))
ok((await call('GET', '/me', undefined, S1)).s === 200, 'current session kept after password change')
ok((await call('GET', '/me', undefined, S2)).s === 401, 'OTHER session revoked after password change')
r = await call('POST', '/auth/login', { username: U, password: PW }); ok(r.s === 401, 'old password no longer works')
l = await call('POST', '/auth/login', { username: U, password: PW2 }); ok(l.d.stage === 'second_password_required', 'new password works')

console.log('--- recovery')
let s = await call('POST', '/auth/step2', { pendingToken: l.d.pendingToken, password: SEC }); const S3 = s.d.token
r = await call('POST', '/auth/recover', { username: U, recoveryCode: rec1, newPassword: '12345678' }); ok(r.s === 400, 'recover with weak new password rejected', String(r.s))
r = await call('POST', '/auth/recover', { username: U, recoveryCode: rec1, newPassword: PW }); ok(r.s === 200 && !!r.d.recoveryCode, 'recover ok, new code issued', JSON.stringify(r).slice(0, 60))
ok((await call('GET', '/me', undefined, S3)).s === 401 && (await call('GET', '/me', undefined, S1)).s === 401, 'ALL old sessions revoked by recovery')
const codes = []; for (const name of [U, 'doesnotexist' + x, '1']) { const out = []; for (let i = 0; i < 7; i++) out.push((await call('POST', '/auth/recover', { username: name, recoveryCode: 'AAAA-BBBB-CCCC-DDDD', newPassword: 'Zxcv#Asdf99' })).s); codes.push(out.join(',')) }
ok(codes[0] === codes[1] && codes[1] === codes[2], 'recover: real / unknown / admin names behave identically', JSON.stringify(codes))

console.log('--- login enumeration (timing)')
const time = async (name) => { const t = []; for (let i = 0; i < 3; i++) { const a = Date.now(); await call('POST', '/auth/login', { username: name, password: 'zzz-wrong-pw' }); t.push(Date.now() - a); await sleep(50) } return Math.round(t.reduce((p, c) => p + c) / 3) }
const tKnown = await time('2'), tUnknown = await time('no-such-user-' + x)
ok(Math.max(tKnown, tUnknown) / Math.max(1, Math.min(tKnown, tUnknown)) < 2, `timing known ${tKnown}ms vs unknown ${tUnknown}ms are close`)

console.log('--- admin lock')
const adm = await call('POST', '/auth/login', { username: '1', password: '1234' }); const A = adm.d.token
const usr = await call('POST', '/auth/login', { username: U, password: PW }); const pend = usr.d.pendingToken
const s4 = await call('POST', '/auth/step2', { pendingToken: (await call('POST', '/auth/login', { username: U, password: PW })).d.pendingToken, password: SEC }); const S5 = s4.d.token
const list = await call('GET', '/admin/users', undefined, A); const uid = (list.d.subscribers).find((u) => u.username === U).id
r = await call('PATCH', '/admin/users/' + uid, { locked: true }, A); ok(r.s === 200, 'admin locks user', JSON.stringify(r).slice(0, 80))
ok((await call('GET', '/me', undefined, S5)).s === 401, 'locked user\'s existing token -> 401')
r = await call('POST', '/auth/step2', { pendingToken: pend, password: SEC }); ok(r.s === 403, 'step2 refuses a locked account', String(r.s))
r = await call('POST', '/auth/login', { username: U, password: 'wrong-pw-xx' }); ok(r.s === 401, 'locked + wrong password -> 401 (does not reveal lock)', String(r.s))
await call('PATCH', '/admin/users/' + uid, { locked: false }, A)

console.log('--- re-auth limits and wipe')
l = await call('POST', '/auth/login', { username: U, password: PW }); s = await call('POST', '/auth/step2', { pendingToken: l.d.pendingToken, password: SEC }); const T = s.d.token
r = await call('POST', '/me/wipe-password', { currentPassword: PW, wipePassword: 'Wipe#Pass789' }, T); ok(r.s === 200, 'wipe password set', JSON.stringify(r).slice(0, 80))
r = await call('POST', '/me/second-password', { currentPassword: PW, secondPassword: 'Wipe#Pass789' }, T); ok(r.s === 400, 'second password equal to wipe password rejected', JSON.stringify(r))
await call('POST', '/me/customers', { name: 'KH-wipe' }, T); await call('POST', '/me/entries', { customerName: 'KH-wipe', entryDate: '2026-10-07', value: '12', score: '3', betType: 'de' }, T)
const wrong = []; for (let i = 0; i < 7; i++) wrong.push((await call('POST', '/me/delete-data', { password: 'wrong-' + i }, T)).s); ok(wrong[0] === 403 && wrong.includes(429), 'wrong password -> 403 then rate limited (429)', wrong.join(','))
ok((await call('GET', '/me', undefined, T)).s === 200, 'still logged in after wrong re-auth attempts')
console.log(`\n${pass} passed, ${fail} failed`)
