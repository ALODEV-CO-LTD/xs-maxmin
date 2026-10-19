// Group chats (no server involved). A group lives on its members' devices only: the creator tells every member (an empty end-to-end
// encrypted "group-new" message carrying the name and the member list) and every group message carries the group again, so a device
// that missed the first message still learns the group. Each message is encrypted once per member and relayed like a 1:1 message.
// Same wire format as the app (app/lib/features/friends/chat_models.dart `ChatGroup`).

export const GROUP_PREFIX = 'g-'
export const isGroupId = (id) => typeof id === 'string' && id.startsWith(GROUP_PREFIX)

// Header of a group as it travels inside every group message.
export const groupHeader = (g) => ({ i: g.id, n: g.name, c: g.creatorId, u: g.updatedAt, m: g.members.map((m) => [m.id, m.name]) })

// Reads and validates a group header; null when it is not a well-formed group.
export function groupFromHeader(h) {
  if (!h || typeof h !== 'object') return null
  const { i, n, c, m, u } = h
  if (typeof i !== 'string' || !isGroupId(i) || i.length > 64 || typeof n !== 'string' || typeof c !== 'string' || !Array.isArray(m)) return null
  const members = []
  for (const x of m) {
    if (Array.isArray(x) && x.length >= 2 && typeof x[0] === 'string' && typeof x[1] === 'string') members.push({ id: x[0], name: x[1].slice(0, 80) })
  }
  if (members.length < 2 || members.length > 50) return null
  return { id: i, name: n.slice(0, 60), creatorId: c, updatedAt: Number(u) || 0, members }
}
