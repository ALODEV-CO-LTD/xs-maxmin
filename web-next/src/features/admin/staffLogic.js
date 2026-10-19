// Pure helpers of the Phân quyền Admin screen (/admin/staff).

// Quick starting points: they only tick boxes, the Admin can still change them.
export const PRESETS = [
  { label: 'Chăm sóc khách hàng', keys: ['users.view', 'users.recovery', 'support.messages'] },
  { label: 'Quản lý hệ thống', keys: ['users.view', 'stats.view', 'announcements.manage', 'maintenance.manage', 'settings.manage', 'backups.manage', 'security.view'] },
]

/** New list with `key` added when missing, removed when present. */
export function togglePerm(list, key) {
  return list.includes(key) ? list.filter((k) => k !== key) : [...list, key]
}

/** Same set of permissions (order ignored). */
export const samePerms = (a, b) => a.length === b.length && a.every((k) => b.includes(k))

/** "Lưu quyền" is allowed only for a non-empty, changed selection. */
export const canSavePerms = (edited, saved) => edited.length > 0 && !samePerms(edited, saved)
