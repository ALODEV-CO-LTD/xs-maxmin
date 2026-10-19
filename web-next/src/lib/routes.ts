// Route table of the app (port of frontend/src/router/index.js). `kind` replaces the Vue meta flags:
//   public     /login, /register (no shell, no auth)
//   user       customer area (admins are sent to their own area)
//   shared     any signed-in role (/account)
//   admin      role === 'admin' (+ optional `perm` / `rootOnly`)
// Old addresses that were redirects in the Vue router are in REDIRECTS (also mirrored for nginx in deploy/).
export type RouteKind = 'public' | 'user' | 'shared' | 'admin'
export interface AppRoute { path: string; title: string; kind: RouteKind; perm?: string | string[]; rootOnly?: boolean }

export const ROUTES: AppRoute[] = [
  { path: '/login', title: 'Đăng nhập', kind: 'public' },
  { path: '/register', title: 'Đăng ký', kind: 'public' },
  { path: '/entries', title: 'Nhập số', kind: 'user' },
  { path: '/results', title: 'Nhập kết quả', kind: 'user' },
  { path: '/scoring', title: 'Tính điểm', kind: 'user' },
  { path: '/scoring-settings', title: 'Cấu hình tính điểm', kind: 'user' },
  { path: '/customers', title: 'Khách hàng', kind: 'user' },
  { path: '/friends', title: 'Tin nhắn', kind: 'user' }, // a thread opens as /friends?thread=<id>
  { path: '/account', title: 'Tài khoản', kind: 'shared' },
  { path: '/admin/users', title: 'Quản lý khách hàng', kind: 'admin', perm: 'users.view' },
  { path: '/admin/stats', title: 'Thống kê', kind: 'admin', perm: 'stats.view' },
  { path: '/admin/settings', title: 'Cài đặt hệ thống', kind: 'admin', perm: ['settings.manage', 'security.view', 'security.policy', 'backups.manage'] },
  { path: '/admin/payment-requests', title: 'Yêu cầu thanh toán', kind: 'admin', perm: 'payments.manage' },
  { path: '/admin/messages', title: 'Phản hồi khách hàng', kind: 'admin', perm: 'support.messages' }, // a thread: ?user=<id>
  { path: '/admin/notices', title: 'Thông báo & bảo trì', kind: 'admin', perm: ['announcements.manage', 'maintenance.manage'] },
  { path: '/admin/staff', title: 'Phân quyền Admin', kind: 'admin', rootOnly: true },
]

// path -> where it goes (old links, notifications, bookmarks)
export const REDIRECTS: Record<string, string> = {
  '/packages': '/account?tab=packages',
  '/payments': '/account?tab=packages',
  '/admin/renewals': '/admin/payment-requests?view=renewals',
  '/admin/backups': '/admin/settings?tab=backups',
  '/admin/security-policy': '/admin/settings?tab=policy',
}

export const routeOf = (path: string) => ROUTES.find((r) => path === r.path || path.startsWith(r.path + '/'))
