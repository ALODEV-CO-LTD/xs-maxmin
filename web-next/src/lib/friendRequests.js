// Pure helpers for friend requests (adding a friend needs the other person's
// acceptance). Kept free of Vue/API imports so node tests can load it.

// Reads the answer of POST /me/friends. `name` is the display name of the person
// we asked for (used when the server does not echo it back).
//   -> { kind: 'friends', friend } | { kind: 'pending', request, message }
export function interpretAddResponse(res, name = '') {
  if (res && res.status === 'friends' && res.friend) {
    return { kind: 'friends', friend: res.friend, message: 'Đã là bạn bè' }
  }
  // Legacy shape (a bare friend row) still means "added".
  if (res && !res.status && res.id && res.name) {
    return { kind: 'friends', friend: res, message: 'Đã là bạn bè' }
  }
  const request = res?.request || null
  const who = request?.toName || name || 'họ'
  return { kind: 'pending', request, message: `Đã gửi lời mời kết bạn tới ${who}. Họ cần chấp nhận.` }
}

// What the button of a search row does.
//   -> { label, action: 'add' | 'accept' | 'none', disabled }
export function searchAction(r) {
  if (r.requestState === 'outgoing') return { label: 'Đã gửi lời mời', action: 'none', disabled: true }
  if (r.requestState === 'incoming') return { label: 'Chấp nhận', action: 'accept', disabled: false }
  return { label: 'Kết bạn', action: 'add', disabled: false }
}

// Normalises GET /me/friend-requests.
export function normalizeRequests(res) {
  const list = (v) => (Array.isArray(v) ? v : [])
  return { incoming: list(res?.incoming), outgoing: list(res?.outgoing) }
}

export function removeRequest(list, id) {
  return list.filter((x) => x.id !== id)
}

// Adds `friend` to the list unless a row with the same id is already there.
export function upsertFriend(friends, friend) {
  if (!friend || friends.some((f) => f.id === friend.id)) return friends
  return [friend, ...friends]
}

// The incoming request of a given sender, if any (search row "Chấp nhận").
export function incomingFrom(incoming, userId) {
  return incoming.find((x) => x.fromId === userId) || null
}

export function badgeText(n) {
  const v = Number(n) || 0
  return v > 99 ? '99+' : v > 0 ? String(v) : ''
}

/**
 * Whether the "Lời mời kết bạn" block is shown. With the bottom bar it lives on the Danh bạ tab; the web build has NO bottom
 * bar (the only list is "chats"), so there it must show above that list or the requests could never be reached.
 */
export function showRequestsBlock(tab, hasBottomNav, hasRequests) {
  if (!hasRequests) return false
  return hasBottomNav ? tab === 'contacts' : tab === 'chats' || tab === 'contacts'
}
