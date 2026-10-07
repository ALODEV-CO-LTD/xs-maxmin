// "Ẩn số liệu" (hide figures) - a screen-only mask, not encryption. When
// `enabled` (persisted per device), every figure shows as "••••" until the
// user re-enters the account password (POST /me/verify-password, done by
// PasswordPromptDialog) which reveals them for 5 minutes. They are covered
// again when the time is up, when the page is left, or when the tab was in
// the background for more than 60 seconds.
//
// Components read `mask.masked` (see MaskedValue.vue) and never receive the
// real value while it is true.
import { computed, reactive } from 'vue'

const KEY = 'xoso_mask_enabled'
const REVEAL_MS = 5 * 60 * 1000
const HIDDEN_MS = 60 * 1000

// Test hook: window.__MASK_TEST = { revealMs, hiddenMs } shortens the timers.
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
function writeEnabled(on) {
  try {
    localStorage.setItem(KEY, on ? '1' : '0')
  } catch (_) {
    // Private mode etc.: the switch just won't survive a reload.
  }
}

const state = reactive({ enabled: readEnabled(), revealed: false })
let revealTimer = null
let hiddenAt = 0
let listening = false

function clearTimer() {
  if (revealTimer) clearTimeout(revealTimer)
  revealTimer = null
}

function cover() {
  clearTimer()
  state.revealed = false
}

function onVisibility() {
  if (document.visibilityState === 'hidden') {
    hiddenAt = Date.now()
  } else if (state.revealed && hiddenAt && Date.now() - hiddenAt > limit('hiddenMs', HIDDEN_MS)) {
    cover()
  }
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
    state.revealed = true
    clearTimer()
    revealTimer = setTimeout(cover, limit('revealMs', REVEAL_MS))
  },
  cover,
  /** A page calls attach() on mount and detach() on unmount. */
  attach() {
    if (listening) return
    document.addEventListener('visibilitychange', onVisibility)
    listening = true
  },
  detach() {
    document.removeEventListener('visibilitychange', onVisibility)
    listening = false
    cover()
  },
}
