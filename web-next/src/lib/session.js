// One place that drops everything the previous account left in memory (open call WebSocket, chat db handle/keys,
// unread counters, toasts). Called from the app shell whenever the session ends, whichever path ended it
// (logout, auto-lock, 401 expiry). The call / chat stores add their cleanup with registerTeardown().
import { hooks } from './hooks'
import { useNotifyStore } from './notifyStore'

export function teardownSession() {
  for (const fn of [...hooks.teardowns, () => useNotifyStore.getState().clearAll()]) {
    try {
      fn()
    } catch {
      /* best effort: keep tearing down the rest */
    }
  }
}
