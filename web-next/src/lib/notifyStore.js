// New-message notifications (port of stores/notify.js). The server pushes a `new-message` event over the same
// WebSocket the calls use (see backend/lib/src/push.dart); the call store hands it to receive() here. This store keeps
// the unread counters and the toast list, plays the ping, and bumps `incomingTick` so the open page (friend chat /
// Phản hồi) reloads its conversation live.
//
// Support unread counters are kept on the server (GET /me/unread, POST /me/unread/read); friend-chat counters live on
// this device (e2ee/chat).
//
// Unread keys: `friend:<friendId>` (chat), `support` (customer's Phản hồi), `support:<userId>` (Admin's inbox, one per
// customer). Toast targets (`to`) are address strings of the Next app: '/friends?thread=<id>', '/admin/messages?user=<id>',
// '/feedback' (opens the Phản hồi popover) ...
import { create } from 'zustand'
import { askNotificationPermission, notifyMessage, playMessageTone } from './callSounds'
import { api } from './api'
import { currentLocation, hooks, navigate } from './hooks'

const TOAST_MS = 7000
export const FEEDBACK = '/feedback'

// A toast / desktop notification target: '/feedback' opens the Phản hồi popover on the current page instead of leaving it.
export function goTo(to) {
  if (to === FEEDBACK) useNotifyStore.setState({ supportOpen: true })
  else navigate(to)
}

function keyOf(msg) {
  if (msg.source === 'friend') return `friend:${msg.from}`
  return msg.toAdmin ? `support:${msg.from}` : 'support'
}

// ---- getters (use as selectors: useNotifyStore(totalOf)) ----
export const totalOf = (s) => Object.values(s.unread).reduce((a, b) => a + b, 0) + s.friendRequests
export const friendUnreadOf = (s) => Object.entries(s.unread).reduce((a, [k, v]) => a + (k.startsWith('friend:') ? v : 0), 0)
export const supportUnreadOf = (s) => s.unread.support || 0
export const adminSupportUnreadOf = (s) => Object.entries(s.unread).reduce((a, [k, v]) => a + (k.startsWith('support:') ? v : 0), 0)

export const useNotifyStore = create((set, get) => ({
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

  // Called by the call store for every `new-message` event.
  receive(msg, { isAdmin = false } = {}) {
    const event = { ...msg, toAdmin: isAdmin && msg.source === 'support' }
    set((s) => ({ lastIncoming: event, incomingTick: s.incomingTick + 1 }))

    // Already looking at that conversation in a visible tab: it refreshes itself, no need to ping.
    const { path, params } = currentLocation()
    const viewing =
      !document.hidden &&
      ((event.source === 'friend' && path === '/friends' && params.get('thread') === event.from) ||
        (event.source === 'support' && !isAdmin && get().supportVisible) ||
        (event.source === 'support' && isAdmin && path === '/admin/messages' && params.get('user') === event.from))
    if (viewing) return

    const key = keyOf(event)
    set((s) => ({ unread: { ...s.unread, [key]: (s.unread[key] || 0) + 1 } }))
    const to =
      event.source === 'friend'
        ? `/friends?thread=${encodeURIComponent(event.from)}`
        : isAdmin
          ? `/admin/messages?user=${encodeURIComponent(event.from)}`
          : FEEDBACK
    const toast = { title: event.fromName || 'Tin nhắn mới', body: event.preview || 'Tin nhắn mới', to }
    get()._pushToast(toast.title, toast.body, toast.to)
    notifyMessage(toast.title, toast.body, () => goTo(to))
  },

  // Admin approved / rejected the user's payment request (WebSocket push).
  paymentDecided(msg) {
    set((s) => ({ paymentTick: s.paymentTick + 1 }))
    const approved = msg.status === 'approved'
    get()._pushToast(
      approved ? 'Thanh toán đã được duyệt' : 'Thanh toán bị từ chối',
      approved ? 'Gói dịch vụ của bạn đã được cập nhật.' : msg.reason ? `Lý do: ${msg.reason}` : 'Xem chi tiết ở trang Gói dịch vụ.',
      '/account?tab=packages',
    )
  },

  // Someone asked to be my friend (WebSocket push).
  friendRequestReceived(msg) {
    set((s) => ({ friendRequests: s.friendRequests + 1, lastFriendEvent: { type: 'friend-request', ...msg }, requestsTick: s.requestsTick + 1 }))
    get()._pushToast(`${msg.fromName || 'Ai đó'} gửi lời mời kết bạn`, 'Bấm để xem lời mời.', '/friends')
  },

  // Someone accepted my request (WebSocket push).
  friendAcceptedByPeer(msg) {
    set((s) => ({ lastFriendEvent: { type: 'friend-accepted', ...msg }, requestsTick: s.requestsTick + 1 }))
    get()._pushToast(`${msg.name || 'Ai đó'} đã chấp nhận lời mời`, 'Các bạn đã là bạn bè.', '/friends')
  },

  // The friends screen knows the exact number after loading the lists.
  setFriendRequests(n) {
    set({ friendRequests: Math.max(0, Number(n) || 0) })
  },

  _pushToast(title, body, to) {
    const id = `${Date.now()}-${Math.random()}`
    set((s) => ({ toasts: [...s.toasts, { id, title, body, to }].slice(-3) }))
    setTimeout(() => get().dismiss(id), TOAST_MS)
    playMessageTone()
  },

  dismiss(id) {
    set((s) => ({ toasts: s.toasts.filter((t) => t.id !== id) }))
  },

  open(toast) {
    get().dismiss(toast.id)
    goTo(toast.to)
  },

  // Loads the real counts from the server (page load, reconnect, tab focus).
  async refresh() {
    try {
      const res = await api.get('/me/unread')
      // Friend chat is end-to-end encrypted and kept on this device, so its unread counters are local (e2ee/chat);
      // only support counters come from the server.
      const next = {}
      for (const [k, n] of Object.entries(get().unread)) if (k.startsWith('friend:')) next[k] = n
      if (res.support > 0) next.support = res.support
      for (const [id, n] of Object.entries(res.supportByUser || {})) if (n > 0) next[`support:${id}`] = n
      set({ unread: next, friendRequests: Math.max(0, Number(res.friendRequests) || 0) })
    } catch {
      /* badges are a nicety - keep whatever we have */
    }
  },

  // The conversation is being read: drop its badge and tell the server so it stays read after a reload.
  clear(key) {
    if (get().unread[key]) {
      const { [key]: _gone, ...rest } = get().unread
      set({ unread: rest })
    }
    const peerId = key === 'support' ? 'support' : key.split(':')[1]
    if (key.startsWith('friend:')) {
      hooks.markFriendRead(peerId)
      return
    }
    if (peerId) api.post('/me/unread/read', { peerId }).catch(() => {})
  },

  clearAll() {
    set({ unread: {}, friendRequests: 0, toasts: [] })
  },

  // Browsers only allow the permission prompt from a user gesture.
  askPermission() {
    askNotificationPermission()
  },
}))
