// Kho chat mã hoá 2 đầu (features/chat/chatStore.js) chạy với CSDL trong bộ nhớ và ổ cắm giả; máy "bạn bè" được đóng
// vai bằng chính các hàm mã hoá (đúng định dạng gói mà app Flutter dùng: e2ee-msg / e2ee-ack / e2ee-undelivered).
import test from 'node:test'
import assert from 'node:assert/strict'

const mem = new Map()
globalThis.localStorage = { getItem: (k) => (mem.has(k) ? mem.get(k) : null), setItem: (k, v) => mem.set(k, String(v)), removeItem: (k) => mem.delete(k) }
const target = () => ({ addEventListener() {}, removeEventListener() {} })
globalThis.window = { ...target(), location: { pathname: '/friends', search: '', assign() {} }, matchMedia: () => ({ matches: false, ...target() }) }
globalThis.document = { ...target(), hidden: false, visibilityState: 'visible', hasFocus: () => true, documentElement: { dataset: {}, classList: { add() {}, remove() {} } }, title: '' }
Object.defineProperty(globalThis, 'navigator', { value: { onLine: true }, configurable: true })

const { useChatStore, deps, frameParts, LIMITS, reasonText } = await import('../src/features/chat/chatStore.js')
const { useNotifyStore } = await import('../src/lib/notifyStore.js')
const { decryptBytes, deriveSessionKey, encryptBytes, generateIdentity, newMessageId, packMessage, unpackMessage } = await import('../src/lib/e2ee/crypto.js')
const { groupHeader } = await import('../src/lib/e2ee/groups.js')

// ---- in-memory stand-in for src/lib/e2ee/db.js ----
function memoryDb() {
  const stores = { identity: new Map(), peers: new Map(), messages: new Map(), meta: new Map() }
  return {
    openChatDb: async () => ({ close() {} }),
    get: async (_db, s, k) => stores[s].get(k),
    getAll: async (_db, s) => [...stores[s].values()],
    put: async (_db, s, v) => void stores[s].set(v.id, structuredClone(v)),
    del: async (_db, s, k) => void stores[s].delete(k),
    messagesOf: async (_db, peerId) => [...stores.messages.values()].filter((m) => m.peerId === peerId),
    stores,
  }
}

const ME = 'u-me'
const BOB = 'u-bob'
const CAT = 'u-cat'
const sent = []
let socketUp = true
let clock = 1_700_000_000_000
const bob = await generateIdentity()
const cat = await generateIdentity()
let idb
let me
let friends

async function boot() {
  idb = memoryDb()
  sent.length = 0
  socketUp = true
  deps.idb = idb
  deps.me = () => ME
  deps.now = () => clock
  deps.transport = { send: (f) => sent.push(f), ready: () => socketUp }
  deps.api = {
    get: async (p) => (p === '/me/e2ee-key' ? { publicKey: null } : { friends }),
    put: async () => ({}),
  }
  friends = [
    { id: BOB, name: 'Bob', publicKey: bob.publicJwk },
    { id: CAT, name: 'Cat', publicKey: cat.publicJwk },
  ]
  useNotifyStore.setState({ unread: {}, toasts: [] })
  useChatStore.getState().reset()
  await useChatStore.getState().init()
  me = idb.stores.identity.get('self')
}
const chat = () => useChatStore.getState()
const keyFor = (peer, peerId) => deriveSessionKey(peer.privateKey, me.publicJwk, peerId, ME) // the friend's side of the session
const open = async (peer, peerId, frames) => {
  const f0 = frames[0]
  const ct = frames.sort((a, b) => a.part - b.part).map((f) => f.ct).join('')
  return unpackMessage(await decryptBytes(await keyFor(peer, peerId), { iv: f0.iv, ct }, { from: ME, to: peerId, id: f0.id }))
}
const settle = () => new Promise((r) => setTimeout(r, 5))

