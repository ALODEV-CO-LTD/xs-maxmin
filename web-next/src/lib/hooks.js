// Seams for parts that are converted later (call store, e2ee chat store) and for the router, so the stores in this
// folder do not import them (no import cycles; the Vue code imported the router and Pinia stores directly).
//   navigate(to)        - the app router's push, installed by <Providers>; falls back to a full page load
//   hooks.inCall()      - true while a voice call is on (the call store installs it)
//   hooks.markFriendRead(friendId) - clears the on-device unread counter of a friend chat (chat store installs it)
//   registerTeardown(fn) - extra cleanup run by teardownSession() when the session ends
let navigator_ = null
export const setNavigator = (fn) => {
  navigator_ = fn
}
export const navigate = (to) => {
  if (navigator_) return navigator_(to)
  if (typeof window !== 'undefined') window.location.assign(to)
}

export const hooks = {
  inCall: () => false,
  markFriendRead: () => {},
  teardowns: [],
}
export const registerTeardown = (fn) => {
  hooks.teardowns.push(fn)
  return () => {
    hooks.teardowns = hooks.teardowns.filter((f) => f !== fn)
  }
}

/** Where the browser is now: `{ path, params }` (the Next router query is read from the address bar). */
export function currentLocation() {
  if (typeof window === 'undefined') return { path: '/', params: new URLSearchParams() }
  return { path: window.location.pathname, params: new URLSearchParams(window.location.search) }
}
