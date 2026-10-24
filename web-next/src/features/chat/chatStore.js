// End-to-end encrypted friend chat (docs/MA_HOA_2_DAU.md; port of e2ee/chat.js, zustand instead of Pinia).
//
// Messages are encrypted on this device with a key only the two friends can derive, relayed by the server over the
// signaling WebSocket to a friend who is ONLINE (the server stores nothing; an offline friend means "not sent"), and
// kept only in this device's IndexedDB. Admin support (Phản hồi) is separate and plaintext.
//
// The wire format is shared with the Flutter app and must not change: e2ee-msg {to,id,iv,ct,part,parts,ts} (<= 40 parts
// of 1,000,000 ciphertext characters), e2ee-ack {to,id}, e2ee-undelivered {id,reason}.
//
// Everything that touches the browser or the network goes through `deps`, so the tests can run this store against an
// in-memory database and a fake socket.
import { create } from 'zustand'
import { api } from '../../lib/api'
import { ALLOWED_IMAGE_TYPES, IMAGE_ONLY_MESSAGE, anonymousName, scrubImageMetadata, MAX_ATTACHMENT_BYTES } from '../../lib/attachments'
import { useAuthStore } from '../../lib/authStore'
import * as idb from '../../lib/e2ee/db'
import { decryptBytes, deriveSessionKey, encryptBytes, fingerprint, generateIdentity, newMessageId, packMessage, samePublicKey, unpackMessage } from '../../lib/e2ee/crypto'
import { groupFromHeader, groupHeader, isGroupId, GROUP_PREFIX } from '../../lib/e2ee/groups'
import { clampReceivedTs } from '../../lib/e2ee/timestamps'
import { useNotifyStore } from '../../lib/notifyStore'
import { setChatHandler, transport } from '../calls/transport'

export const REASONS = {
  offline: 'Bạn bè đang offline, tin nhắn chưa được gửi. Hãy gửi lại khi họ trực tuyến.',
  'not-friend': 'Không còn là bạn bè nên không gửi được.',
  invalid: 'Tin nhắn không hợp lệ.',
  'no-key': 'Bạn bè chưa bật mã hoá đầu cuối (chưa mở phiên bản mới), chưa gửi được.',
  'no-socket': 'Mất kết nối tới máy chủ, thử lại sau.',
  timeout: 'Không nhận được xác nhận, tin nhắn có thể chưa tới.',
}
export const reasonText = (reason) => REASONS[reason] || 'Chưa gửi được.'

export const LIMITS = {
  ACK_WAIT_MS: 15000,
  PART_CHARS: 1000000, // ciphertext characters per WebSocket frame (the server allows 2 M)
  MAX_PARTS: 40,
  PART_WAIT_MS: 60000,
}

// Replaceable in tests.
export const deps = {
  idb,
  api,
  transport,
  me: () => useAuthStore.getState().user?.id,
  notify: () => useNotifyStore.getState(),
  now: () => Date.now(),
}

let db = null // IndexedDB for the current account
let identity = null // { privateKey, publicJwk }
let userId = null
const sessionKeys = new Map() // friendId -> { jwk, key }
const ackTimers = new Map() // message id -> timeout
const incoming = new Map() // message id -> parts received so far
const lastShotNotice = new Map() // friend id -> when we last warned them about a screenshot
const fanOut = new Map() // group message id -> recipients that may still receive it (0 and no ack = failed)

const plainCopy = (o) => JSON.parse(JSON.stringify(o)) // IndexedDB cannot clone every object a store may hold

// Splits a ciphertext into the frames of one message.
export function frameParts(to, id, iv, ct, ts) {
  const parts = Math.max(1, Math.ceil(ct.length / LIMITS.PART_CHARS))
  if (parts > LIMITS.MAX_PARTS) return null
  const out = []
  for (let i = 0; i < parts; i++) out.push({ type: 'e2ee-msg', to, id, iv, ct: ct.slice(i * LIMITS.PART_CHARS, (i + 1) * LIMITS.PART_CHARS), part: i, parts, ts })
  return out
}