test('init: tạo khoá, công bố khoá công khai, đọc khoá bạn bè', async () => {
  await boot()
  assert.equal(chat().ready, true)
  assert.ok(chat().myFingerprint)
  assert.deepEqual(Object.keys(chat().friendKeys).sort(), [BOB, CAT])
  assert.equal(chat().peerInfo[BOB].changed, false)
})

test('gửi tin: gói e2ee-msg đúng định dạng, bạn giải mã được, ack → delivered', async () => {
  await boot()
  const msg = await chat().send({ id: BOB, name: 'Bob' }, 'xin chào', null)
  assert.equal(sent.length, 1)
  const f = sent[0]
  assert.deepEqual(Object.keys(f).sort(), ['ct', 'id', 'iv', 'part', 'parts', 'to', 'ts', 'type'])
  assert.equal(f.type, 'e2ee-msg')
  assert.equal(f.to, BOB)
  assert.equal(f.part, 0)
  assert.equal(f.parts, 1)
  assert.equal(f.id, msg.id)
  assert.ok(!JSON.stringify(f).includes('xin chào'), 'máy chủ chỉ thấy bản mã')
  const got = await open(bob, BOB, sent)
  assert.equal(got.text, 'xin chào')
  assert.equal((await chat().messages(BOB))[0].status, 'sent')
  await chat().onSocketMessage({ type: 'e2ee-ack', id: msg.id })
  assert.equal((await chat().messages(BOB))[0].status, 'delivered')
})

test('bạn bè offline: e2ee-undelivered → failed/offline, Gửi lại phát gói mới', async () => {
  await boot()
  const msg = await chat().send({ id: BOB, name: 'Bob' }, 'ping', null)
  await chat().onSocketMessage({ type: 'e2ee-undelivered', id: msg.id, reason: 'offline' })
  const [m] = await chat().messages(BOB)
  assert.equal(m.status, 'failed')
  assert.equal(m.reason, 'offline')
  assert.match(reasonText(m.reason), /offline/)
  await chat().retry({ id: msg.id, mine: true })
  assert.equal(sent.length, 2)
  assert.equal(sent[1].id, msg.id)
  assert.equal((await chat().messages(BOB))[0].status, 'sent')
})

test('ack đến sau khi đã failed không bị ghi đè ngược; failed không ghi đè delivered', async () => {
  await boot()
  const msg = await chat().send({ id: BOB, name: 'Bob' }, 'x', null)
  await chat().onSocketMessage({ type: 'e2ee-ack', id: msg.id })
  await chat().onSocketMessage({ type: 'e2ee-undelivered', id: msg.id, reason: 'offline' })
  assert.equal((await chat().messages(BOB))[0].status, 'delivered')
})

test('mất ổ cắm / chưa có khoá → failed với lý do đúng', async () => {
  await boot()
  socketUp = false
  await chat().send({ id: BOB, name: 'Bob' }, 'a', null)
  assert.equal((await chat().messages(BOB))[0].reason, 'no-socket')
  socketUp = true
  await chat().send({ id: 'u-nokey', name: 'Z' }, 'b', null)
  assert.equal((await chat().messages('u-nokey'))[0].reason, 'no-key')
})

test('nhận tin: giải mã, lưu, gửi ack, tăng chưa đọc, bỏ trùng', async () => {
  await boot()
  const key = await keyFor(bob, BOB)
  const id = newMessageId()
  const { iv, ct } = await encryptBytes(key, packMessage({ text: 'chào bạn', ts: clock }), { from: BOB, to: ME, id })
  const frame = { type: 'e2ee-msg', from: BOB, fromName: 'Bob', id, iv, ct, part: 0, parts: 1, ts: clock }
  await chat().onSocketMessage(frame)
  await chat().onSocketMessage(frame)
  const list = await chat().messages(BOB)
  assert.equal(list.length, 1)
  assert.equal(list[0].text, 'chào bạn')
  assert.equal(list[0].mine, false)
  assert.deepEqual(sent.filter((f) => f.type === 'e2ee-ack'), [{ type: 'e2ee-ack', to: BOB, id }])
  assert.equal(useNotifyStore.getState().unread[`friend:${BOB}`], 1)
  assert.equal(idb.stores.meta.get(`unread:${BOB}`).value, 1)
})

