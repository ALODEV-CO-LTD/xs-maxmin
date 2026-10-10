// Privacy store - client-side "Cài đặt quyền riêng tư" (K34) and the logic
// behind auto-lock (K09/K40/S02) and auto-lock after being away.
//
// Conventions:
//   - Settings live in localStorage under 'xoso_privacy' (per browser, not
//     synced to the server): { autoLockMinutes, hideLockSeconds }.
//       * autoLockMinutes  - lock after this many idle minutes; 0 = off.
//       * hideLockSeconds  - lock if the tab/window was hidden at least this
//                            long; 0 = off.
//   - `locked` is also persisted ('xoso_locked') so a reload does not bypass
//     the lock; the last-activity time ('xoso_last_active') lets a reload or
//     a sleeping computer still lock once the idle limit has passed.
//   - Locking never unmounts the views: the page is only covered (and made
//     `inert`) by <PrivacyGuard />, so half-typed input survives the lock.
//   - Unlocking asks the server (POST /me/verify-password) to check the login
//     password or the layer-2 password. Nothing is sent about the device or
//     its location.
//   - Limit (K33): a web page cannot block screenshots or the OS app-switcher
//     preview. (The old blur-while-away feature was removed on request.)
import { defineStore } from 'pinia'
import { api } from '../api'
import { useCallStore } from './call'

const SETTINGS_KEY = 'xoso_privacy'
const LOCKED_KEY = 'xoso_locked'
const ACTIVE_KEY = 'xoso_last_active'

const DEFAULTS = { autoLockMinutes: 0, hideLockSeconds: 0 }

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

function loadSettings() {
  try {
    const raw = JSON.parse(readStorage(SETTINGS_KEY) || '{}')
    return {
      autoLockMinutes: Math.max(0, Number(raw.autoLockMinutes) || 0),
      hideLockSeconds: Math.max(0, Number(raw.hideLockSeconds) || 0),
    }
  } catch {
    return { ...DEFAULTS }
  }
}

// A voice call must never be interrupted by the auto-lock or the blur: the
// user is talking, not idle, and the call screen has to stay answerable.
function inCall() {
  try {
    const call = useCallStore()
    return call.status !== 'idle' || call.acquiring
  } catch {
    return false
  }
}

let timer = null
let serverDefaultMinutes = 0 // admin policy default, remembered so start() can re-apply it
let hiddenAt = 0
let lastWrite = 0
let lastActive = 0
let cleanup = null

export const usePrivacyStore = defineStore('privacy', {
  state: () => ({
    ...loadSettings(),
    locked: false,
  }),
  actions: {
    saveSettings(patch) {
      Object.assign(this, patch)
      writeStorage(
        SETTINGS_KEY,
        JSON.stringify({
          autoLockMinutes: this.autoLockMinutes,
          hideLockSeconds: this.hideLockSeconds,
        }),
      )
      this.touch(true)
    },

    // Admin-set default idle lock (stores/policy.js): used only while this person has not
    // chosen their own value (nothing saved in this browser yet).
    applyServerDefault(minutes) {
      serverDefaultMinutes = minutes
      if (readStorage(SETTINGS_KEY) === null && minutes > 0) this.autoLockMinutes = minutes
    },

    lock() {
      if (this.locked || inCall()) return
      this.locked = true
      writeStorage(LOCKED_KEY, '1')
    },

    async unlock(password) {
      await api.post('/me/verify-password', { password })
      this.locked = false
      writeStorage(LOCKED_KEY, null)
      this.touch(true)
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
      if (this.locked || !this.autoLockMinutes) return
      // Time on a call counts as activity, so the idle clock restarts when it ends.
      if (inCall()) {
        this.touch(true)
        return
      }
      const last = lastActive || Number(readStorage(ACTIVE_KEY)) || Date.now()
      if (Date.now() - last >= this.autoLockMinutes * 60000) this.lock()
    },

    // Attach listeners once a user is logged in; call stop() on logout.
    start() {
      if (cleanup) return
      Object.assign(this, loadSettings())
      this.applyServerDefault(serverDefaultMinutes)
      lastActive = Number(readStorage(ACTIVE_KEY)) || Date.now()
      if (readStorage(LOCKED_KEY) === '1') this.locked = true
      this.checkIdle()

      const onActivity = () => {
        if (!this.locked) this.touch()
      }
      const events = ['pointerdown', 'keydown', 'wheel', 'touchstart', 'mousemove']
      events.forEach((e) => window.addEventListener(e, onActivity, { passive: true }))

      const onVisibility = () => {
        if (document.hidden) {
          hiddenAt = Date.now()
        } else {
          if (this.hideLockSeconds && hiddenAt && Date.now() - hiddenAt >= this.hideLockSeconds * 1000) this.lock()
          hiddenAt = 0
          this.checkIdle()
        }
      }
      document.addEventListener('visibilitychange', onVisibility)

      timer = setInterval(() => this.checkIdle(), 5000)

      cleanup = () => {
        events.forEach((e) => window.removeEventListener(e, onActivity))
        document.removeEventListener('visibilitychange', onVisibility)
        clearInterval(timer)
        timer = null
      }
    },

    stop() {
      if (cleanup) cleanup()
      cleanup = null
      this.locked = false
      writeStorage(LOCKED_KEY, null)
      writeStorage(ACTIVE_KEY, null)
    },
  },
})
