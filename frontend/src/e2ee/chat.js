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

export const useChatStore = defineStore('e2ee-chat', {
  state: () => ({
    ready: false,
    error: '',
    tick: 0, // bumps whenever stored messages change (views reload from the DB)
    myFingerprint: '',
    peerInfo: {}, // friendId -> { fingerprint, changed }
    friendKeys: {}, // friendId -> public JWK from the server
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

    // The user has seen the "key changed" warning for this friend.
    async acceptKeyChange(friendId) {
      const known = await get(db, 'peers', friendId)
      if (known) await put(db, 'peers', { ...known, changed: false })
      if (this.peerInfo[friendId]) this.peerInfo[friendId].changed = false
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
          out[m.peerId] = { at: m.createdAt, text: m.sys ? '📷 Chụp màn hình cuộc trò chuyện' : m.text || (m.att ? `[Đính kèm] ${m.att.name}` : '') }
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
      const msg = { id, peerId: friend.id, mine: true, text: text || '', att: stored, createdAt, status: 'sending' }
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
      if (msg.type === 'e2ee-ack') return this._setStatus(msg.id, 'delivered')
      if (msg.type === 'e2ee-undelivered') return this._setStatus(msg.id, 'failed', msg.reason)
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
        const { text, ts, att, file, kind } = unpackMessage(plain)
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
    async applyRetentionAll() {
      for (const m of await getAll(db, 'meta')) if (m.id.startsWith('retention:')) await this.applyRetention(m.id.slice(10))
    },
  },
})