test('nhận tin nhiều phần ghép lại đúng thứ tự; ảnh được giữ, tệp khác bị bỏ', async () => {
  await boot()
  const key = await keyFor(bob, BOB)
  const png = new Uint8Array(3000).map((_, i) => i & 255)
  const id = newMessageId()
  const { iv, ct } = await encryptBytes(key, packMessage({ text: '', ts: clock, att: { name: 'a.png', type: 'image/png', size: png.length } }, png), { from: BOB, to: ME, id })
  const frames = []
  const cut = Math.ceil(ct.length / 3)
  for (let i = 0; i < 3; i++) frames.push({ type: 'e2ee-msg', from: BOB, id, iv, ct: ct.slice(i * cut, (i + 1) * cut), part: i, parts: 3, ts: clock })
  for (const f of [frames[2], frames[0], frames[1]]) await chat().onSocketMessage(f)
  const [m] = await chat().messages(BOB)
  assert.equal(m.att.isImage, true)
  assert.equal(m.att.size, png.length)
  const id2 = newMessageId()
  const e2 = await encryptBytes(key, packMessage({ text: 'x', ts: clock, att: { name: 'a.exe', type: 'application/x-msdownload', size: 3 } }, new Uint8Array([1, 2, 3])), { from: BOB, to: ME, id: id2 })
  await chat().onSocketMessage({ type: 'e2ee-msg', from: BOB, id: id2, ...e2, part: 0, parts: 1, ts: clock })
  assert.equal((await chat().messages(BOB)).find((x) => x.id === id2).att, null)
})

test('bản mã gắn id khác (phát lại) không giải mã được', async () => {
  await boot()
  const key = await keyFor(bob, BOB)
  const { iv, ct } = await encryptBytes(key, packMessage({ text: 'giả', ts: clock }), { from: BOB, to: ME, id: 'id-that' })
  await chat().onSocketMessage({ type: 'e2ee-msg', from: BOB, id: 'id-khac', iv, ct, part: 0, parts: 1, ts: clock })
  assert.equal((await chat().messages(BOB)).length, 0)
})

test('thời gian nhận bị kẹp: tin đề ngày quá khứ xa không lùi lịch', async () => {
  await boot()
  const key = await keyFor(bob, BOB)
  const id = newMessageId()
  const e = await encryptBytes(key, packMessage({ text: 'cũ', ts: 1000 }), { from: BOB, to: ME, id })
  await chat().onSocketMessage({ type: 'e2ee-msg', from: BOB, id, ...e, part: 0, parts: 1, ts: 1000 })
  const [m] = await chat().messages(BOB)
  assert.ok(m.createdAt > 1000)
})

test('khoá bạn bè đổi: cảnh báo cho tới khi chấp nhận', async () => {
  await boot()
  const other = await generateIdentity()
  friends = [{ id: BOB, name: 'Bob', publicKey: other.publicJwk }, friends[1]]
  await chat().loadFriendKeys()
  assert.equal(chat().peerInfo[BOB].changed, true)
  await chat().loadFriendKeys()
  assert.equal(chat().peerInfo[BOB].changed, true, 'làm mới danh sách không tự xoá cảnh báo')
  await chat().acceptKeyChange(BOB)
  assert.equal(chat().peerInfo[BOB].changed, false)
  await chat().loadFriendKeys()
  assert.equal(chat().peerInfo[BOB].changed, false)
})

