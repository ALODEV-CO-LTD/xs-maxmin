// Route conventions (shared across the whole app):
//   - `meta.public: true`            -> no auth required, and App.vue does
//                                        NOT wrap it in the AppShell (top
//                                        bar + nav). Only /login, /register
//                                        (and their step2/wipe sub-steps,
//                                        which live on the same view).
//   - default (no `meta.public`)     -> requires a logged-in user (any
//                                        role). Guard redirects to /login
//                                        with `?redirect=<path>` if missing.
//   - `meta.userOnly: true`          -> customer-area page; admins are sent to
//                                        /admin/users instead (their own area).
//                                        Pages without it (e.g. /account) are shared.
//   - `meta.requiresAdmin: true`     -> additionally requires role==='admin'.
//                                        Guard redirects non-admins to `/`
//                                        (not a broken page).
//   - `meta.parent`                  -> route name of the parent screen; AppShell
//                                        shows a "Quay lại" button to it (K44).
//   - `meta.title`                   -> human-readable page title, used by
//                                        PlaceholderView and can be reused
//                                        for <title>/breadcrumbs by real
//                                        views too.
//   - Real view components for the user/admin areas replace the
//     `component: PlaceholderView` lines below in place - keep the `path`/
//     `name`/`meta` as-is so nav links and guards elsewhere don't break.
import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '../stores/auth'
import LoginView from '../views/LoginView.vue'
import RegisterView from '../views/RegisterView.vue'
import EntriesView from '../views/EntriesView.vue'
import ResultsView from '../views/ResultsView.vue'
import ScoringView from '../views/ScoringView.vue'
import ScoringSettingsView from '../views/ScoringSettingsView.vue'
import CustomersView from '../views/CustomersView.vue'
import FriendsView from '../views/FriendsView.vue'
import { useNotifyStore } from '../stores/notify'
import PackagesView from '../views/PackagesView.vue'
import AccountView from '../views/AccountView.vue'
import AdminUsersView from '../views/admin/UsersView.vue'
import AdminStatsView from '../views/admin/StatsView.vue'
import AdminSettingsView from '../views/admin/SettingsView.vue'
import AdminRenewalsView from '../views/admin/RenewalsView.vue'
import AdminPaymentRequestsView from '../views/admin/PaymentRequestsView.vue'
import AdminMessagesView from '../views/admin/MessagesView.vue'
import AdminNoticesView from '../views/admin/NoticesView.vue'
import AdminBackupsView from '../views/admin/BackupsView.vue'

