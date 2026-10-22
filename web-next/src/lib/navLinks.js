// Navigation entries of the app shell (sidebar on desktop, dropdown on phones).
// { path, label, icon, perm? (admin permission(s), any of), root? (root admin only), badge? ('friends' | 'admin-messages') }
export const USER_LINKS = [
  { path: '/entries', label: 'Nhập số', icon: 'pencil' },
  { path: '/results', label: 'Nhập kết quả', icon: 'pencil-line' },
  { path: '/scoring', label: 'Tính điểm', icon: 'calculator' },
  { path: '/customers', label: 'Khách hàng', icon: 'users' },
  { path: '/scoring-settings', label: 'Cấu hình tính điểm', icon: 'sliders' },
  { path: '/friends', label: 'Nhắn tin', icon: 'message-circle-more', badge: 'friends' },
  { path: '/account', label: 'Tài khoản', icon: 'user' },
]

export const ADMIN_LINKS = [
  { perm: 'stats.view', path: '/admin/stats', label: 'Thống kê', icon: 'chart-column-increasing' },
  { perm: 'users.view', path: '/admin/users', label: 'Khách hàng', icon: 'users' },
  { perm: 'payments.manage', path: '/admin/payment-requests', label: 'Thanh toán & gia hạn', icon: 'pay' },
  { perm: 'support.messages', path: '/admin/messages', label: 'Phản hồi', icon: 'feedback', badge: 'admin-messages' },
  { perm: ['announcements.manage', 'maintenance.manage'], path: '/admin/notices', label: 'Thông báo', icon: 'megaphone' },
  { perm: ['settings.manage', 'security.view', 'security.policy', 'backups.manage'], path: '/admin/settings', label: 'Cài đặt', icon: 'settings' },
  // Admin shares /account with customers (change password...). Admin has no "Bạn bè": contact with customers goes
  // through "Phản hồi" above.
  { root: true, path: '/admin/staff', label: 'Phân quyền', icon: 'user-admin' },
  { path: '/account', label: 'Tài khoản', icon: 'user' },
]

/** The nav entries this account sees (customers: all user links; admins: filtered by permission / root). */
export function linksFor(isAdmin, isRoot, can) {
  return isAdmin ? ADMIN_LINKS.filter((l) => (l.root ? isRoot : !l.perm || can(l.perm))) : USER_LINKS
}

