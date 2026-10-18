// New-message notifications. The server pushes a `new-message` event over the
// same WebSocket the calls use (see backend/lib/src/push.dart); the call store
// hands it to receive() here. This store keeps the unread counters and the
// toast list, plays the ping, and bumps `incomingTick` so the open page
// (friend chat / Phản hồi) reloads its conversation live.
//
// Support unread counters are kept on the server (GET /me/unread, POST
// /me/unread/read); friend-chat counters live on this device (e2ee/chat.js).
//
// Unread keys: `friend:<friendId>` (chat), `support` (customer's Phản hồi),
// `support:<userId>` (Admin's inbox, one per customer).
import { defineStore } from 'pinia'
import { askNotificationPermission, notifyMessage, playMessageTone } from '../callSounds'
import { api } from '../api'
import { router } from '../router'
import { useChatStore } from '../e2ee/chat'

const TOAST_MS = 7000

function keyOf(msg) {
  if (msg.source === 'friend') return `friend:${msg.from}`
  return msg.toAdmin ? `support:${msg.from}` : 'support'
}

export const useNotifyStore = defineStore('notify', {
  state: () => ({
    unread: {}, // key -> count
    toasts: [], // { id, title, body, to }
    incomingTick: 0,
    supportVisible: false, // the popover is on screen right now
    supportOpen: false, // asks <SupportChat /> to open itself (toast tap, old /feedback link)
    paymentTick: 0, // bumps when Admin decides this user's payment request
    lastIncoming: null, // the last raw event, so views can tell if it is theirs
    friendRequests: 0, // pending incoming friend requests (server count + live pushes)
    requestsTick: 0, // bumps on friend-request / friend-accepted so the friends screen reloads
    lastFriendEvent: null, // { type: 'friend-request' | 'friend-accepted', ... }
  }),
  getters: {
    total: (s) => Object.values(s.unread).reduce((a, b) => a + b, 0) + s.friendRequests,
    friendUnread: (s) =>
      Object.entries(s.unread).reduce((a, [k, v]) => a + (k.startsWith('friend:') ? v : 0), 0),
    supportUnread: (s) => s.unread.support || 0,
    adminSupportUnread: (s) =>
      Object.entries(s.unread).reduce((a, [k, v]) => a + (k.startsWith('support:') ? v : 0), 0),
  },
  actions: {
    // Called by the call store for every `new-message` event.
    receive(msg, { isAdmin = false } = {}) {
      const event = { ...msg, toAdmin: isAdmin && msg.source === 'support' }
      this.lastIncoming = event
      this.incomingTick++

      // Already looking at that conversation in a visible tab: it refreshes
      // itself, no need to ping.
      const r = router.currentRoute.value
      const viewing =
        !document.hidden &&
        ((event.source === 'friend' && r.name === 'friend-thread' && r.params.friendId === event.from) ||
          (event.source === 'support' && !isAdmin && (r.name === 'feedback' || this.supportVisible)) ||
          (event.source === 'support' && isAdmin && r.name === 'admin-messages-thread' && r.params.userId === event.from))
      if (viewing) return

      const key = keyOf(event)
      this.unread[key] = (this.unread[key] || 0) + 1
      const to =
        event.source === 'friend'
          ? { name: 'friend-thread', params: { friendId: event.from } }
          : isAdmin
            ? { name: 'admin-messages-thread', params: { userId: event.from } }
            : { name: 'feedback' }
      const id = `${Date.now()}-${Math.random()}`
      const toast = { id, title: event.fromName || 'Tin nhắn mới', body: event.preview || 'Tin nhắn mới', to }
      this.toasts.push(toast)
      if (this.toasts.length > 3) this.toasts.shift()
      setTimeout(() => this.dismiss(id), TOAST_MS)
      playMessageTone()
      notifyMessage(toast.title, toast.body, () => router.push(to))
    },

    // Admin approved / rejected the user's payment request (WebSocket push).
    paymentDecided(msg) {
      this.paymentTick++
      const approved = msg.status === 'approved'
      const id = `${Date.now()}-${Math.random()}`
      this.toasts.push({
        id,
        title: approved ? 'Thanh toán đã được duyệt' : 'Thanh toán bị từ chối',
        body: approved ? 'Gói dịch vụ của bạn đã được cập nhật.' : msg.reason ? `Lý do: ${msg.reason}` : 'Xem chi tiết ở trang Gói dịch vụ.',
        to: { name: 'packages' },
      })
      if (this.toasts.length > 3) this.toasts.shift()
      setTimeout(() => this.dismiss(id), TOAST_MS)
      playMessageTone()
    },

    // Someone asked to be my friend (WebSocket push).
    friendRequestReceived(msg) {
      this.friendRequests++
      this.lastFriendEvent = { type: 'friend-request', ...msg }
      this.requestsTick++
      this._pushToast(`${msg.fromName || 'Ai đó'} gửi lời mời kết bạn`, 'Bấm để xem lời mời.', { name: 'friends' })
    },

    // Someone accepted my request (WebSocket push).
    friendAcceptedByPeer(msg) {
      this.lastFriendEvent = { type: 'friend-accepted', ...msg }
      this.requestsTick++
      this._pushToast(`${msg.name || 'Ai đó'} đã chấp nhận lời mời`, 'Các bạn đã là bạn bè.', { name: 'friends' })
    },

    // The friends screen knows the exact number after loading the lists.
    setFriendRequests(n) {
      this.friendRequests = Math.max(0, Number(n) || 0)
    },

    _pushToast(title, body, to) {
      const id = `${Date.now()}-${Math.random()}`
      this.toasts.push({ id, title, body, to })
      if (this.toasts.length > 3) this.toasts.shift()
      setTimeout(() => this.dismiss(id), TOAST_MS)
      playMessageTone()
    },

    dismiss(id) {
      this.toasts = this.toasts.filter((t) => t.id !== id)
    },

    open(toast) {
      this.dismiss(toast.id)
      router.push(toast.to)
    },

    // Loads the real counts from the server (page load, reconnect, tab focus).
    async refresh() {
      try {
        const res = await api.get('/me/unread')
        // Friend chat is end-to-end encrypted and kept on this device, so its unread
        // counters are local (e2ee/chat.js); only support counters come from the server.
        const next = {}
        for (const [k, n] of Object.entries(this.unread)) if (k.startsWith('friend:')) next[k] = n
        if (res.support > 0) next.support = res.support
        for (const [id, n] of Object.entries(res.supportByUser || {})) if (n > 0) next[`support:${id}`] = n
        this.unread = next
        this.friendRequests = Math.max(0, Number(res.friendRequests) || 0)
      } catch {
        /* badges are a nicety - keep whatever we have */
      }
    },

    // The conversation is being read: drop its badge and tell the server so it
    // stays read after a reload.
    clear(key) {
      const had = !!this.unread[key]
      if (had) delete this.unread[key]
      const peerId = key === 'support' ? 'support' : key.split(':')[1]
      if (key.startsWith('friend:')) {
        useChatStore().markRead(peerId)
        return
      }
      if (peerId) api.post('/me/unread/read', { peerId }).catch(() => {})
    },

    clearAll() {
      this.unread = {}
      this.friendRequests = 0
      this.toasts = []
    },

    // Browsers only allow the permission prompt from a user gesture.
    askPermission() {
      askNotificationPermission()
    },
  },
})
