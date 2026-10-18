// One place that drops everything the previous account left in memory (open call
// WebSocket, chat db handle/keys, unread counters, toasts). Called from App.vue
// whenever the session ends, whichever path ended it (logout, auto-lock, 401 expiry).
import { useCallStore } from './stores/call'
import { useChatStore } from './e2ee/chat'
import { useNotifyStore } from './stores/notify'

export function teardownSession() {
  for (const fn of [
    () => useCallStore().disconnect(),
    () => useChatStore().reset(),
    () => useNotifyStore().clearAll(),
  ]) {
    try {
      fn()
    } catch {
      /* best effort: keep tearing down the rest */
    }
  }
}
