// Pure helpers of Phản hồi khách hàng (/admin/messages): list filter, time labels, day dividers.

export function noAccents(s) {
  return String(s || '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/đ/g, 'd')
    .replace(/Đ/g, 'D')
    .toLowerCase()
}

export const awaitingCountOf = (conversations) => conversations.filter((c) => c.awaitingReply).length

/** Conversations matching the search (name or username, accent-insensitive) and the "Chưa trả lời" filter. */
export function filterConversations(conversations, query, onlyAwaiting) {
  const q = noAccents(String(query || '').trim())
  return conversations.filter((c) => {
    if (onlyAwaiting && !c.awaitingReply) return false
    if (!q) return true
    return noAccents(c.userName).includes(q) || noAccents(c.username).includes(q)
  })
}

/** List time: hh:mm today, "Hôm qua", else dd/mm. */
export function shortTime(iso, now = new Date()) {
  const d = new Date(iso)
  if (!iso || isNaN(d)) return ''
  const startOf = (x) => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime()
  const days = Math.round((startOf(now) - startOf(d)) / 86400000)
  if (days === 0) return d.toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit' })
  if (days === 1) return 'Hôm qua'
  return d.toLocaleDateString('vi-VN', { day: '2-digit', month: '2-digit' })
}

export function expiryLabel(iso) {
  const d = new Date(iso)
  return !iso || isNaN(d) ? '' : d.toLocaleDateString('vi-VN', { day: '2-digit', month: '2-digit', year: 'numeric' })
}

/** "@user · <package> · hết hạn dd/mm/yyyy" under the customer's name. */
export function threadSubtitle(c, labelOf = (x) => x) {
  if (!c) return ''
  const parts = []
  if (c.username) parts.push(`@${c.username}`)
  if (c.packageType) parts.push(labelOf(c.packageType))
  if (c.packageExpiresAt) parts.push(`hết hạn ${expiryLabel(c.packageExpiresAt)}`)
  return parts.join(' · ')
}

export const avatarLetter = (name) => (name || '?').charAt(0).toUpperCase()
export const unreadBadge = (n) => (n > 9 ? '9+' : String(n))

const dayKey = (iso) => {
  const d = new Date(iso)
  return isNaN(d) ? '' : `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`
}
export function dayLabel(iso, now = new Date()) {
  const d = new Date(iso)
  if (isNaN(d)) return ''
  const yesterday = new Date(now)
  yesterday.setDate(now.getDate() - 1)
  if (dayKey(iso) === dayKey(now)) return 'Hôm nay'
  if (dayKey(iso) === dayKey(yesterday)) return 'Hôm qua'
  return d.toLocaleDateString('vi-VN', { day: '2-digit', month: '2-digit', year: 'numeric' })
}
export function timeLabel(iso) {
  const d = new Date(iso)
  return isNaN(d) ? '' : d.toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit' })
}

/** Flat list with a date divider before the first message of each day. */
export function withDayDividers(messages, now = new Date()) {
  const out = []
  let last = ''
  for (const m of messages) {
    const k = dayKey(m.createdAt)
    if (k !== last) {
      out.push({ divider: true, id: `d-${k}`, label: dayLabel(m.createdAt, now) })
      last = k
    }
    out.push(m)
  }
  return out
}
