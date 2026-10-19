// Small helpers shared by the admin screens (kept here so src/lib stays untouched by this port).
import { ApiError } from '@/lib/api'

/** User-facing text of a failed API call: the server's own message, else `fallback`. */
export const errMsg = (err, fallback) => (err instanceof ApiError ? err.message : fallback)

export const fmtDateTime = (iso) => (iso ? new Date(iso).toLocaleString('vi-VN') : '-')
export const fmtDate = (iso) => (iso ? new Date(iso).toLocaleDateString('vi-VN') : '-')

/** Copy text; false when the clipboard is blocked (the value stays on screen to copy by hand). */
export async function copyToClipboard(text) {
  try {
    await navigator.clipboard.writeText(text)
    return true
  } catch {
    return false
  }
}
