// End-to-end encrypted friend chat (docs/MA_HOA_2_DAU.md).
//
// Messages are encrypted on this device with a key only the two friends can
// derive, relayed by the server over the signaling WebSocket to a friend who is
// ONLINE (the server stores nothing; an offline friend means "not sent"), and
// kept only in this device's IndexedDB. Admin support (Phản hồi) is separate.
import { defineStore } from 'pinia'
import { api } from '../api'
import { ALLOWED_IMAGE_TYPES, IMAGE_ONLY_MESSAGE, anonymousName, scrubImageMetadata, MAX_ATTACHMENT_BYTES } from '../attachments'
import { useAuthStore } from '../stores/auth'
import { useCallStore } from '../stores/call'
import { useNotifyStore } from '../stores/notify'
import { decryptBytes, deriveSessionKey, encryptBytes, fingerprint, generateIdentity, newMessageId, packMessage, samePublicKey, unpackMessage } from './crypto'
import { del, get, getAll, messagesOf, openChatDb, put } from './db'
import { groupFromHeader, groupHeader, isGroupId, GROUP_PREFIX } from './groups'

const REASONS = {
  offline: 'Bạn bè đang offline, tin nhắn chưa được gửi. Hãy gửi lại khi họ trực tuyến.',
  'not-friend': 'Không còn là bạn bè nên không gửi được.',
  invalid: 'Tin nhắn không hợp lệ.',
  'no-key': 'Bạn bè chưa bật mã hoá 2 đầu (chưa mở phiên bản mới), chưa gửi được.',
  'no-socket': 'Mất kết nối tới máy chủ, thử lại sau.',
  timeout: 'Không nhận được xác nhận, tin nhắn có thể chưa tới.',
}
const ACK_WAIT_MS = 15000
const PART_CHARS = 1000000 // ciphertext characters per WebSocket frame (the server allows 2 M)
const MAX_PARTS = 8
const PART_WAIT_MS = 60000

let db = null // IndexedDB for the current account
let identity = null // { privateKey, publicJwk }
let userId = null
const sessionKeys = new Map() // friendId -> { jwkKey, key }
const ackTimers = new Map() // message id -> timeout
const incoming = new Map() // message id -> parts received so far
const lastShotNotice = new Map() // friend id -> when we last warned them about a screenshot
const fanOut = new Map() // group message id -> recipients that may still receive it (0 and no ack = failed)