const routes = [
  { path: '/login', name: 'login', component: LoginView, meta: { public: true, title: 'Đăng nhập' } },
  { path: '/register', name: 'register', component: RegisterView, meta: { public: true, title: 'Đăng ký' } },

  // User area
  { path: '/', name: 'home', redirect: () => (useAuthStore().isAdmin ? useAuthStore().adminHome() : '/entries') },
  { path: '/entries', name: 'entries', component: EntriesView, meta: { userOnly: true, title: 'Nhập số' } },
  { path: '/results', name: 'results', component: ResultsView, meta: { userOnly: true, title: 'Nhập kết quả' } },
  { path: '/scoring', name: 'scoring', component: ScoringView, meta: { userOnly: true, title: 'Tính điểm' } },
  {
    path: '/scoring-settings',
    name: 'scoring-settings',
    component: ScoringSettingsView,
    meta: { userOnly: true, title: 'Cấu hình tính điểm', parent: 'scoring' },
  },
  { path: '/customers', name: 'customers', component: CustomersView, meta: { userOnly: true, title: 'Khách hàng' } },
  { path: '/friends', name: 'friends', component: FriendsView, meta: { userOnly: true, title: 'Bạn bè & tin nhắn' } },
  {
    path: '/friends/:friendId',
    name: 'friend-thread',
    component: FriendsView,
    meta: { userOnly: true, title: 'Bạn bè & tin nhắn' },
  },
  // Phản hồi is now a popover in the top bar (components/SupportChat.vue); this old address
  // (message toasts, bookmarks) just opens it on top of the page the person is already on.
  {
    path: '/feedback',
    name: 'feedback',
    meta: { userOnly: true, title: 'Phản hồi' },
    component: { render: () => null },
    beforeEnter: (to, from) => {
      useNotifyStore().supportOpen = true
      return from.name ? false : '/'
    },
  },
  { path: '/packages', name: 'packages', component: PackagesView, meta: { userOnly: true, title: 'Gói dịch vụ & Thanh toán' } },
  // Payments was merged into /packages (same purchase flow, one page instead of two).
  { path: '/payments', redirect: '/packages' },
  { path: '/account', name: 'account', component: AccountView, meta: { title: 'Tài khoản' } },

  // Admin area
  {
    path: '/admin/users',
    name: 'admin-users',
    component: AdminUsersView,
    meta: { title: 'Quản lý khách hàng', requiresAdmin: true, perm: 'users.view' },
  },
  {
    path: '/admin/stats',
    name: 'admin-stats',
    component: AdminStatsView,
    meta: { title: 'Thống kê', requiresAdmin: true, perm: 'stats.view' },
  },
  {
    path: '/admin/settings',
    name: 'admin-settings',
    component: AdminSettingsView,
    meta: { title: 'Cài đặt hệ thống', requiresAdmin: true, perm: ['settings.manage', 'security.view'] },
  },
  {
    path: '/admin/renewals',
    name: 'admin-renewals',
    component: AdminRenewalsView,
    meta: { title: 'Gia hạn gói', requiresAdmin: true, perm: 'payments.manage' },
  },
  {
    path: '/admin/payment-requests',
    name: 'admin-payment-requests',
    component: AdminPaymentRequestsView,
    meta: { title: 'Yêu cầu thanh toán', requiresAdmin: true, perm: 'payments.manage' },
  },
  {
    path: '/admin/messages',
    name: 'admin-messages',
    component: AdminMessagesView,
    meta: { title: 'Phản hồi khách hàng', requiresAdmin: true, perm: 'support.messages' },
  },
  {
    path: '/admin/messages/:userId',
    name: 'admin-messages-thread',
    component: AdminMessagesView,
    meta: { title: 'Phản hồi khách hàng', requiresAdmin: true, perm: 'support.messages' },
  },
  {
    path: '/admin/notices',
    name: 'admin-notices',
    component: AdminNoticesView,
    meta: { title: 'Thông báo & bảo trì', requiresAdmin: true, perm: 'announcements.manage' },
  },
  {
    path: '/admin/backups',
    name: 'admin-backups',
    component: AdminBackupsView,
    meta: { title: 'Sao lưu dữ liệu', requiresAdmin: true, perm: 'backups.manage' },
  },
  {
    path: '/admin/security-policy',
    name: 'admin-security-policy',
    component: () => import('../views/admin/SecurityPolicyView.vue'),
    meta: { title: 'Chính sách bảo mật', requiresAdmin: true, perm: 'security.policy' },
  },
  {
    path: '/admin/staff',
    name: 'admin-staff',
    component: () => import('../views/admin/StaffView.vue'),
    meta: { title: 'Phân quyền Admin', requiresAdmin: true, rootOnly: true },
  },
  { path: '/:pathMatch(.*)*', redirect: '/' },
]

export const router = createRouter({
  history: createWebHistory(),
  routes,
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()

  if (to.meta.public) {
    // Already logged in and heading to /login or /register - bounce to
    // the dashboard instead of showing the auth forms again.
    if (auth.isAuthenticated && (to.name === 'login' || to.name === 'register')) {
      return { path: '/' }
    }
    return true
  }

  if (!auth.isAuthenticated) {
    return { path: '/login', query: { redirect: to.fullPath } }
  }

  if (to.meta.requiresAdmin && !auth.isAdmin) {
    return { path: '/' }
  }

  // Admin pages are gated by permission (A07); the profile (with its permissions)
  // may not be loaded yet on the very first navigation.
  if (auth.isAdmin && !auth.user) await auth.fetchMe().catch(() => {})
  if (to.meta.rootOnly && !auth.isRoot) return { path: auth.adminHome() }
  if (to.meta.perm && !auth.can(to.meta.perm)) return { path: auth.adminHome() }

  if (to.meta.userOnly && auth.isAdmin) {
    return { path: auth.adminHome() }
  }

  return true
})
