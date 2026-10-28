// Pure helpers of the lock screen's wrong-password feedback (same texts as the app: privacy_gate.dart).
// POST /me/verify-password answers 403 `{error, failedAttempts, maxAttempts, attemptsLeft}` on a wrong password and
// 429 `{error, retryAfterSeconds}` while the server has locked the tries.

/** "45 giây", "1 phút 05 giây", "15 phút". */
export function formatLockWait(seconds) {
  const s = Math.max(0, Math.floor(Number(seconds) || 0))
  if (s < 60) return `${s} giây`
  const m = Math.floor(s / 60)
  const r = s % 60
  return r === 0 ? `${m} phút` : `${m} phút ${String(r).padStart(2, '0')} giây`
}

/** What a refused unlock tells the person: how many wrong tries so far and how many are left before the temporary lock. */
export function wrongMessage(message, data) {
  const failed = data?.failedAttempts
  const max = data?.maxAttempts
  const left = data?.attemptsLeft
  if (![failed, max, left].every((v) => typeof v === 'number')) return message
  const tail = left <= 0 ? 'Lần sai tiếp theo sẽ bị khoá tạm.' : `Còn ${left} lần thử trước khi bị khoá tạm.`
  return `${message}. Đã sai ${failed}/${max} lần. ${tail}`
}

/** Seconds of a 429 lock: `retryAfterSeconds`, else the "N giây" of the message, else 30 (never less than 1). */
export function lockSeconds(message, data) {
  const n = data?.retryAfterSeconds
  if (typeof n === 'number') return Math.max(1, Math.round(n))
  const m = /(\d+) giây/.exec(String(message || ''))
  return Math.max(1, m ? Number(m[1]) : 30)
}

/** Seconds left until `deadline` (ms since epoch), counted by the clock so a throttled background timer cannot drift. */
export const lockLeftAt = (deadline, now = Date.now()) => Math.max(0, Math.ceil((deadline - now) / 1000))
