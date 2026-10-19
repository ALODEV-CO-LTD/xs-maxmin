// End-to-end check of the encrypted relay against a running backend (default http://localhost:8080).
// Needs two friends: node tools/e2e/e2ee-relay.mjs <userA> <passA> <secondA> <userB> <passB> <secondB>
import { decryptBytes, deriveSessionKey, encryptBytes, generateIdentity, newMessageId, packMessage, unpackMessage } from '../../web-next/src/lib/e2ee/crypto.js'
const BASE = process.env.BASE || 'http://localhost:8080/api'
const [uA, pA, sA, uB, pB, sB] = process.argv.slice(2)
let pass = 0, fail = 0
const ok = (c, n) => { c ? pass++ : fail++; console.log((c ? 'PASS ' : 'FAIL ') + n) }
const call = async (m, p, b, t) => { const r = await fetch(BASE + p, { method: m, headers: { 'content-type': 'application/json', ...(t ? { authorization: 'Bearer ' + t } : {}) }, body: b ? JSON.stringify(b) : undefined }); return { s: r.status, j: await r.json().catch(() => null) } }
async function login(u, p, s) { const a = await call('POST', '/auth/login', { username: u, password: p }); const t = await call('POST', '/auth/step2', { pendingToken: a.j.pendingToken, password: s }); return t.j.token }
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
function open(token) {
  return new Promise((resolve) => {
    const ws = new WebSocket(BASE.replace('http', 'ws') + '/ws/calls?token=' + encodeURIComponent(token))
    const inbox = []
    ws.onmessage = (e) => inbox.push(JSON.parse(e.data))
    ws.onopen = () => resolve({ ws, inbox })
  })
}
const tA = await login(uA, pA, sA), tB = await login(uB, pB, sB)
const meA = (await call('GET', '/me', null, tA)).j, meB = (await call('GET', '/me', null, tB)).j
const A = await generateIdentity(), B = await generateIdentity()
ok((await call('PUT', '/me/e2ee-key', { publicKey: A.publicJwk }, tA)).s === 200, 'publish key A')
ok((await call('PUT', '/me/e2ee-key', { publicKey: B.publicJwk }, tB)).s === 200, 'publish key B')
ok((await call('PUT', '/me/e2ee-key', { publicKey: { ...A.publicJwk, d: 'x' , x: 'short' } }, tA)).s === 400, 'bad key rejected')
const friends = (await call('GET', '/me/friends', null, tA)).j.friends
ok(friends.find((f) => f.id === meB.id)?.publicKey?.x === B.publicJwk.x, "friend list carries B's public key")

const a = await open(tA)
const kA = await deriveSessionKey(A.privateKey, B.publicJwk, meA.id, meB.id)
const kB = await deriveSessionKey(B.privateKey, A.publicJwk, meB.id, meA.id)
const send = async (text, file) => { const id = newMessageId(); const e = await encryptBytes(kA, packMessage({ text }, file), { from: meA.id, to: meB.id, id }); const n = Math.ceil(e.ct.length / 1000000); for (let i = 0; i < n; i++) a.ws.send(JSON.stringify({ type: 'e2ee-msg', to: meB.id, id, iv: e.iv, ct: e.ct.slice(i * 1000000, (i + 1) * 1000000), part: i, parts: n })); return id }

// B offline: nothing delivered, sender told, nothing stored.
const id1 = await send('khi B offline'); await sleep(500)
ok(a.inbox.some((m) => m.type === 'e2ee-undelivered' && m.id === id1 && m.reason === 'offline'), 'offline friend -> undelivered')

// B online: delivered, decrypts, ack relayed back.
const b = await open(tB)
const big = new Uint8Array(Number(process.env.SIZE || 3 * 1024 * 1024)).map((_, i) => (i * 31 + 7) & 255)
const id2 = await send('xin chào B', big); await sleep(Number(process.env.WAIT || 1500))
const frames = b.inbox.filter((m) => m.type === 'e2ee-msg' && m.id === id2).sort((x, y) => x.part - y.part)
const got = frames.length && frames.length === frames[0].parts ? { ...frames[0], ct: frames.map((f) => f.ct).join('') } : undefined
ok(!!got && got.from === meA.id, 'online friend receives the envelope')
const plain = got && unpackMessage(await decryptBytes(kB, got, { from: got.from, to: meB.id, id: got.id }))
ok(plain?.text === 'xin chào B' && plain.file.length === big.length, 'B decrypts text and a 3 MB file')
ok(!JSON.stringify(got || {}).includes('xin chào'), 'server only ever saw ciphertext')
b.ws.send(JSON.stringify({ type: 'e2ee-ack', to: meA.id, id: id2 })); await sleep(1000)
ok(a.inbox.some((m) => m.type === 'e2ee-ack' && m.id === id2), 'ack relayed to sender'); if (process.env.DEBUG) console.log(JSON.stringify(a.inbox).slice(0, 400))

// A stranger who is not a friend cannot send.
const reg = await call('POST', '/auth/register', { name: 'S', username: 's' + Date.now().toString(36), password: 'x', secondPassword: 'y' })
const tS = (await call('POST', '/auth/step2', { pendingToken: reg.j.pendingToken, password: 'y' })).j.token
const s = await open(tS)
s.ws.send(JSON.stringify({ type: 'e2ee-msg', to: meB.id, id: newMessageId(), iv: 'AAAAAAAAAAAAAAAA', ct: 'AAAA' })); await sleep(400)
ok(s.inbox.some((m) => m.type === 'e2ee-undelivered' && m.reason === 'not-friend') && !b.inbox.some((m) => m.from && m.from !== meA.id), 'non-friend refused')
for (const c of [a, b, s]) c.ws.close()
console.log(`\n${pass} passed, ${fail} failed`)
process.exit(fail ? 1 : 0)
