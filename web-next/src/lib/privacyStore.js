// Privacy store - client-side "Cài đặt quyền riêng tư" (K34) and the logic behind auto-lock (K09/K40/S02) and
// hide-when-away (K32/S10). Port of stores/privacy.js.
//
// Conventions:
//   - Settings live in localStorage under 'xoso_privacy' (per browser, not synced to the server):
//     { autoLockMinutes, hideLockSeconds, blurOnHide }.
//       * autoLockMinutes  - lock after this many idle minutes; 0 = off.
//       * hideLockSeconds  - lock if the tab/window was hidden at least this long; 0 = off.
//       * blurOnHide       - blur the page while it is hidden / unfocused.
//   - `locked` is also persisted ('xoso_locked') so a reload does not bypass the lock; the last-activity time
//     ('xoso_last_active') lets a reload or a sleeping computer still lock once the idle limit has passed.
//   - Locking never unmounts the screens: the page is only covered (and made `inert`) by <PrivacyGuard />, so
//     half-typed input survives the lock.
//   - Unlocking asks the server (POST /me/verify-password) to check the login password or the layer-2 password.
//   - Limit (K33): a web page cannot block screenshots or the OS app-switcher preview; blur only reduces what is left
//     visible while the page is away.
import { create } from 'zustand'
import { api } from './api'
import { hooks } from './hooks'

const SETTINGS_KEY = 'xoso_privacy'
const LOCKED_KEY = 'xoso_locked'
const ACTIVE_KEY = 'xoso_last_active'

const DEFAULTS = { autoLockMinutes: 0, hideLockSeconds: 0, blurOnHide: true }

function readStorage(key) {
  try {
    return localStorage.getItem(key)
  } catch {
    return null
  }
}
function writeStorage(key, value) {
  try {
    if (value === null) localStorage.removeItem(key)
    else localStorage.setItem(key, value)
  } catch {
    /* localStorage unavailable - works for this tab only */
  }
}

export function loadSettings() {
  try {
    const raw = JSON.parse(readStorage(SETTINGS_KEY) || '{}')
    return {
      autoLockMinutes: Math.max(0, Number(raw.autoLockMinutes) || 0),
      hideLockSeconds: Math.max(0, Number(raw.hideLockSeconds) || 0),
      blurOnHide: raw.blurOnHide === undefined ? DEFAULTS.blurOnHide : !!raw.blurOnHide,
    }
  } catch {
    return { ...DEFAULTS }
  }
}

// A voice call must never be interrupted by the auto-lock or the blur: the user is talking, not idle, and the call
// screen has to stay answerable.
const inCall = () => {
  try {
    return !!hooks.inCall()
  } catch {
    return false
  }
}

let timer = null
let serverDefaultMinutes = 0 // admin policy defaults, remembered so start() can re-apply them
let serverDefaultHideSeconds = 0
let hiddenAt = 0
let lastWrite = 0
let lastActive = 0
let cleanup = null

export const usePrivacyStore = create((set, get) => ({
  ...DEFAULTS,
  locked: false,
  away: false, // page hidden / window unfocused -> blurred
  blurPolicy: false, // Admin policy (Chính sách bảo mật): blur-on-hide allowed at all (default off)

  saveSettings(patch) {
    set(patch)
    const s = get()
    writeStorage(SETTINGS_KEY, JSON.stringify({ autoLockMinutes: s.autoLockMinutes, hideLockSeconds: s.hideLockSeconds, blurOnHide: s.blurOnHide }))
    if (!s.blurOnHide) set({ away: false })
    get().touch(true)
  },

  setBlurPolicy(on) {
    set({ blurPolicy: on === true })
    if (on !== true) set({ away: false })
  },

  // Admin-set system defaults (policyStore): the idle lock minutes and the "lock when the page was hidden" seconds. Used only
  // while this person has not chosen their own values (nothing saved in this browser yet).
  applyServerDefault(minutes, hideSeconds = serverDefaultHideSeconds) {
    serverDefaultMinutes = minutes
    serverDefaultHideSeconds = hideSeconds
    if (readStorage(SETTINGS_KEY) !== null) return
    if (minutes > 0) set({ autoLockMinutes: minutes })
    if (hideSeconds > 0) set({ hideLockSeconds: hideSeconds })
  },

  lock() {
    if (get().locked || inCall()) return
    set({ locked: true })
    writeStorage(LOCKED_KEY, '1')
  },

  async unlock(password) {
    await api.post('/me/verify-password', { password })
    set({ locked: false, away: false })
    writeStorage(LOCKED_KEY, null)
    get().touch(true)
  },

  // Record user activity (throttled writes so storage is not hammered).
  touch(force = false) {
    const now = Date.now()
    lastActive = now
    if (force || now - lastWrite > 5000) {
      lastWrite = now
      writeStorage(ACTIVE_KEY, String(now))
    }
  },

  // Locks if the idle limit has already passed (also covers sleep / reload).
  checkIdle() {
    const s = get()
    if (s.locked || !s.autoLockMinutes) return
    // Time on a call counts as activity, so the idle clock restarts when it ends.
    if (inCall()) {
      s.touch(true)
      return
    }
    const last = lastActive || Number(readStorage(ACTIVE_KEY)) || Date.now()
    if (Date.now() - last >= s.autoLockMinutes * 60000) s.lock()
  },

  // Attach listeners once a user is logged in; call stop() on logout.
  start() {
    if (cleanup) return
    set(loadSettings())
    get().applyServerDefault(serverDefaultMinutes, serverDefaultHideSeconds)
    lastActive = Number(readStorage(ACTIVE_KEY)) || Date.now()
    if (readStorage(LOCKED_KEY) === '1') set({ locked: true })
    get().checkIdle()

    const onActivity = () => {
      if (!get().locked) get().touch()
    }
    const events = ['pointerdown', 'keydown', 'wheel', 'touchstart', 'mousemove']
    events.forEach((e) => window.addEventListener(e, onActivity, { passive: true }))

    const goAway = () => {
      const s = get()
      if (s.blurPolicy && s.blurOnHide && !inCall()) set({ away: true })
    }
    const comeBack = () => set({ away: false })
    const onVisibility = () => {
      if (document.hidden) {
        hiddenAt = Date.now()
        goAway()
      } else {
        const s = get()
        if (s.hideLockSeconds && hiddenAt && Date.now() - hiddenAt >= s.hideLockSeconds * 1000) s.lock()
        hiddenAt = 0
        get().checkIdle()
        if (document.hasFocus()) comeBack()
      }
    }
    const onBlur = () => goAway()
    const onFocus = () => {
      if (!document.hidden) comeBack()
    }
    document.addEventListener('visibilitychange', onVisibility)
    window.addEventListener('blur', onBlur)
    window.addEventListener('focus', onFocus)

    timer = setInterval(() => get().checkIdle(), 5000)

    cleanup = () => {
      events.forEach((e) => window.removeEventListener(e, onActivity))
      document.removeEventListener('visibilitychange', onVisibility)
      window.removeEventListener('blur', onBlur)
      window.removeEventListener('focus', onFocus)
      clearInterval(timer)
      timer = null
    }
  },

  stop() {
    if (cleanup) cleanup()
    cleanup = null
    set({ locked: false, away: false })
    writeStorage(LOCKED_KEY, null)
    writeStorage(ACTIVE_KEY, null)
  },
}))

// Initial settings from storage on the client (the module is also evaluated while the static pages are built).
if (typeof window !== 'undefined') usePrivacyStore.setState(loadSettings())
