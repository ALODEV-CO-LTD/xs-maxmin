// Light/Dark theme controller.
//
// The choice is stored in localStorage ('xoso_theme' = 'light' | 'dark') and
// applied as <html data-theme="...">, which styles/tokens.css keys off. With
// nothing stored we follow the OS (prefers-color-scheme) and keep following it.
// index.html runs the same lookup inline before first paint to avoid a flash.
import { ref } from 'vue'

const KEY = 'xoso_theme'
const mq = typeof window !== 'undefined' ? window.matchMedia('(prefers-color-scheme: dark)') : null

function stored() {
  try {
    const v = localStorage.getItem(KEY)
    return v === 'light' || v === 'dark' ? v : null
  } catch {
    return null
  }
}

function resolve() {
  return stored() || (mq && mq.matches ? 'dark' : 'light')
}

// The theme currently in effect ('light' | 'dark').
export const theme = ref(resolve())

function apply(value) {
  theme.value = value
  document.documentElement.dataset.theme = value
}

export function initTheme() {
  apply(resolve())
  // No explicit choice yet -> track OS changes live.
  mq?.addEventListener?.('change', () => {
    if (!stored()) apply(resolve())
  })
}

export function setTheme(value) {
  try {
    localStorage.setItem(KEY, value)
  } catch {
    /* storage unavailable - theme still applies for this session */
  }
  apply(value)
}

export function toggleTheme() {
  setTheme(theme.value === 'dark' ? 'light' : 'dark')
}