test('nhóm: tạo, gói group-new tới từng thành viên, nhắn nhóm cần ack; thất bại khi mọi người đều undelivered', async () => {
  await boot()
  const g = await chat().createGroup('Hội', 'Tôi', [{ id: BOB, name: 'Bob' }, { id: CAT, name: 'Cat' }])
  assert.equal(sent.length, 2)
  const hdr = (await open(bob, BOB, [sent[0]])).group
  assert.equal(hdr.i, g.id)
  assert.equal((await open(bob, BOB, [sent[0]])).kind, 'group-new')
  sent.length = 0
  const m = await chat().send({ id: g.id, name: g.name }, 'chào cả nhóm', null)
  assert.equal(sent.length, 2)
  const body = await open(cat, CAT, sent.filter((f) => f.to === CAT))
  assert.equal(body.text, 'chào cả nhóm')
  assert.deepEqual(body.group, groupHeader(g))
  await chat().onSocketMessage({ type: 'e2ee-undelivered', id: m.id, reason: 'offline' })
  assert.equal((await chat().messages(g.id))[0].status, 'sent', 'còn một người có thể nhận')
  await chat().onSocketMessage({ type: 'e2ee-undelivered', id: m.id, reason: 'offline' })
  assert.equal((await chat().messages(g.id))[0].status, 'failed')
  await assert.rejects(() => chat().createGroup('x', 'Tôi', [{ id: BOB, name: 'Bob' }]), /ít nhất 2/)
})

test('rời nhóm xoá nhóm và tin trên máy', async () => {
  await boot()
  const g = await chat().createGroup('Hội', 'Tôi', [{ id: BOB, name: 'Bob' }, { id: CAT, name: 'Cat' }])
  await chat().send({ id: g.id, name: g.name }, 'a', null)
  sent.length = 0
  await chat().leaveGroup(g.id)
  assert.equal(chat().groups[g.id], undefined)
  assert.equal((await chat().messages(g.id)).length, 0)
  assert.equal(sent.length, 2, 'các thành viên còn lại được báo')
})

test('tự xoá trên máy theo thời gian và phạm vi', async () => {
  await boot()
  await chat().send({ id: BOB, name: 'Bob' }, 'cũ', null)
  clock += 2 * 3600 * 1000
  await chat().send({ id: BOB, name: 'Bob' }, 'mới', null)
  await chat().setRetention(BOB, { ttlSeconds: 3600, scope: 'all' })
  assert.deepEqual((await chat().messages(BOB)).map((m) => m.text), ['mới'])
  await chat().setRetention(BOB, null)
  assert.equal(await chat().retentionOf(BOB), null)
})

test('ghi chú theo máy (ghim) và xoá một tin', async () => {
  await boot()
  const m = await chat().send({ id: BOB, name: 'Bob' }, 'a', null)
  await chat().metaSet(`pin:${BOB}`, [m.id])
  assert.deepEqual(await chat().metaGet(`pin:${BOB}`), [m.id])
  await chat().metaSet(`pin:${BOB}`, null)
  assert.equal(await chat().metaGet(`pin:${BOB}`), null)
  await chat().deleteMessage(m.id)
  assert.equal((await chat().messages(BOB)).length, 0)
})

test('previews: tin cuối mỗi cuộc trò chuyện', async () => {
  await boot()
  await chat().send({ id: BOB, name: 'Bob' }, 'một', null)
  clock += 10
  await chat().send({ id: BOB, name: 'Bob' }, 'hai', null)
  const p = await chat().previews()
  assert.equal(p[BOB].text, 'hai')
  assert.equal(p[BOB].mine, true)
})

test('frameParts: cắt theo 1.000.000 ký tự, tối đa 8 phần', () => {
  const ct = 'a'.repeat(LIMITS.PART_CHARS * 2 + 5)
  const frames = frameParts('u', 'id', 'iv', ct, 7)
  assert.equal(frames.length, 3)
  assert.deepEqual(frames.map((f) => f.part), [0, 1, 2])
  assert.ok(frames.every((f) => f.parts === 3 && f.type === 'e2ee-msg' && f.ts === 7))
  assert.equal(frames.map((f) => f.ct).join(''), ct)
  assert.equal(frameParts('u', 'id', 'iv', 'a'.repeat(LIMITS.PART_CHARS * 8 + 1), 7), null)
})
