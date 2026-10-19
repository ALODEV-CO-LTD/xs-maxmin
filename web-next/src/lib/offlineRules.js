// Pure decision helpers for the offline queue (kept import-free so they can be unit tested).

/** HTTP statuses where the request itself may be fine and a later retry can succeed. */
const RETRY_STATUSES = new Set([401, 408, 425, 429])

/** True when a failed queued op must be kept and retried later (not dropped). */
export function shouldKeepForRetry(status) {
  return RETRY_STATUSES.has(status) || status >= 500
}

/** Fields of `current` that differ from what was `sent` (an edit made while the request
 *  was in flight). Returns null when nothing changed. */
export function changesDuringFlight(sent, current) {
  const out = {}
  let any = false
  for (const key of Object.keys(current || {})) {
    if (JSON.stringify(current[key]) !== JSON.stringify((sent || {})[key])) {
      out[key] = current[key]
      any = true
    }
  }
  return any ? out : null
}
