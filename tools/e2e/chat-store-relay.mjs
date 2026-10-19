// Two-device check of the Next.js chat store (web-next/src/features/chat/chatStore.js) against a RUNNING backend
// (default http://localhost:8080). Device A is the real store (in-memory database, real WebSocket); device B is played
// with the raw crypto functions, exactly like tools/e2e/e2ee-relay.mjs, so the wire format is checked both ways.
//   node --import ./web-next/tests/stubs.mjs tools/e2e/chat-store-relay.mjs <userA> <passA> <secondA> <userB> <passB> <secondB>
// A and B must already be friends. Nothing is written to the server except the two public keys.
import { useChatStore, deps } from '../../web-next/src/features/chat/chatStore.js'
import { bindSocket } from '../../web-next/src/features/calls/transport.js'
import { decryptBytes, deriveSessionKey, encryptBytes, generateIdentity, newMessageId, packMessage, unpackMessage } from '../../web-next/src/lib/e2ee/crypto.js'

const BASE = process.env.BASE || 'http://localhost:8080/api'
const [uA, pA, sA, uB, pB, sB] = process.argv.slice(2)
let pass = 0, fail = 0
const ok = (c, n) => { c ? pass++ : fail++; console.log((c ? 'PASS ' : 'FAIL ') + n) }
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const call = async (m, p, b, t) => { const r = await fetch(BASE + p, { method: m, headers: { 'content-type': 'application/json', ...(t ? { authorization: 'Bearer ' + t } : {}) }, body: b ? JSON.stringify(b) : undefined }); return { s: r.status, j: await r.json().catch(() => null) } }
async function login(u, p, s) { const a = await call('POST', '/auth/login', { username: u, password: p }); const t = await call('POST', '/auth/step2', { pendingToken: a.j.pendingToken, password: s }); return t.j.token }
const open = (token, onMessage) => new Promise((resolve) => {
  const ws = new WebSocket(BASE.replace('http', 'ws') + '/ws/calls?token=' + encodeURIComponent(token))
  ws.onmessage = (e) => onMessage(JSON.parse(e.data))
  ws.onopen = () => resolve(ws)
})

const tA = await login(uA, pA, sA), tB = await login(uB, pB, sB)
const meA = (await call('GET', '/me', null, tA)).j, meB = (await call('GET', '/me', null, tB)).j

// ---- device A: the store, with the real API and a real socket ----
const mem = { identity: new Map(), peers: new Map(), messages: new Map(), meta: new Map() }
deps.idb = {
  openChatDb: async () => ({ close() {} }),
  get: async (_d, s, k) => mem[s].get(k),
  getAll: async (_d, s) => [...mem[s].values()],
  put: async (_d, s, v) => void mem[s].set(v.id, structuredClone(v)),
  del: async (_d, s, k) => void mem[s].delete(k),
  messagesOf: async (_d, p) => [...mem.messages.values()].filter((m) => m.peerId === p),
}
deps.me = () => meA.id
deps.api = { get: async (p) => (await call('GET', p, null, tA)).j, put: async (p, b) => (await call('PUT', p, b, tA)).j }
let wsA = null
bindSocket((m) => wsA?.send(JSON.stringify(m)), () => wsA?.readyState === 1)
wsA = await open(tA, (m) => deps.transport.deliverToChat(m))
await useChatStore.getState().init()
ok(useChatStore.getState().ready, 'A: store ready, key published')

// ---- device B: raw crypto ----
const B = await generateIdentity()
await call('PUT', '/me/e2ee-key', { publicKey: B.publicJwk }, tB)
await useChatStore.getState().loadFriendKeys()
const inboxB = []
const wsB0 = await open(tB, (m) => inboxB.push(m))
const aKey = useChatStore.getState().friendKeys[meB.id]
ok(aKey?.x === B.publicJwk.x, "A sees B's public key")
const myJwk = [...mem.identity.values()][0].publicJwk
const kB = await deriveSessionKey(B.privateKey, myJwk, meB.id, meA.id)

// A -> B, B online
const m1 = await useChatStore.getState().send({ id: meB.id, name: 'B' }, 'từ kho Next.js', null)
await sleep(1500)
const got = inboxB.filter((m) => m.type === 'e2ee-msg' && m.id === m1.id).sort((a, b) => a.part - b.part)
ok(got.length === got[0]?.parts, 'B receives all parts of the envelope')
const plain = got.length && unpackMessage(await decryptBytes(kB, { iv: got[0].iv, ct: got.map((f) => f.ct).join('') }, { from: meA.id, to: meB.id, id: m1.id }))
ok(plain?.text === 'từ kho Next.js', 'B decrypts the text sent by the store')
wsB0.send(JSON.stringify({ type: 'e2ee-ack', to: meA.id, id: m1.id })); await sleep(800)
ok((await useChatStore.getState().messages(meB.id)).find((m) => m.id === m1.id)?.status === 'delivered', 'ack from B marks the message delivered')

// B -> A
const id2 = newMessageId()
const kBA = kB
const e = await encryptBytes(kBA, packMessage({ text: 'trả lời từ B' }), { from: meB.id, to: meA.id, id: id2 })
wsB0.send(JSON.stringify({ type: 'e2ee-msg', to: meA.id, id: id2, ...e, part: 0, parts: 1, ts: Date.now() })); await sleep(1500)
ok((await useChatStore.getState().messages(meB.id)).some((m) => m.id === id2 && m.text === 'trả lời từ B' && !m.mine), 'A stores and decrypts the message from B')
ok(inboxB.some((m) => m.type === 'e2ee-ack' && m.id === id2), 'A acked the message')

// B offline -> undelivered(offline) -> label
wsB0.close(); await sleep(800)
const m3 = await useChatStore.getState().send({ id: meB.id, name: 'B' }, 'khi B offline', null); await sleep(1000)
const last = (await useChatStore.getState().messages(meB.id)).find((m) => m.id === m3.id)
ok(last?.status === 'failed' && last.reason === 'offline', 'offline friend -> failed with reason "offline"')
wsA.close()
console.log(`\n${pass} passed, ${fail} failed`)
process.exit(fail ? 1 : 0)
