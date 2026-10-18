// A peer-supplied timestamp is not trusted: keep it within a window around the time we
// received the message, so a friend cannot backdate (or future-date) what we store.
export const MAX_BACKDATE_MS = 5 * 60 * 1000

export function clampReceivedTs(ts, now = Date.now()) {
  const n = Number(ts)
  if (!Number.isFinite(n)) return now
  return Math.min(now, Math.max(now - MAX_BACKDATE_MS, n))
}
