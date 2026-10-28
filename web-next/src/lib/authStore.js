// Auth store - single source of truth for the logged-in session (port of frontend/src/stores/auth.js to zustand).
//   - `token` + `role` are persisted to localStorage ('xoso_token' / 'xoso_role') and restored by init(), called once
//     on the client before any screen renders. Read them only through this store.
//   - login(token, role) stores the session; clear() wipes it (logout AND a 401 from api.js).
import { create } from 'zustand'
import { api } from './api'

const TOKEN_KEY = 'xoso_token'
const ROLE_KEY = 'xoso_role'

// First admin page this account may open (admin pages are listed in nav order).
const ADMIN_PAGES = [
  ['stats.view', '/admin/stats'],
  ['users.view', '/admin/users'],
  ['support.messages', '/admin/messages'],
  ['payments.manage', '/admin/payment-requests'],
  [['announcements.manage', 'maintenance.manage'], '/admin/notices'],
  [['settings.manage', 'security.view', 'security.policy', 'backups.manage'], '/admin/settings'],
  ['trash.manage', '/admin/trash'],
]

export const useAuthStore = create((set, get) => ({
  token: null,
  role: null,
  user: null, // the object of GET /api/me, null until loaded
  ready: false,
  signedOutByUser: false, // true only for the instant after an explicit logout

  // derived (functions, because zustand has no getters)
  isAuthenticated: () => !!get().token,
  isAdmin: () => get().role === 'admin',
  permissions: () => get().user?.permissions || [],
  isRoot: () => !!get().user?.isRoot,
  // True when this admin account holds `perm` (the root Admin holds all). `perm` may be a list: any of them.
  can(perm) {
    const s = get()
    if (s.role !== 'admin') return false
    const list = Array.isArray(perm) ? perm : [perm]
    return !!s.user?.isRoot || list.some((p) => (s.user?.permissions || []).includes(p))
  },
  adminHome() {
    return ADMIN_PAGES.find(([perm]) => get().can(perm))?.[1] || '/account'
  },

  init() {
    let token = null
    let role = null
    try {
      token = localStorage.getItem(TOKEN_KEY)
      role = localStorage.getItem(ROLE_KEY)
    } catch {
      /* no localStorage */
    }
    set({ token, role, ready: true })
  },
  login(token, role) {
    set({ token, role })
    try {
      localStorage.setItem(TOKEN_KEY, token)
      localStorage.setItem(ROLE_KEY, role)
    } catch {
      /* the session still works for this tab */
    }
  },
  clear() {
    set({ token: null, role: null, user: null })
    try {
      localStorage.removeItem(TOKEN_KEY)
      localStorage.removeItem(ROLE_KEY)
    } catch {
      /* ignore */
    }
  },
  logout() {
    set({ signedOutByUser: true })
    // Also revoke this device's session on the server (best effort; the token is read before clear()).
    if (get().token) api.del('/me/sessions/current').catch(() => {})
    get().clear()
  },
  async fetchMe() {
    if (!get().token) return null
    const me = await api.get('/me')
    set({ user: me })
    return me
  },
}))
