// Light/Dark theme controller.
//
// The choice is stored in localStorage ('xoso_theme' = 'light' | 'dark') and applied as <html data-theme="...">, which
// tokens.css keys off. With nothing stored we follow the OS (prefers-color-scheme) and keep following it.
// layout.tsx runs the same lookup inline before first paint to avoid a flash.
import { create } from 'zustand'

const KEY = 'xoso_theme'
const mq = () => (typeof window !== 'undefined' && window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null)

function stored() {
  try {
    const v = localStorage.getItem(KEY)
    return v === 'light' || v === 'dark' ? v : null
  } catch {
    return null
  }
}

function resolve() {
  return stored() || (mq()?.matches ? 'dark' : 'light')
}

/** The theme currently in effect: `useThemeStore((s) => s.theme)` ('light' | 'dark'). */
export const useThemeStore = create(() => ({ theme: 'light' }))
export const getTheme = () => useThemeStore.getState().theme

function apply(value) {
  useThemeStore.setState({ theme: value })
  if (typeof document !== 'undefined') document.documentElement.dataset.theme = value
}

let listening = false
export function initTheme() {
  apply(resolve())
  // No explicit choice yet -> track OS changes live.
  if (!listening) {
    listening = true
    mq()?.addEventListener?.('change', () => {
      if (!stored()) apply(resolve())
    })
  }
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
  setTheme(getTheme() === 'dark' ? 'light' : 'dark')
}
