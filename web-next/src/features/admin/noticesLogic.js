// Pure helpers of Thông báo & bảo trì (/admin/notices): which tabs an account sees and keyboard tab movement.

export const KINDS = [
  { value: 'maintenance', label: 'Bảo trì' },
  { value: 'policy', label: 'Đổi chính sách' },
  { value: 'info', label: 'Thông báo chung' },
]
export const kindLabel = (k) => KINDS.find((x) => x.value === k)?.label || k

/** Tabs by right: announcements.manage -> Đã gửi + Gửi thông báo; maintenance.manage -> Chế độ bảo trì. */
export function buildTabs({ canAnnounce, canMaintenance, sentCount = 0 }) {
  return [
    ...(canAnnounce
      ? [
          { key: 'sent', label: `Đã gửi (${sentCount})` },
          { key: 'compose', label: 'Gửi thông báo' },
        ]
      : []),
    ...(canMaintenance ? [{ key: 'maintenance', label: 'Chế độ bảo trì' }] : []),
  ]
}

/** The wanted tab (?tab=) when this account has it, else the first one. */
export const resolveTab = (tabs, wanted) => (tabs.some((t) => t.key === wanted) ? wanted : tabs[0]?.key)

/** Key of the tab reached by ArrowLeft/ArrowRight (wraps around); null for other keys. */
export function nextTabKey(tabs, active, key) {
  const i = tabs.findIndex((t) => t.key === active)
  const next = key === 'ArrowRight' ? i + 1 : key === 'ArrowLeft' ? i - 1 : null
  if (next === null || !tabs.length) return null
  return tabs[(next + tabs.length) % tabs.length].key
}