export const useChatStore = defineStore('e2ee-chat', {
  state: () => ({
    ready: false,
    error: '',
    tick: 0, // bumps whenever stored messages change (views reload from the DB)
    myFingerprint: '',
    peerInfo: {}, // friendId -> { fingerprint, changed }
    friendKeys: {}, // friendId -> public JWK from the server
    groups: {}, // group id -> { id, name, creatorId, updatedAt, members: [{ id, name }] } (kept on this device only)
  }),

  actions: {
    // Opens this account's local store, creates the key pair on first use and
    // publishes the public key. Safe to call repeatedly.
    async init() {
      const auth = useAuthStore()
      const id = auth.user?.id
      if (!id || (this.ready && userId === id)) return
      try {
        this.reset()
        db = await openChatDb(id)
        userId = id
        const saved = await get(db, 'identity', 'self')
        identity = saved || { id: 'self', ...(await generateIdentity()) }
        if (!saved) await put(db, 'identity', identity)
        this.myFingerprint = await fingerprint(identity.publicJwk)
        // Publish if the server has no key or a different one (new device / cleared storage).
        const remote = (await api.get('/me/e2ee-key')).publicKey
        if (!samePublicKey(remote, identity.publicJwk)) await api.put('/me/e2ee-key', { publicKey: identity.publicJwk })
        await this.restoreUnread()
        await this.restoreGroups()
        this.ready = true
        this.error = ''
        await this.loadFriendKeys()
        await this.applyRetentionAll()
      } catch (err) {
        this.ready = false
        this.error = 'Không khởi tạo được mã hoá 2 đầu trên thiết bị này.'
        console.error('e2ee init failed', err)
      }
    },

    reset() {
      db?.close()
      db = null
      identity = null
      userId = null
      sessionKeys.clear()
      for (const t of ackTimers.values()) clearTimeout(t)
      ackTimers.clear()
      this.ready = false
      this.peerInfo = {}
      this.friendKeys = {}
      this.groups = {}
      fanOut.clear()
    },

    async loadFriendKeys() {
      const res = await api.get('/me/friends')
      await this.rememberFriends(res.friends)
    },

    // Called with the friend list from the server: remembers each friend's public
    // key and flags a key that changed since we last saw it.
    async rememberFriends(friends) {
      if (!db) return
      for (const f of friends) {
        if (!f.publicKey) {
          delete this.friendKeys[f.id]
          continue
        }
        this.friendKeys[f.id] = f.publicKey
        const known = await get(db, 'peers', f.id)
        const fp = await fingerprint(f.publicKey)
        if (!known) {
          await put(db, 'peers', { id: f.id, jwk: f.publicKey, fingerprint: fp, changed: false })
          this.peerInfo[f.id] = { fingerprint: fp, changed: false }
        } else if (!samePublicKey(known.jwk, f.publicKey)) {
          await put(db, 'peers', { id: f.id, jwk: f.publicKey, fingerprint: fp, changed: true })
          sessionKeys.delete(f.id)
          this.peerInfo[f.id] = { fingerprint: fp, changed: true }
        } else {
          this.peerInfo[f.id] = { fingerprint: fp, changed: !!known.changed }
        }
      }
    },

    // The user has seen the "key changed" warning for this friend: trust the key the server shows NOW. The stored key
    // must be replaced too, otherwise the next refresh of the friend list still sees "different from the stored one"
    // and shows the warning again.
    async acceptKeyChange(friendId) {
      const current = this.friendKeys[friendId]
      const known = await get(db, 'peers', friendId)
      if (current) {
        // A plain copy: `current` is a reactive proxy and IndexedDB cannot clone a proxy.
        const jwk = { kty: current.kty, crv: current.crv, x: current.x, y: current.y }
        const fp = await fingerprint(jwk)
        await put(db, 'peers', { id: friendId, jwk, fingerprint: fp, changed: false })
        this.peerInfo[friendId] = { fingerprint: fp, changed: false }
        sessionKeys.delete(friendId)
      } else if (known) {
        await put(db, 'peers', { ...known, changed: false })
        if (this.peerInfo[friendId]) this.peerInfo[friendId].changed = false
      }
    },

    async _session(friendId) {
      const jwk = this.friendKeys[friendId]
      if (!jwk) return null
      const cached = sessionKeys.get(friendId)
      if (cached && samePublicKey(cached.jwk, jwk)) return cached.key
      const key = await deriveSessionKey(identity.privateKey, jwk, userId, friendId)
      sessionKeys.set(friendId, { jwk, key })
      return key
    },

    async messages(friendId) {
      if (!db) return []
      await this.applyRetention(friendId) // messages that expired while the app stayed open
      const list = await messagesOf(db, friendId)
      return list.sort((a, b) => a.createdAt - b.createdAt)
    },

    // Last message per friend (for the list preview and ordering).
    async previews() {
      if (!db) return {}
      const out = {}
      for (const m of await getAll(db, 'messages')) {
        if (!out[m.peerId] || m.createdAt > out[m.peerId].at) {
          out[m.peerId] = { at: m.createdAt, text: m.sys ? '📷 Chụp màn hình cuộc trò chuyện' : m.text || (m.att ? `[Đính kèm] ${m.att.name}` : ''), from: m.fromId || null, mine: !!m.mine }
        }
      }
      return out
    },

    // This person just took (or tried to take) a screenshot with the conversation open: tell
    // the friend, end-to-end encrypted like any message, and leave a visible line on both
    // sides. Detection is by the screenshot shortcut (screenshotGuard.js), so it is best effort:
    // phone hardware buttons and other devices cannot be seen. Sent at most once per 20 s.
    async notifyScreenshot(friend) {
      if (!this.ready || !friend?.id || !this.friendKeys[friend.id]) return
      const last = lastShotNotice.get(friend.id) || 0
      if (Date.now() - last < 20000) return
      lastShotNotice.set(friend.id, Date.now())
      const msg = { id: newMessageId(), peerId: friend.id, mine: true, text: '', att: null, sys: 'screenshot-sent', createdAt: Date.now(), status: 'sending' }
      await put(db, 'messages', msg)
      this.tick++
      await this._transmit(friend.id, msg, null, null)
    },

    // Sends `text` and/or one `file` to `friend` ({id, name}). Returns the stored message.
    async send(friend, text, file) {
      if (!this.ready) throw new Error('Mã hoá 2 đầu chưa sẵn sàng trên thiết bị này.')
      const id = newMessageId()
      let fileBytes = null
      let att = null
      let stored = null
      if (file) {
        if (!ALLOWED_IMAGE_TYPES.includes(file.type)) throw new Error(IMAGE_ONLY_MESSAGE)
        if (file.size > MAX_ATTACHMENT_BYTES) throw new Error('Tệp quá lớn (tối đa 5 MB)')
        // The picture is redrawn (no EXIF/GPS/device/time) and renamed before it is encrypted.
        const clean = await scrubImageMetadata(file)
        const name = anonymousName(clean.type)
        fileBytes = new Uint8Array(await clean.arrayBuffer())
        att = { name, type: clean.type || 'application/octet-stream', size: fileBytes.length }
        stored = { ...att, isImage: att.type.startsWith('image/') && att.type !== 'image/svg+xml', blob: new Blob([fileBytes], { type: att.type }) }
      }
      const createdAt = Date.now()
      const msg = { id, peerId: friend.id, mine: true, text: text || '', att: stored, createdAt, status: 'sending', ...(isGroupId(friend.id) ? { fromId: userId } : {}) }
      await put(db, 'messages', msg)
      this.tick++
      await this._transmit(friend.id, msg, fileBytes, att)
      return msg
    },

    // Encrypts and relays an already stored message (also used for "Gửi lại").
    async _transmit(friendId, msg, fileBytes, att) {
      const fail = async (reason) => {
        await this._setStatus(msg.id, 'failed', reason)
      }
      if (isGroupId(friendId)) return this._transmitGroup(msg, fileBytes, att)
      const key = await this._session(friendId)
      if (!key) return fail('no-key')
      const call = useCallStore()
      if (!call.socket || !call.socketReady) return fail('no-socket')
      if (msg.att && !fileBytes) fileBytes = new Uint8Array(await msg.att.blob.arrayBuffer())
      if (msg.att && !att) att = { name: msg.att.name, type: msg.att.type, size: msg.att.size }
      const plain = packMessage({ text: msg.text, ts: msg.createdAt, att, kind: msg.sys === 'screenshot-sent' ? 'screenshot' : null }, fileBytes)
      const { iv, ct } = await encryptBytes(key, plain, { from: userId, to: friendId, id: msg.id })
      const parts = Math.max(1, Math.ceil(ct.length / PART_CHARS))
      if (parts > MAX_PARTS) return fail('invalid')
      for (let i = 0; i < parts; i++) {
        call._send({ type: 'e2ee-msg', to: friendId, id: msg.id, iv, ct: ct.slice(i * PART_CHARS, (i + 1) * PART_CHARS), part: i, parts, ts: msg.createdAt })
      }
      await this._setStatus(msg.id, 'sent')
      ackTimers.set(
        msg.id,
        setTimeout(() => this._setStatus(msg.id, 'failed', 'timeout'), ACK_WAIT_MS),
      )
    },

    async retry(message) {
      if (!db || !message.mine) return
      const m = await get(db, 'messages', message.id)
      if (!m) return
      await this._setStatus(m.id, 'sending')
      await this._transmit(m.peerId, { ...m, status: 'sending' })
    },

    async _setStatus(id, status, reason) {
      const m = await get(db, 'messages', id)
      if (!m) return
      if (status !== 'sent') {
        clearTimeout(ackTimers.get(id))
        ackTimers.delete(id)
      }
      // A late timeout must not overwrite a delivery that already happened.
      if (m.status === 'delivered' && status === 'failed') return
      await put(db, 'messages', { ...m, status, reason: status === 'failed' ? reason : undefined })
      this.tick++
    },

    reasonText: (reason) => REASONS[reason] || 'Chưa gửi được.',

    // Puts the parts of one message back together; returns it once complete, else null.
    _assemble(frame) {
      const total = frame.parts || 1
      if (total === 1) return frame
      let entry = incoming.get(frame.id)
      if (!entry) {
        entry = { parts: new Array(total), got: 0, timer: setTimeout(() => incoming.delete(frame.id), PART_WAIT_MS) }
        incoming.set(frame.id, entry)
      }
      if (entry.parts.length !== total || entry.parts[frame.part] !== undefined) return null
      entry.parts[frame.part] = frame.ct
      entry.got++
      if (entry.got < total) return null
      clearTimeout(entry.timer)
      incoming.delete(frame.id)
      return { ...frame, ct: entry.parts.join('') }
    },

    // Frames from the WebSocket (routed here by the call store).
    async onSocketMessage(msg) {
      if (!db) return
      if (msg.type === 'e2ee-ack') {
        fanOut.delete(msg.id)
        return this._setStatus(msg.id, 'delivered')
      }
      if (msg.type === 'e2ee-undelivered') {
        // A group message goes to several members: it only failed when NONE of them can get it.
        const left = fanOut.get(msg.id)
        if (left > 1) {
          fanOut.set(msg.id, left - 1)
          return
        }
        fanOut.delete(msg.id)
        return this._setStatus(msg.id, 'failed', msg.reason)
      }
      if (msg.type !== 'e2ee-msg') return
      msg = this._assemble(msg)
      if (!msg) return
      try {
        if (await get(db, 'messages', msg.id)) return // duplicate
        // Fetch the sender's current key if we do not know it yet (new friend / new device).
        if (!this.friendKeys[msg.from]) await this.loadFriendKeys()
        let key = await this._session(msg.from)
        if (!key) return
        const frame = { from: msg.from, to: userId, id: msg.id }
        let plain
        try {
          plain = await decryptBytes(key, msg, frame)
        } catch {
          await this.loadFriendKeys() // their key may have changed; retry once with a fresh one
          key = await this._session(msg.from)
          plain = await decryptBytes(key, msg, frame)
        }
        const { text, ts, att, file, kind, group } = unpackMessage(plain)
        if (group) return await this._handleGroupMessage(msg, { text, ts, att, file, kind, group })
        if (kind === 'screenshot') {
          // The friend took a screenshot of this conversation: show a notice line and alert.
          await put(db, 'messages', { id: msg.id, peerId: msg.from, mine: false, text: '', att: null, sys: 'screenshot', createdAt: Math.min(ts, Date.now()), status: 'delivered' })
          useCallStore()._send({ type: 'e2ee-ack', to: msg.from, id: msg.id })
          this.tick++
          useNotifyStore().receive({ source: 'friend', from: msg.from, fromName: msg.fromName, preview: 'đã chụp màn hình cuộc trò chuyện với bạn', hasAttachment: false })
          await this.bumpUnread(msg.from)
          return
        }
        // Only pictures are accepted from a friend as well (a modified client could send anything).
        const stored = att && file.length && ALLOWED_IMAGE_TYPES.includes(att.type)
          ? {
              name: String(att.name || 'tep-dinh-kem').slice(0, 200),
              type: String(att.type || 'application/octet-stream'),
              size: file.length,
              isImage: true,
              blob: new Blob([file], { type: String(att.type || 'application/octet-stream') }),
            }
          : null
        await put(db, 'messages', { id: msg.id, peerId: msg.from, mine: false, text, att: stored, createdAt: Math.min(ts, Date.now()), status: 'delivered' })
        useCallStore()._send({ type: 'e2ee-ack', to: msg.from, id: msg.id })
        this.tick++
        useNotifyStore().receive({
          source: 'friend',
          from: msg.from,
          fromName: msg.fromName,
          preview: text || 'Đã gửi một tệp đính kèm',
          hasAttachment: !!stored,
        })
        await this.bumpUnread(msg.from)
      } catch (err) {
        console.warn('e2ee: could not read an incoming message', err)
      }
    },

    // ---- group chats ----
    async restoreGroups() {
      const groups = {}
      for (const m of await getAll(db, 'meta')) {
        if (!m.id.startsWith(`group:${GROUP_PREFIX}`)) continue
        const g = groupFromHeader(groupHeader(m.value))
        if (g) groups[g.id] = g
      }
      this.groups = groups
    },

    async _saveGroup(g) {
      const plain = JSON.parse(JSON.stringify(g)) // a plain copy: IndexedDB cannot clone a reactive proxy
      this.groups[g.id] = plain
      await put(db, 'meta', { id: `group:${g.id}`, value: plain })
    },

    // Creates the group on this device and tells every member. `others` = [{ id, name }] of friends (the relay only carries messages
    // between friends).
    async createGroup(name, myName, others) {
      if (!this.ready) throw new Error('Mã hoá 2 đầu chưa sẵn sàng trên thiết bị này.')
      const n = String(name || '').trim()
      if (!n) throw new Error('Nhập tên nhóm.')
      const seen = new Set([userId])
      const members = [{ id: userId, name: myName || 'Thành viên' }]
      for (const o of others) if (!seen.has(o.id)) { seen.add(o.id); members.push({ id: o.id, name: o.name }) }
      if (members.length < 3) throw new Error('Chọn ít nhất 2 bạn bè để tạo nhóm.')
      if (members.length > 50) throw new Error('Nhóm tối đa 50 người.')
      const g = { id: `${GROUP_PREFIX}${newMessageId()}`, name: n.slice(0, 60), creatorId: userId, updatedAt: Date.now(), members }
      await this._saveGroup(g)
      this.tick++
      await this._fanOutKind(g, 'group-new')
      return this.groups[g.id]
    },

    async renameGroup(groupId, name) {
      const g = this.groups[groupId]
      const n = String(name || '').trim()
      if (!g || !n || g.creatorId !== userId) return // only the creator renames
      const next = { ...JSON.parse(JSON.stringify(g)), name: n.slice(0, 60), updatedAt: Date.now() }
      await this._saveGroup(next)
      this.tick++
      await this._fanOutKind(next, 'group-new')
    },

    // Creator only: adds friends ([{ id, name }]) to the group. Everybody (the newcomers included) gets the updated group; the newcomers
    // see the messages sent from now on, not the earlier ones.
    async addGroupMembers(groupId, added) {
      const g = this.groups[groupId]
      if (!g || g.creatorId !== userId) return
      const have = new Set(g.members.map((m) => m.id))
      const fresh = added.filter((a) => !have.has(a.id) && have.add(a.id))
      if (!fresh.length) return
      if (g.members.length + fresh.length > 50) throw new Error('Nhóm tối đa 50 người.')
      const next = { ...JSON.parse(JSON.stringify(g)), members: [...g.members.map((m) => ({ id: m.id, name: m.name })), ...fresh.map((a) => ({ id: a.id, name: a.name }))], updatedAt: Date.now() }
      await this._saveGroup(next)
      this.tick++
      await this._fanOutKind(next, 'group-new')
    },

    // Creator only: removes a member. The others get the updated group; the removed person is told and drops the group.
    async removeGroupMember(groupId, memberId) {
      const g = this.groups[groupId]
      if (!g || g.creatorId !== userId || memberId === userId || !g.members.some((m) => m.id === memberId)) return
      const next = { ...JSON.parse(JSON.stringify(g)), members: g.members.filter((m) => m.id !== memberId).map((m) => ({ id: m.id, name: m.name })), updatedAt: Date.now() }
      if (next.members.length < 2) throw new Error('Nhóm cần ít nhất 2 người.')
      await this._saveGroup(next)
      this.tick++
      // the removed member is told with the group as it is now (without them) and kind "group-removed"
      const key = await this._session(memberId)
      const call = useCallStore()
      if (key && call.socket && call.socketReady) {
        const ts = Date.now()
        const id = newMessageId()
        const { iv, ct } = await encryptBytes(key, packMessage({ text: '', ts, kind: 'group-removed', group: groupHeader(next) }), { from: userId, to: memberId, id })
        call._send({ type: 'e2ee-msg', to: memberId, id, iv, ct, part: 0, parts: 1, ts })
      }
      await this._fanOutKind(next, 'group-new')
    },

    // Leaves the group: the others are told, then it is removed from this device together with its messages.
    async leaveGroup(groupId, notify = true) {
      const g = this.groups[groupId]
      if (g && notify) {
        const rest = { ...JSON.parse(JSON.stringify(g)), members: g.members.filter((m) => m.id !== userId), updatedAt: Date.now() }
        if (rest.members.length >= 2) await this._fanOutKind(rest, 'group-left')
      }
      await this.deleteConversation(groupId)
      delete this.groups[groupId]
      await del(db, 'meta', `group:${groupId}`)
      await del(db, 'meta', `unread:${groupId}`)
      await del(db, 'meta', `pin:${groupId}`)
      useNotifyStore().unread[`friend:${groupId}`] = 0
      this.tick++
    },

    // The name to show for member `id` of group `g` on this device.
    memberName(g, id) {
      if (id === userId) return 'Bạn'
      return g?.members.find((m) => m.id === id)?.name || 'Thành viên'
    },

    // A message with no text, only carrying the group (creation, rename, somebody left).
    async _fanOutKind(g, kind) {
      const ts = Date.now()
      const plain = packMessage({ text: '', ts, kind, group: groupHeader(g) })
      return this._fanOutFrames(g, newMessageId(), plain, ts, false)
    },

    // Encrypts `plain` for every member except me and relays it. Returns how many members it was handed to the socket for.
    async _fanOutFrames(g, id, plain, ts, ack = true) {
      const call = useCallStore()
      if (!call.socket || !call.socketReady) return 0
      let sent = 0
      for (const member of g.members) {
        if (member.id === userId) continue
        const key = await this._session(member.id)
        if (!key) continue // not my friend (no key): the relay would refuse it anyway
        const { iv, ct } = await encryptBytes(key, plain, { from: userId, to: member.id, id })
        const parts = Math.max(1, Math.ceil(ct.length / PART_CHARS))
        if (parts > MAX_PARTS) continue
        for (let i = 0; i < parts; i++) call._send({ type: 'e2ee-msg', to: member.id, id, iv, ct: ct.slice(i * PART_CHARS, (i + 1) * PART_CHARS), part: i, parts, ts })
        sent++
      }
      if (ack && sent > 0) fanOut.set(id, sent)
      return sent
    },

    async _transmitGroup(msg, fileBytes, att) {
      const g = this.groups[msg.peerId]
      if (!g) return this._setStatus(msg.id, 'failed', 'invalid')
      const call = useCallStore()
      if (!call.socket || !call.socketReady) return this._setStatus(msg.id, 'failed', 'no-socket')
      if (msg.att && !fileBytes) fileBytes = new Uint8Array(await msg.att.blob.arrayBuffer())
      if (msg.att && !att) att = { name: msg.att.name, type: msg.att.type, size: msg.att.size }
      const plain = packMessage({ text: msg.text, ts: msg.createdAt, att, group: groupHeader(g) }, fileBytes)
      const sent = await this._fanOutFrames(g, msg.id, plain, msg.createdAt)
      if (sent === 0) return this._setStatus(msg.id, 'failed', 'no-key')
      await this._setStatus(msg.id, 'sent')
      ackTimers.set(
        msg.id,
        setTimeout(() => {
          fanOut.delete(msg.id)
          this._setStatus(msg.id, 'failed', 'timeout')
        }, ACK_WAIT_MS),
      )
    },

    // A message (or creation / rename / "left" notice) of a group chat from `msg.from`.
    async _handleGroupMessage(msg, { text, ts, att, file, kind, group }) {
      const incoming = groupFromHeader(group)
      if (!incoming) return
      const known = this.groups[incoming.id]
      if (kind === 'group-removed') {
        // The creator removed me: forget the group (its messages go with it).
        if (!known || known.creatorId !== msg.from || incoming.members.some((x) => x.id === userId)) return
        useCallStore()._send({ type: 'e2ee-ack', to: msg.from, id: msg.id })
        const name = known.name
        await this.leaveGroup(known.id, false)
        useNotifyStore().receive({ source: 'friend', from: known.id, fromName: name, preview: 'Bạn đã bị xoá khỏi nhóm', hasAttachment: false })
        return
      }
      if (kind === 'group-left') {
        // The sender is leaving: it is no longer in the list the message carries, so it must have been a member before.
        if (!known || !known.members.some((x) => x.id === msg.from) || incoming.members.some((x) => x.id === msg.from)) return
      } else if (!incoming.members.some((x) => x.id === msg.from) || !incoming.members.some((x) => x.id === userId)) {
        return // only a member may speak in the group, and the group must include me
      }
      if (known && known.creatorId !== incoming.creatorId) return // the creator of an existing group cannot be changed
      // Who may change the group (name, members): the creator; a member leaving removes only themselves. A newer header carried by an
      // ordinary message of another member is not trusted.
      if (!known) await this._saveGroup(incoming)
      else if (incoming.updatedAt > known.updatedAt) {
        const leftOk = kind === 'group-left' && incoming.members.length === known.members.length - 1
        if (msg.from === incoming.creatorId || leftOk) await this._saveGroup(incoming)
      }
      const g = this.groups[incoming.id]
      useCallStore()._send({ type: 'e2ee-ack', to: msg.from, id: msg.id })
      const who = g.members.find((x) => x.id === msg.from)?.name || msg.fromName || 'Thành viên'
      if (kind === 'group-new' || kind === 'group-left') {
        this.tick++
        if (kind === 'group-new' && !known) useNotifyStore().receive({ source: 'friend', from: g.id, fromName: g.name, preview: `${who} đã thêm bạn vào nhóm`, hasAttachment: false })
        return
      }
      const stored = att && file.length && ALLOWED_IMAGE_TYPES.includes(att.type)
        ? { name: String(att.name || 'tep-dinh-kem').slice(0, 200), type: String(att.type), size: file.length, isImage: true, blob: new Blob([file], { type: String(att.type) }) }
        : null
      await put(db, 'messages', { id: msg.id, peerId: g.id, mine: false, text, att: stored, createdAt: Math.min(ts, Date.now()), status: 'delivered', fromId: msg.from })
      this.tick++
      useNotifyStore().receive({ source: 'friend', from: g.id, fromName: g.name, preview: `${who}: ${text || 'Đã gửi một tệp đính kèm'}`, hasAttachment: !!stored })
      await this.bumpUnread(g.id)
    },

    // ---- unread counters, kept on this device ----
    async bumpUnread(friendId) {
      const notify = useNotifyStore()
      await put(db, 'meta', { id: `unread:${friendId}`, value: notify.unread[`friend:${friendId}`] || 0 })
    },
    async restoreUnread() {
      const notify = useNotifyStore()
      for (const m of await getAll(db, 'meta')) {
        if (m.id.startsWith('unread:') && m.value > 0) notify.unread[`friend:${m.id.slice(7)}`] = m.value
      }
    },
    async markRead(friendId) {
      if (db) await del(db, 'meta', `unread:${friendId}`)
    },

    // ---- per-friend auto-delete, applied on this device ----
    async retentionOf(friendId) {
      return db ? (await get(db, 'meta', `retention:${friendId}`))?.value || null : null
    },
    async setRetention(friendId, rule) {
      if (rule) await put(db, 'meta', { id: `retention:${friendId}`, value: rule })
      else await del(db, 'meta', `retention:${friendId}`)
      await this.applyRetention(friendId)
    },
    async applyRetention(friendId) {
      const rule = await this.retentionOf(friendId)
      if (!rule) return
      const cutoff = Date.now() - rule.ttlSeconds * 1000
      let changed = false
      for (const m of await messagesOf(db, friendId)) {
        if (m.createdAt >= cutoff) continue
        if (rule.scope === 'images' && !m.att?.isImage) continue
        await del(db, 'messages', m.id)
        changed = true
      }
      if (changed) this.tick++
    },
    // Per-device notes kept next to the messages (pins, edited decodings). Never uploaded.
    async metaGet(key) {
      return db ? (await get(db, 'meta', key))?.value ?? null : null
    },
    async metaSet(key, value) {
      if (!db) return
      if (value == null) await del(db, 'meta', key)
      else await put(db, 'meta', { id: key, value })
    },
    // Deletes one message from THIS device (the friend keeps theirs).
    async deleteMessage(id) {
      if (!db) return
      await del(db, 'messages', id)
      await del(db, 'meta', `decode:${id}`)
      this.tick++
    },
    // Deletes the whole conversation with this friend from THIS device (the friend keeps theirs).
    async deleteConversation(friendId) {
      if (!db) return
      for (const m of await messagesOf(db, friendId)) await del(db, 'messages', m.id)
      this.tick++
    },
    async applyRetentionAll() {
      for (const m of await getAll(db, 'meta')) if (m.id.startsWith('retention:')) await this.applyRetention(m.id.slice(10))
    },
  },
})