export const useChatStore = create((set, get) => {
  const send = (frame) => deps.transport.send(frame)
  const socketUp = () => deps.transport.ready()
  const ack = (to, id) => send({ type: 'e2ee-ack', to, id })
  const bump = () => set((s) => ({ tick: s.tick + 1 }))

  async function session(friendId) {
    const jwk = get().friendKeys[friendId]
    if (!jwk) return null
    const cached = sessionKeys.get(friendId)
    if (cached && samePublicKey(cached.jwk, jwk)) return cached.key
    const key = await deriveSessionKey(identity.privateKey, jwk, userId, friendId)
    sessionKeys.set(friendId, { jwk, key })
    return key
  }

  async function setStatus(id, status, reason) {
    const m = await deps.idb.get(db, 'messages', id)
    if (!m) return
    if (status !== 'sent') {
      clearTimeout(ackTimers.get(id))
      ackTimers.delete(id)
    }
    // A late timeout must not overwrite a delivery that already happened.
    if (m.status === 'delivered' && status === 'failed') return
    await deps.idb.put(db, 'messages', { ...m, status, reason: status === 'failed' ? reason : undefined })
    bump()
  }

  function waitForAck(id, onTimeout) {
    ackTimers.set(
      id,
      setTimeout(() => {
        onTimeout?.()
        setStatus(id, 'failed', 'timeout')
      }, LIMITS.ACK_WAIT_MS),
    )
  }

  // Puts the parts of one message back together; returns it once complete, else null.
  function assemble(frame) {
    const total = frame.parts || 1
    if (total === 1) return frame
    let entry = incoming.get(frame.id)
    if (!entry) {
      entry = { parts: new Array(total), got: 0, timer: setTimeout(() => incoming.delete(frame.id), LIMITS.PART_WAIT_MS) }
      incoming.set(frame.id, entry)
    }
    if (entry.parts.length !== total || entry.parts[frame.part] !== undefined) return null
    entry.parts[frame.part] = frame.ct
    entry.got++
    if (entry.got < total) return null
    clearTimeout(entry.timer)
    incoming.delete(frame.id)
    return { ...frame, ct: entry.parts.join('') }
  }

  // Encrypts and relays an already stored message (also used for "Gửi lại").
  async function transmit(friendId, msg, fileBytes, att) {
    const fail = (reason) => setStatus(msg.id, 'failed', reason)
    if (isGroupId(friendId)) return transmitGroup(msg, fileBytes, att)
    const key = await session(friendId)
    if (!key) return fail('no-key')
    if (!socketUp()) return fail('no-socket')
    if (msg.att && !fileBytes) fileBytes = new Uint8Array(await msg.att.blob.arrayBuffer())
    if (msg.att && !att) att = { name: msg.att.name, type: msg.att.type, size: msg.att.size }
    const plain = packMessage({ text: msg.text, ts: msg.createdAt, att, kind: msg.sys === 'screenshot-sent' ? 'screenshot' : null }, fileBytes)
    const { iv, ct } = await encryptBytes(key, plain, { from: userId, to: friendId, id: msg.id })
    const frames = frameParts(friendId, msg.id, iv, ct, msg.createdAt)
    if (!frames) return fail('invalid')
    for (const f of frames) send(f)
    await setStatus(msg.id, 'sent')
    waitForAck(msg.id)
  }

  // Encrypts `plain` for every member except me and relays it. Returns how many members it was handed to the socket for.
  async function fanOutFrames(g, id, plain, ts, wantAck = true) {
    if (!socketUp()) return 0
    let sent = 0
    for (const member of g.members) {
      if (member.id === userId) continue
      const key = await session(member.id)
      if (!key) continue // not my friend (no key): the relay would refuse it anyway
      const { iv, ct } = await encryptBytes(key, plain, { from: userId, to: member.id, id })
      const frames = frameParts(member.id, id, iv, ct, ts)
      if (!frames) continue
      for (const f of frames) send(f)
      sent++
    }
    if (wantAck && sent > 0) fanOut.set(id, sent)
    return sent
  }

  // A message with no text, only carrying the group (creation, rename, somebody left).
  function fanOutKind(g, kind) {
    const ts = deps.now()
    return fanOutFrames(g, newMessageId(), packMessage({ text: '', ts, kind, group: groupHeader(g) }), ts, false)
  }

  async function transmitGroup(msg, fileBytes, att) {
    const g = get().groups[msg.peerId]
    if (!g) return setStatus(msg.id, 'failed', 'invalid')
    if (!socketUp()) return setStatus(msg.id, 'failed', 'no-socket')
    if (msg.att && !fileBytes) fileBytes = new Uint8Array(await msg.att.blob.arrayBuffer())
    if (msg.att && !att) att = { name: msg.att.name, type: msg.att.type, size: msg.att.size }
    const plain = packMessage({ text: msg.text, ts: msg.createdAt, att, group: groupHeader(g) }, fileBytes)
    const sent = await fanOutFrames(g, msg.id, plain, msg.createdAt)
    if (sent === 0) return setStatus(msg.id, 'failed', 'no-key')
    await setStatus(msg.id, 'sent')
    waitForAck(msg.id, () => fanOut.delete(msg.id))
  }

  async function saveGroup(g) {
    const plain = plainCopy(g)
    set((s) => ({ groups: { ...s.groups, [g.id]: plain } }))
    await deps.idb.put(db, 'meta', { id: `group:${g.id}`, value: plain })
  }

  const storedImage = (att, file) =>
    att && file.length && ALLOWED_IMAGE_TYPES.includes(att.type)
      ? {
          name: String(att.name || 'tep-dinh-kem').slice(0, 200),
          type: String(att.type),
          size: file.length,
          isImage: true,
          blob: new Blob([file], { type: String(att.type) }),
        }
      : null

  // A message (or creation / rename / "left" notice) of a group chat from `msg.from`.
  async function handleGroupMessage(msg, { text, ts, att, file, kind, group }) {
    const inc = groupFromHeader(group)
    if (!inc) return
    const known = get().groups[inc.id]
    const notify = deps.notify()
    if (kind === 'group-removed') {
      // The creator removed me: forget the group (its messages go with it).
      if (!known || known.creatorId !== msg.from || inc.members.some((x) => x.id === userId)) return
      ack(msg.from, msg.id)
      const name = known.name
      await get().leaveGroup(known.id, false)
      notify.receive({ source: 'friend', from: known.id, fromName: name, preview: 'Bạn đã bị xoá khỏi nhóm', hasAttachment: false })
      return
    }
    if (kind === 'group-left') {
      // The sender is leaving: no longer in the list the message carries, so it must have been a member before.
      if (!known || !known.members.some((x) => x.id === msg.from) || inc.members.some((x) => x.id === msg.from)) return
    } else if (!inc.members.some((x) => x.id === msg.from) || !inc.members.some((x) => x.id === userId)) {
      return // only a member may speak in the group, and the group must include me
    }
    if (known && known.creatorId !== inc.creatorId) return // the creator of an existing group cannot be changed
    // Only the creator changes name / members; a member leaving removes only themselves. A newer header carried by an
    // ordinary message of another member is not trusted.
    if (!known) await saveGroup(inc)
    else if (inc.updatedAt > known.updatedAt) {
      const leftOk = kind === 'group-left' && inc.members.length === known.members.length - 1
      if (msg.from === inc.creatorId || leftOk) await saveGroup(inc)
    }
    const g = get().groups[inc.id]
    ack(msg.from, msg.id)
    const who = g.members.find((x) => x.id === msg.from)?.name || msg.fromName || 'Thành viên'
    if (kind === 'group-new' || kind === 'group-left') {
      bump()
      if (kind === 'group-new' && !known) notify.receive({ source: 'friend', from: g.id, fromName: g.name, preview: `${who} đã thêm bạn vào nhóm`, hasAttachment: false })
      return
    }
    const stored = storedImage(att, file)
    await deps.idb.put(db, 'messages', { id: msg.id, peerId: g.id, mine: false, text, att: stored, createdAt: clampReceivedTs(ts), status: 'delivered', fromId: msg.from })
    bump()
    notify.receive({ source: 'friend', from: g.id, fromName: g.name, preview: `${who}: ${text || 'Đã gửi một tệp đính kèm'}`, hasAttachment: !!stored })
    await get().bumpUnread(g.id)
  }

  // Frames from the WebSocket (routed here by the call store through ./transport).
  async function onSocketMessage(msg) {
    if (!db) return
    if (msg.type === 'e2ee-ack') {
      fanOut.delete(msg.id)
      return setStatus(msg.id, 'delivered')
    }
    if (msg.type === 'e2ee-undelivered') {
      // A group message goes to several members: it only failed when NONE of them can get it.
      const left = fanOut.get(msg.id)
      if (left > 1) {
        fanOut.set(msg.id, left - 1)
        return
      }
      fanOut.delete(msg.id)
      return setStatus(msg.id, 'failed', msg.reason)
    }
    if (msg.type !== 'e2ee-msg') return
    msg = assemble(msg)
    if (!msg) return
    try {
      if (await deps.idb.get(db, 'messages', msg.id)) return // duplicate
      // Fetch the sender's current key if we do not know it yet (new friend / new device).
      if (!get().friendKeys[msg.from]) await get().loadFriendKeys()
      let key = await session(msg.from)
      if (!key) return
      const frame = { from: msg.from, to: userId, id: msg.id }
      let plain
      try {
        plain = await decryptBytes(key, msg, frame)
      } catch {
        await get().loadFriendKeys() // their key may have changed; retry once with a fresh one
        key = await session(msg.from)
        plain = await decryptBytes(key, msg, frame)
      }
      const { text, ts, att, file, kind, group } = unpackMessage(plain)
      if (group) return await handleGroupMessage(msg, { text, ts, att, file, kind, group })
      const notify = deps.notify()
      if (kind === 'screenshot') {
        // The friend took a screenshot of this conversation: show a notice line and alert.
        await deps.idb.put(db, 'messages', { id: msg.id, peerId: msg.from, mine: false, text: '', att: null, sys: 'screenshot', createdAt: clampReceivedTs(ts), status: 'delivered' })
        ack(msg.from, msg.id)
        bump()
        notify.receive({ source: 'friend', from: msg.from, fromName: msg.fromName, preview: 'đã chụp màn hình cuộc trò chuyện với bạn', hasAttachment: false })
        await get().bumpUnread(msg.from)
        return
      }
      // Only pictures are accepted from a friend (a modified client could send anything).
      const stored = storedImage(att, file)
      await deps.idb.put(db, 'messages', { id: msg.id, peerId: msg.from, mine: false, text, att: stored, createdAt: clampReceivedTs(ts), status: 'delivered' })
      ack(msg.from, msg.id)
      bump()
      notify.receive({ source: 'friend', from: msg.from, fromName: msg.fromName, preview: text || 'Đã gửi một tệp đính kèm', hasAttachment: !!stored })
      await get().bumpUnread(msg.from)
    } catch {
      // Never log the content or keys: only that a frame could not be read.
      console.warn('e2ee: could not read an incoming message')
    }
  }
  setChatHandler(onSocketMessage)

  return {
    ready: false,
    error: '',
    tick: 0, // bumps whenever stored messages change (views reload from the DB)
    myFingerprint: '',
    peerInfo: {}, // friendId -> { fingerprint, changed }
    friendKeys: {}, // friendId -> public JWK from the server
    groups: {}, // group id -> { id, name, creatorId, updatedAt, members: [{ id, name }] } (kept on this device only)

    onSocketMessage,
    reasonText,
    userId: () => userId,

    // Opens this account's local store, creates the key pair on first use and publishes the public key. Safe to repeat.
    async init() {
      const id = deps.me()
      if (!id || (get().ready && userId === id)) return
      try {
        get().reset()
        db = await deps.idb.openChatDb(id)
        userId = id
        const saved = await deps.idb.get(db, 'identity', 'self')
        identity = saved || { id: 'self', ...(await generateIdentity()) }
        if (!saved) await deps.idb.put(db, 'identity', identity)
        set({ myFingerprint: await fingerprint(identity.publicJwk) })
        // Publish if the server has no key or a different one (new device / cleared storage).
        const remote = (await deps.api.get('/me/e2ee-key')).publicKey
        if (!samePublicKey(remote, identity.publicJwk)) await deps.api.put('/me/e2ee-key', { publicKey: identity.publicJwk })
        await get().restoreUnread()
        await get().restoreGroups()
        set({ ready: true, error: '' })
        await get().loadFriendKeys()
        await get().applyRetentionAll()
      } catch {
        set({ ready: false, error: 'Không khởi tạo được mã hoá đầu cuối trên thiết bị này.' })
        console.error('e2ee init failed')
      }
    },

    reset() {
      db?.close?.()
      db = null
      identity = null
      userId = null
      sessionKeys.clear()
      for (const t of ackTimers.values()) clearTimeout(t)
      ackTimers.clear()
      for (const e of incoming.values()) clearTimeout(e.timer)
      incoming.clear()
      fanOut.clear()
      set({ ready: false, peerInfo: {}, friendKeys: {}, groups: {}, myFingerprint: '' })
    },

    async loadFriendKeys() {
      const res = await deps.api.get('/me/friends')
      await get().rememberFriends(res.friends)
    },

    // Called with the friend list from the server: remembers each friend's public key and flags a key that changed since
    // we last saw it.
    async rememberFriends(friends) {
      if (!db) return
      const keys = { ...get().friendKeys }
      const info = { ...get().peerInfo }
      for (const f of friends) {
        if (!f.publicKey) {
          delete keys[f.id]
          continue
        }
        keys[f.id] = f.publicKey
        const known = await deps.idb.get(db, 'peers', f.id)
        const fp = await fingerprint(f.publicKey)
        if (!known) {
          await deps.idb.put(db, 'peers', { id: f.id, jwk: f.publicKey, fingerprint: fp, changed: false })
          info[f.id] = { fingerprint: fp, changed: false }
        } else if (!samePublicKey(known.jwk, f.publicKey)) {
          await deps.idb.put(db, 'peers', { id: f.id, jwk: f.publicKey, fingerprint: fp, changed: true })
          sessionKeys.delete(f.id)
          info[f.id] = { fingerprint: fp, changed: true }
        } else {
          info[f.id] = { fingerprint: fp, changed: !!known.changed }
        }
      }
      set({ friendKeys: keys, peerInfo: info })
    },

    // The user has seen the "key changed" warning: trust the key the server shows NOW. The stored key must be replaced
    // too, otherwise the next refresh of the friend list sees "different from the stored one" and warns again.
    async acceptKeyChange(friendId) {
      const current = get().friendKeys[friendId]
      const known = await deps.idb.get(db, 'peers', friendId)
      if (current) {
        const jwk = { kty: current.kty, crv: current.crv, x: current.x, y: current.y }
        const fp = await fingerprint(jwk)
        await deps.idb.put(db, 'peers', { id: friendId, jwk, fingerprint: fp, changed: false })
        set((s) => ({ peerInfo: { ...s.peerInfo, [friendId]: { fingerprint: fp, changed: false } } }))
        sessionKeys.delete(friendId)
      } else if (known) {
        await deps.idb.put(db, 'peers', { ...known, changed: false })
        set((s) => (s.peerInfo[friendId] ? { peerInfo: { ...s.peerInfo, [friendId]: { ...s.peerInfo[friendId], changed: false } } } : s))
      }
    },

    async messages(friendId) {
      if (!db) return []
      await get().applyRetention(friendId) // messages that expired while the app stayed open
      const list = await deps.idb.messagesOf(db, friendId)
      return list.sort((a, b) => a.createdAt - b.createdAt)
    },

    // Last message per friend (for the list preview and ordering).
    async previews() {
      if (!db) return {}
      const out = {}
      for (const m of await deps.idb.getAll(db, 'messages')) {
        if (!out[m.peerId] || m.createdAt > out[m.peerId].at) {
          out[m.peerId] = { at: m.createdAt, text: m.sys ? '📷 Chụp màn hình cuộc trò chuyện' : m.text || (m.att ? `[Đính kèm] ${m.att.name}` : ''), from: m.fromId || null, mine: !!m.mine }
        }
      }
      return out
    },

    // This person just took (or tried to take) a screenshot with the conversation open: tell the friend, end-to-end
    // encrypted like any message, and leave a visible line on both sides. Best effort; at most once per 20 s.
    async notifyScreenshot(friend) {
      if (!get().ready || !friend?.id || !get().friendKeys[friend.id]) return
      const last = lastShotNotice.get(friend.id) || 0
      if (deps.now() - last < 20000) return
      lastShotNotice.set(friend.id, deps.now())
      const msg = { id: newMessageId(), peerId: friend.id, mine: true, text: '', att: null, sys: 'screenshot-sent', createdAt: deps.now(), status: 'sending' }
      await deps.idb.put(db, 'messages', msg)
      bump()
      await transmit(friend.id, msg, null, null)
    },

    // Sends `text` and/or one `file` to `friend` ({id, name}). Returns the stored message.
    async send(friend, text, file) {
      if (!get().ready) throw new Error('Mã hoá đầu cuối chưa sẵn sàng trên thiết bị này.')
      const id = newMessageId()
      let fileBytes = null
      let att = null
      let stored = null
      if (file) {
        if (!ALLOWED_IMAGE_TYPES.includes(file.type)) throw new Error(IMAGE_ONLY_MESSAGE)
        if (file.size > MAX_ATTACHMENT_BYTES) throw new Error('Tệp quá lớn (tối đa 25 MB)')
        // The picture is redrawn (no EXIF/GPS/device/time) and renamed before it is encrypted.
        const clean = await scrubImageMetadata(file)
        const name = anonymousName(clean.type)
        fileBytes = new Uint8Array(await clean.arrayBuffer())
        att = { name, type: clean.type || 'application/octet-stream', size: fileBytes.length }
        stored = { ...att, isImage: att.type.startsWith('image/') && att.type !== 'image/svg+xml', blob: new Blob([fileBytes], { type: att.type }) }
      }
      const msg = { id, peerId: friend.id, mine: true, text: text || '', att: stored, createdAt: deps.now(), status: 'sending', ...(isGroupId(friend.id) ? { fromId: userId } : {}) }
      await deps.idb.put(db, 'messages', msg)
      bump()
      await transmit(friend.id, msg, fileBytes, att)
      return msg
    },

    async retry(message) {
      if (!db || !message.mine) return
      const m = await deps.idb.get(db, 'messages', message.id)
      if (!m) return
      await setStatus(m.id, 'sending')
      await transmit(m.peerId, { ...m, status: 'sending' })
    },

    // ---- group chats ----
    async restoreGroups() {
      const groups = {}
      for (const m of await deps.idb.getAll(db, 'meta')) {
        if (!m.id.startsWith(`group:${GROUP_PREFIX}`)) continue
        const g = groupFromHeader(groupHeader(m.value))
        if (g) groups[g.id] = g
      }
      set({ groups })
    },

    // Creates the group on this device and tells every member. `others` = [{ id, name }] of friends (the relay only
    // carries messages between friends).
    async createGroup(name, myName, others) {
      if (!get().ready) throw new Error('Mã hoá đầu cuối chưa sẵn sàng trên thiết bị này.')
      const n = String(name || '').trim()
      if (!n) throw new Error('Nhập tên nhóm.')
      const seen = new Set([userId])
      const members = [{ id: userId, name: myName || 'Thành viên' }]
      for (const o of others) if (!seen.has(o.id)) { seen.add(o.id); members.push({ id: o.id, name: o.name }) }
      if (members.length < 3) throw new Error('Chọn ít nhất 2 bạn bè để tạo nhóm.')
      if (members.length > 50) throw new Error('Nhóm tối đa 50 người.')
      const g = { id: `${GROUP_PREFIX}${newMessageId()}`, name: n.slice(0, 60), creatorId: userId, updatedAt: deps.now(), members }
      await saveGroup(g)
      bump()
      await fanOutKind(g, 'group-new')
      return get().groups[g.id]
    },

    async renameGroup(groupId, name) {
      const g = get().groups[groupId]
      const n = String(name || '').trim()
      if (!g || !n || g.creatorId !== userId) return // only the creator renames
      const next = { ...plainCopy(g), name: n.slice(0, 60), updatedAt: deps.now() }
      await saveGroup(next)
      bump()
      await fanOutKind(next, 'group-new')
    },

    // Creator only: adds friends ([{ id, name }]). Everybody (the newcomers included) gets the updated group; the
    // newcomers see the messages sent from now on, not the earlier ones.
    async addGroupMembers(groupId, added) {
      const g = get().groups[groupId]
      if (!g || g.creatorId !== userId) return
      const have = new Set(g.members.map((m) => m.id))
      const fresh = added.filter((a) => !have.has(a.id) && have.add(a.id))
      if (!fresh.length) return
      if (g.members.length + fresh.length > 50) throw new Error('Nhóm tối đa 50 người.')
      const next = { ...plainCopy(g), members: [...g.members.map((m) => ({ id: m.id, name: m.name })), ...fresh.map((a) => ({ id: a.id, name: a.name }))], updatedAt: deps.now() }
      await saveGroup(next)
      bump()
      await fanOutKind(next, 'group-new')
    },

    // Creator only: removes a member. The others get the updated group; the removed person is told and drops the group.
    async removeGroupMember(groupId, memberId) {
      const g = get().groups[groupId]
      if (!g || g.creatorId !== userId || memberId === userId || !g.members.some((m) => m.id === memberId)) return
      const next = { ...plainCopy(g), members: g.members.filter((m) => m.id !== memberId).map((m) => ({ id: m.id, name: m.name })), updatedAt: deps.now() }
      if (next.members.length < 2) throw new Error('Nhóm cần ít nhất 2 người.')
      await saveGroup(next)
      bump()
      // the removed member is told with the group as it is now (without them) and kind "group-removed"
      const key = await session(memberId)
      if (key && socketUp()) {
        const ts = deps.now()
        const id = newMessageId()
        const { iv, ct } = await encryptBytes(key, packMessage({ text: '', ts, kind: 'group-removed', group: groupHeader(next) }), { from: userId, to: memberId, id })
        send({ type: 'e2ee-msg', to: memberId, id, iv, ct, part: 0, parts: 1, ts })
      }
      await fanOutKind(next, 'group-new')
    },

    // Leaves the group: the others are told, then it is removed from this device together with its messages.
    async leaveGroup(groupId, notify = true) {
      const g = get().groups[groupId]
      if (g && notify) {
        const rest = { ...plainCopy(g), members: g.members.filter((m) => m.id !== userId), updatedAt: deps.now() }
        if (rest.members.length >= 2) await fanOutKind(rest, 'group-left')
      }
      await get().deleteConversation(groupId)
      set((s) => {
        const { [groupId]: _gone, ...groups } = s.groups
        return { groups }
      })
      await deps.idb.del(db, 'meta', `group:${groupId}`)
      await deps.idb.del(db, 'meta', `unread:${groupId}`)
      await deps.idb.del(db, 'meta', `pin:${groupId}`)
      useNotifyStore.setState((s) => ({ unread: { ...s.unread, [`friend:${groupId}`]: 0 } }))
      bump()
    },

    // The name to show for member `id` of group `g` on this device.
    memberName(g, id) {
      if (id === userId) return 'Bạn'
      return g?.members.find((m) => m.id === id)?.name || 'Thành viên'
    },

    // ---- unread counters, kept on this device ----
    async bumpUnread(friendId) {
      await deps.idb.put(db, 'meta', { id: `unread:${friendId}`, value: deps.notify().unread[`friend:${friendId}`] || 0 })
    },
    async restoreUnread() {
      const restored = {}
      for (const m of await deps.idb.getAll(db, 'meta')) if (m.id.startsWith('unread:') && m.value > 0) restored[`friend:${m.id.slice(7)}`] = m.value
      useNotifyStore.setState((s) => ({ unread: { ...s.unread, ...restored } }))
    },
    async markRead(friendId) {
      if (db) await deps.idb.del(db, 'meta', `unread:${friendId}`)
    },

    // ---- per-friend auto-delete, applied on this device ----
    async retentionOf(friendId) {
      return db ? (await deps.idb.get(db, 'meta', `retention:${friendId}`))?.value || null : null
    },
    async setRetention(friendId, rule) {
      if (rule) await deps.idb.put(db, 'meta', { id: `retention:${friendId}`, value: rule })
      else await deps.idb.del(db, 'meta', `retention:${friendId}`)
      await get().applyRetention(friendId)
    },
    async applyRetention(friendId) {
      const rule = await get().retentionOf(friendId)
      if (!rule) return
      const cutoff = deps.now() - rule.ttlSeconds * 1000
      let changed = false
      for (const m of await deps.idb.messagesOf(db, friendId)) {
        if (m.createdAt >= cutoff) continue
        if (rule.scope === 'images' && !m.att?.isImage) continue
        await deps.idb.del(db, 'messages', m.id)
        changed = true
      }
      if (changed) bump()
    },
    async applyRetentionAll() {
      for (const m of await deps.idb.getAll(db, 'meta')) if (m.id.startsWith('retention:')) await get().applyRetention(m.id.slice(10))
    },
    // Per-device notes kept next to the messages (pins, edited decodings, reports). Never uploaded.
    async metaGet(key) {
      return db ? (await deps.idb.get(db, 'meta', key))?.value ?? null : null
    },
    async metaSet(key, value) {
      if (!db) return
      if (value == null) await deps.idb.del(db, 'meta', key)
      else await deps.idb.put(db, 'meta', { id: key, value })
    },
    // Deletes one message from THIS device (the friend keeps theirs).
    async deleteMessage(id) {
      if (!db) return
      await deps.idb.del(db, 'messages', id)
      await deps.idb.del(db, 'meta', `decode:${id}`)
      bump()
    },
    // Deletes the whole conversation with this friend from THIS device (the friend keeps theirs).
    async deleteConversation(friendId) {
      if (!db) return
      for (const m of await deps.idb.messagesOf(db, friendId)) await deps.idb.del(db, 'messages', m.id)
      bump()
    },
  }
})
