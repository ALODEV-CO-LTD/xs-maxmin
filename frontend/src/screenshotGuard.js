// Desktop screenshot guard (K33). A web page cannot block the operating system's
// screenshot tools, but it can make sure the screen is already covered when they
// run. The shortcuts all start with a modifier chord, so the screen is covered
// the moment that chord is held, BEFORE the key that takes the picture:
//   macOS     Cmd+Shift+3 / 4 / 5 (and Ctrl variants that copy to the clipboard)
//   Windows   Win+Shift+S (Snipping Tool)
// The cover stays until the chord is released, at least MIN_COVER_MS has passed
// AND fresh input reaches the page again. While a macOS crosshair selection
// (Cmd+Shift+4) or the Cmd+Shift+5 toolbar is open the page gets no mouse
// events, so the cover stays on for the whole selection and lifts when the
// pointer comes back. A hard timeout (MAX_COVER_MS) means it can never lock
// anyone out.
// PrintScreen (Windows/Linux) is delivered to the page only AFTER the picture was
// taken: it cannot be prevented, so the screen is covered for a moment and the
// clipboard is emptied to remove a copy that went there.
//
// Limits (be honest in the UI): this does not stop phones (hardware buttons),
// another device filming the screen, or a person who turns this script off.
// Only an app can truly block screenshots.
const MIN_COVER_MS = 900
const MAX_COVER_MS = 20000
const PRINT_COVER_MS = 2500
const CLASS = 'shot-guard'
const STYLE_ID = 'shot-guard-style'

let enabled = true
let started = false
let covered = false
let coveredAt = 0
let freshInput = false
let hardTimer = null
let softTimer = null
let held = { meta: false, shift: false }

function injectStyle() {
  if (document.getElementById(STYLE_ID)) return
  const st = document.createElement('style')
  st.id = STYLE_ID
  // A pseudo-element on <html> is painted in the very next frame and does not depend on Vue.
  st.textContent =
    `html.${CLASS}::after{content:"Nội dung đang được bảo vệ";position:fixed;inset:0;z-index:2147483647;` +
    `display:flex;align-items:center;justify-content:center;background:#000;color:#555;font:600 15px system-ui,sans-serif;` +
    `pointer-events:none}html.${CLASS} body{visibility:hidden!important}`
  document.head.appendChild(st)
}

// Listeners told when a screenshot shortcut is detected (e.g. to warn the chat friend).
const listeners = new Set()
export function onScreenshotAttempt(fn) {
  listeners.add(fn)
  return () => listeners.delete(fn)
}
function emitAttempt() {
  for (const fn of listeners) {
    try {
      fn()
    } catch {
      /* a listener must never break the guard */
    }
  }
}

function cover() {
  if (!enabled) return
  injectStyle()
  if (!covered) emitAttempt()
  covered = true
  coveredAt = Date.now()
  freshInput = false
  document.documentElement.classList.add(CLASS)
  clearTimeout(hardTimer)
  hardTimer = setTimeout(uncover, MAX_COVER_MS)
}

function uncover() {
  covered = false
  clearTimeout(hardTimer)
  clearTimeout(softTimer)
  document.documentElement.classList.remove(CLASS)
}

// Lift the cover once it is safe: chord released, minimum time passed, fresh input seen.
function maybeUncover() {
  if (!covered || held.meta && held.shift || !freshInput) return
  const left = MIN_COVER_MS - (Date.now() - coveredAt)
  if (left > 0) {
    clearTimeout(softTimer)
    softTimer = setTimeout(maybeUncover, left)
    return
  }
  uncover()
}

function clearClipboard() {
  try {
    navigator.clipboard?.writeText(' ').catch(() => {})
  } catch {
    /* clipboard blocked: nothing more can be done */
  }
}

function onKeyDown(e) {
  if (e.key === 'Meta' || e.key === 'OS') held.meta = true // 'OS' = Windows key in older Firefox/Edge
  if (e.key === 'Shift') held.shift = true
  if (e.metaKey) held.meta = true
  if (e.shiftKey) held.shift = true
  if (held.meta && held.shift) cover()
  else if (covered && e.key !== 'Meta' && e.key !== 'OS' && e.key !== 'Shift') {
    freshInput = true
    maybeUncover()
  }
}

function onKeyUp(e) {
  if (e.key === 'Meta' || e.key === 'OS') held.meta = false
  if (e.key === 'Shift') held.shift = false
  if (e.key === 'PrintScreen') {
    covered = false // a PrintScreen always counts as a new attempt
    cover()
    clearClipboard()
    clearTimeout(softTimer)
    freshInput = true
    softTimer = setTimeout(maybeUncover, PRINT_COVER_MS)
    return
  }
  if (covered) maybeUncover()
}

// Input that proves the person is back in the page after a selection / toolbar.
function onFresh(e) {
  if (!covered) return
  // Pointer events carry the modifier state: it fixes a "held" flag whose keyup never came
  // (the screenshot tool consumed it).
  if (e && typeof e.metaKey === 'boolean') {
    held.meta = e.metaKey
    held.shift = e.shiftKey
  }
  freshInput = true
  maybeUncover()
}

// Modifier keys released while another app had focus never reach us: forget them.
function onBlur() {
  held = { meta: false, shift: false }
}

export function setScreenshotGuardEnabled(on) {
  enabled = on
  if (!on) uncover()
}

export function startScreenshotGuard() {
  if (started || typeof window === 'undefined') return
  started = true
  window.addEventListener('keydown', onKeyDown, true)
  window.addEventListener('keyup', onKeyUp, true)
  window.addEventListener('blur', onBlur)
  for (const ev of ['mousemove', 'pointerdown', 'touchstart', 'wheel', 'focus'])
    window.addEventListener(ev, onFresh, { capture: true, passive: true })
}

export function stopScreenshotGuard() {
  if (!started) return
  started = false
  uncover()
  window.removeEventListener('keydown', onKeyDown, true)
  window.removeEventListener('keyup', onKeyUp, true)
  window.removeEventListener('blur', onBlur)
  for (const ev of ['mousemove', 'pointerdown', 'touchstart', 'wheel', 'focus'])
    window.removeEventListener(ev, onFresh, { capture: true })
}
