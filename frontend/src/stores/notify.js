// New-message notifications. The server pushes a `new-message` event over the
// same WebSocket the calls use (see backend/lib/src/push.dart); the call store
// hands it to receive() here. This store keeps the unread counters and the
// toast list, plays the ping, and bumps `incomingTick` so the open page
// (friend chat / Phản hồi) reloads its conversation live.
//
// Unread counters live in memory only: they reset on a full page reload.
//
// Unread keys: `friend:<friendId>` (chat), `support` (customer's Phản hồi),
// `support:<userId>` (Admin's inbox, one per customer).
import { defineStore } from 'pinia'
import { askNotificationPermission, notifyMessage, playMessageTone } from '../callSounds'
import { router } from '../router'

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
    lastIncoming: null, // the last raw event, so views can tell if it is theirs
  }),
  getters: {
    total: (s) => Object.values(s.unread).reduce((a, b) => a + b, 0),
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
          (event.source === 'support' && !isAdmin && r.name === 'feedback') ||
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

    dismiss(id) {
      this.toasts = this.toasts.filter((t) => t.id !== id)
    },

    open(toast) {
      this.dismiss(toast.id)
      router.push(toast.to)
    },

    clear(key) {
      if (this.unread[key]) delete this.unread[key]
    },

    clearAll() {
      this.unread = {}
      this.toasts = []
    },

    // Browsers only allow the permission prompt from a user gesture.
    askPermission() {
      askNotificationPermission()
    },
  },
})
