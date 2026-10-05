// Auth store - single source of truth for the logged-in session.
//
// Conventions (shared across the whole app):
//   - State: `token` (JWT string or null), `role` ('admin' | 'user' | null),
//     `user` (the object returned by GET /api/me, or null until loaded).
//   - `token` + `role` are persisted to localStorage under keys
//     'xoso_token' / 'xoso_role' and restored in `init()`, which is called
//     once from src/main.js before the router/app mount. Do NOT read
//     localStorage directly anywhere else - go through this store.
//   - `isAuthenticated` / `isAdmin` getters are what router guards use.
//   - `login(token, role)` stores the session; `clear()` wipes it (used by
//     logout AND by api.js on a 401 response).
//   - `fetchMe()` loads/refreshes `user` from GET /api/me - call it after
//     login and whenever a view needs fresh profile/quota numbers.
import { defineStore } from 'pinia'
import { api } from '../api'

const TOKEN_KEY = 'xoso_token'
const ROLE_KEY = 'xoso_role'

export const useAuthStore = defineStore('auth', {
  state: () => ({
    token: null,
    role: null,
    user: null,
    ready: false,
  }),
  getters: {
    isAuthenticated: (state) => !!state.token,
    isAdmin: (state) => state.role === 'admin',
  },
  actions: {
    init() {
      try {
        this.token = localStorage.getItem(TOKEN_KEY)
        this.role = localStorage.getItem(ROLE_KEY)
      } catch {
        this.token = null
        this.role = null
      }
      this.ready = true
    },
    login(token, role) {
      this.token = token
      this.role = role
      try {
        localStorage.setItem(TOKEN_KEY, token)
        localStorage.setItem(ROLE_KEY, role)
      } catch {
        /* localStorage unavailable - session still works for this tab */
      }
    },
    clear() {
      this.token = null
      this.role = null
      this.user = null
      try {
        localStorage.removeItem(TOKEN_KEY)
        localStorage.removeItem(ROLE_KEY)
      } catch {
        /* ignore */
      }
    },
    logout() {
      // Also revoke this device's session on the server (best effort - the
      // token is read synchronously inside the call, before clear() below).
      if (this.token) api.del('/me/sessions/current').catch(() => {})
      this.clear()
    },
    async fetchMe() {
      if (!this.token) return null
      const me = await api.get('/me')
      this.user = me
      return me
    },
  },
})
