// "Ẩn số liệu" (hide figures) - a screen-only mask, not encryption (port of stores/mask.js). When `enabled` (persisted
// per device), every figure shows as "••••" until the user re-enters the account password (POST /me/verify-password,
// done by PasswordPromptDialog) which reveals them. The chosen time (30 s by default; 10 s / 20 s / 30 s / 1 min /
// 5 min, remembered per device) is an IDLE time: every touch / click / key press / scroll restarts it, so figures never
// disappear while the user is working - they are covered only after that long WITHOUT any action. They are covered at
// once, whatever the timer says, when the window loses focus, the tab goes to the background, or the page is left.
//
// Components read `mask.masked()` / `useMasked()` (see MaskedValue) and never receive the real value while it is true.
import { create } from 'zustand'

const KEY = 'xoso_mask_enabled'
const SECONDS_KEY = 'xoso_mask_reveal_seconds'
// Choices offered in the toolbar, in seconds.
export const REVEAL_CHOICES = [10, 20, 30, 60, 300]
const DEFAULT_SECONDS = 30
// Grace before covering when the tab is hidden / the window loses focus. 0 = at once.
const HIDDEN_MS = 0
const BLUR_MS = 0

// Test hook: window.__MASK_TEST = { revealMs, hiddenMs, blurMs } overrides the timers.
function limit(name, dflt) {
  const v = typeof window !== 'undefined' && window.__MASK_TEST ? window.__MASK_TEST[name] : null
  return typeof v === 'number' ? v : dflt
}

function readEnabled() {
  try {
    localStorage.removeItem(KEY) // an old "on" saved by an earlier version must not hide anything
  } catch (_) {
    /* storage unavailable */
  }
  return false
}
function readSeconds() {
  try {
    const n = Number(localStorage.getItem(SECONDS_KEY))
    return REVEAL_CHOICES.includes(n) ? n : DEFAULT_SECONDS
  } catch (_) {
    return DEFAULT_SECONDS
  }
}
function writeSeconds(n) {
  try {
    localStorage.setItem(SECONDS_KEY, String(n))
  } catch (_) {
    // Private mode etc.: the choice just won't survive a reload.
  }
}
function writeEnabled(on) {
  try {
    localStorage.setItem(KEY, on ? '1' : '0')
  } catch (_) {
    // Private mode etc.: the switch just won't survive a reload.
  }
}

// revealUntil: epoch ms when the figures are covered again (0 while covered).
export const useMaskStore = create(() => ({ enabled: false, revealed: false, revealSeconds: DEFAULT_SECONDS, revealUntil: 0 }))
const get = () => useMaskStore.getState()
const set = (p) => useMaskStore.setState(p)
if (typeof window !== 'undefined') set({ enabled: readEnabled(), revealSeconds: readSeconds() })

let revealTimer = null
let graceTimer = null
let users = 0 // screens currently using the mask (each calls attach/detach)

function clearTimer() {
  if (revealTimer) clearTimeout(revealTimer)
  revealTimer = null
}

function revealMs() {
  return limit('revealMs', get().revealSeconds * 1000)
}

// Idle timer: fires at revealUntil; if the user acted meanwhile revealUntil moved on, so wait again.
function armIdleTimer() {
  clearTimer()
  revealTimer = setTimeout(() => {
    if (get().revealed && Date.now() < get().revealUntil) armIdleTimer()
    else cover()
  }, Math.max(0, get().revealUntil - Date.now()))
}

// Any action by the user while figures are shown restarts the idle time.
let lastActivity = 0
function onActivity() {
  if (!get().revealed) return
  const now = Date.now()
  if (now - lastActivity < 400) return // pointermove/scroll fire a lot
  lastActivity = now
  set({ revealUntil: now + revealMs() })
}
const ACTIVITY_EVENTS = ['pointerdown', 'pointermove', 'keydown', 'wheel', 'scroll', 'touchstart', 'touchmove']

function cover() {
  clearTimer()
  if (graceTimer) clearTimeout(graceTimer)
  graceTimer = null
  set({ revealed: false, revealUntil: 0 })
}

// Cover now (or after a short grace); coming back in time cancels it.
function coverSoon(ms) {
  if (!get().revealed) return
  if (!ms) return cover()
  if (graceTimer) clearTimeout(graceTimer)
  graceTimer = setTimeout(cover, ms)
}
function cancelGrace() {
  if (graceTimer) clearTimeout(graceTimer)
  graceTimer = null
}

function onVisibility() {
  if (document.visibilityState === 'hidden') coverSoon(limit('hiddenMs', HIDDEN_MS))
  else cancelGrace()
}
function onBlur() {
  coverSoon(limit('blurMs', BLUR_MS))
}
function onFocus() {
  cancelGrace()
}
function onPageHide() {
  cover()
}

export const mask = {
  get state() {
    return get()
  },
  /** true while figures must be shown as dots */
  // "Ẩn số liệu" was removed from the app: figures are always shown (the store stays so the components that read it keep working)
  masked: () => false,
  /** Turning the mask ON needs no password. */
  enable() {
    set({ enabled: true, revealed: false })
    clearTimer()
    writeEnabled(true)
  },
  /** Call only after the password was verified. */
  disable() {
    set({ enabled: false, revealed: false })
    clearTimer()
    writeEnabled(false)
  },
  /** Call only after the password was verified. */
  reveal() {
    set({ revealed: true, revealUntil: Date.now() + revealMs() })
    lastActivity = Date.now()
    armIdleTimer()
  },
  /** Idle time after which figures are covered again; remembered per device. */
  setRevealSeconds(n) {
    if (!REVEAL_CHOICES.includes(n)) return
    set({ revealSeconds: n })
    writeSeconds(n)
  },
  cover,
  /**
   * A screen (or the shared mask bar) calls attach() on mount and detach() on unmount; the browser listeners exist
   * while at least one screen uses the mask. Leaving a screen always covers the figures again.
   */
  attach() {
    users++
    if (users > 1) return
    document.addEventListener('visibilitychange', onVisibility)
    window.addEventListener('blur', onBlur)
    window.addEventListener('focus', onFocus)
    window.addEventListener('pagehide', onPageHide)
    for (const ev of ACTIVITY_EVENTS) window.addEventListener(ev, onActivity, { capture: true, passive: true })
  },
  detach() {
    users = Math.max(0, users - 1)
    cover()
    if (users > 0) return
    document.removeEventListener('visibilitychange', onVisibility)
    window.removeEventListener('blur', onBlur)
    window.removeEventListener('focus', onFocus)
    window.removeEventListener('pagehide', onPageHide)
    for (const ev of ACTIVITY_EVENTS) window.removeEventListener(ev, onActivity, { capture: true })
  },
}

/** Hook: re-renders when the mask state changes; returns whether figures are masked (always false, see above). */
export const useMasked = () => useMaskStore(() => mask.masked())
