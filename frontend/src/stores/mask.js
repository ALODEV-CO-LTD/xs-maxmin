// "Ẩn số liệu" (hide figures) - a screen-only mask, not encryption. When
// `enabled` (persisted per device), every figure shows as "••••" until the
// user re-enters the account password (POST /me/verify-password, done by
// PasswordPromptDialog) which reveals them for a SHORT time (30 s by default;
// the user can pick 10 s / 20 s / 30 s / 1 min / 5 min, remembered per device).
// They are covered again as soon as ANY of these happens: the time is up, the
// window loses focus (another app / window in front, a screenshot tool taking
// over), the tab goes to the background, or the page is left. The shorter the
// time they are on screen, the smaller the chance for a screenshot or a
// glance over the shoulder.
//
// Components read `mask.masked` (see MaskedValue.vue) and never receive the
// real value while it is true.
import { computed, reactive } from 'vue'

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
    return localStorage.getItem(KEY) === '1'
  } catch (_) {
    return false
  }
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
const state = reactive({ enabled: readEnabled(), revealed: false, revealSeconds: readSeconds(), revealUntil: 0 })
let revealTimer = null
let graceTimer = null
let listening = false

function clearTimer() {
  if (revealTimer) clearTimeout(revealTimer)
  revealTimer = null
}

function cover() {
  clearTimer()
  if (graceTimer) clearTimeout(graceTimer)
  graceTimer = null
  state.revealed = false
  state.revealUntil = 0
}

// Cover now (or after a short grace); coming back in time cancels it.
function coverSoon(ms) {
  if (!state.revealed) return
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
  state,
  /** true while figures must be shown as dots */
  masked: computed(() => state.enabled && !state.revealed),
  /** Turning the mask ON needs no password. */
  enable() {
    state.enabled = true
    state.revealed = false
    clearTimer()
    writeEnabled(true)
  },
  /** Call only after the password was verified. */
  disable() {
    state.enabled = false
    state.revealed = false
    clearTimer()
    writeEnabled(false)
  },
  /** Call only after the password was verified. */
  reveal() {
    const ms = limit('revealMs', state.revealSeconds * 1000)
    state.revealed = true
    state.revealUntil = Date.now() + ms
    clearTimer()
    revealTimer = setTimeout(cover, ms)
  },
  /** How long figures stay visible after the password; remembered per device. */
  setRevealSeconds(n) {
    if (!REVEAL_CHOICES.includes(n)) return
    state.revealSeconds = n
    writeSeconds(n)
  },
  cover,
  /** A page calls attach() on mount and detach() on unmount. */
  attach() {
    if (listening) return
    document.addEventListener('visibilitychange', onVisibility)
    window.addEventListener('blur', onBlur)
    window.addEventListener('focus', onFocus)
    window.addEventListener('pagehide', onPageHide)
    listening = true
  },
  detach() {
    document.removeEventListener('visibilitychange', onVisibility)
    window.removeEventListener('blur', onBlur)
    window.removeEventListener('focus', onFocus)
    window.removeEventListener('pagehide', onPageHide)
    listening = false
    cover()
  },
}
