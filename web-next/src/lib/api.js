// Thin fetch wrapper around the XOSO backend REST API.
//
// Conventions (shared across the whole app - user area + admin area):
//   - Base path is always '/api/...' (Next dev rewrites it to
//     http://localhost:8080; in production this SPA is meant to be served
//     from the same origin as the API, so no base URL config is needed).
//   - Every call goes through apiFetch(path, options). It automatically:
//       * attaches `Authorization: Bearer <token>` when the auth store has
//         a token,
//       * JSON-encodes `options.body` if it's a plain object,
//       * parses the JSON response,
//       * throws an `ApiError` (with `.status` and `.message`) built from
//         the backend's `{ error: "..." }` shape on any non-2xx response.
//   - Call sites should `await` and catch `ApiError` to show `err.message`
//     (already a user-facing Vietnamese string from the backend) directly
//     in the UI - no need to re-map error messages.
//   - `api.get/post/patch/del(path, body)` are convenience shortcuts.
import { useAuthStore } from './authStore'
import { useMaintenanceStore } from './maintenanceStore'

export class ApiError extends Error {
  constructor(status, message, data = null) {
    super(message)
    this.status = status
    // Parsed JSON body of the error response (e.g. the 409 conflict payload).
    this.data = data
  }
}

// Endpoints that ask the logged-in user to re-type a password. A 401 from
// these means "wrong password" (older servers) - show the message at the form
// instead of treating the session as expired. Newer servers answer 403.
const REAUTH_PATHS = [
  '/me/password',
  '/me/second-password',
  '/me/wipe-password',
  '/me/delete-data',
  '/me/recovery-code',
  '/me/verify-password',
]
function isReauthRequest(path, method) {
  const p = path.split('?')[0]
  if (p.startsWith('/auth/')) return true
  if (p === '/me' && method !== 'GET') return true // username change asks for the password
  return REAUTH_PATHS.includes(p)
}

async function apiFetch(path, { method = 'GET', body, headers = {} } = {}) {
  const auth = useAuthStore.getState()
  const finalHeaders = { ...headers }
  let finalBody = body
  if (body !== undefined && typeof body !== 'string') {
    finalHeaders['content-type'] = 'application/json'
    finalBody = JSON.stringify(body)
  }
  if (auth.token) {
    finalHeaders['authorization'] = `Bearer ${auth.token}`
  }

  let res
  try {
    res = await fetch(`/api${path}`, { method, headers: finalHeaders, body: finalBody })
  } catch {
    throw new ApiError(0, 'Không thể kết nối tới máy chủ')
  }

  let data = null
  const text = await res.text()
  if (text) {
    try {
      data = JSON.parse(text)
    } catch {
      data = null
    }
  }

  if (!res.ok) {
    if (res.status === 401 && !isReauthRequest(path, method)) {
      // Session invalid/expired - clear it so the router guard redirects
      // to /login instead of retry-looping against a dead token.
      // (Not for "type your current password again" requests: there a 401
      // only means the password was wrong, and must not log the user out.)
      auth.clear()
    }
    const message = data && typeof data.error === 'string' ? data.error : statusFallback(res.status)
    if (res.status === 503 && data && data.maintenance === true) useMaintenanceStore.getState().setMessage(message)
    throw new ApiError(res.status, message, data)
  }

  return data
}

// Vietnamese text for responses without our JSON body (e.g. nginx answering
// 413/429 before the backend sees the request).
export function statusFallback(status) {
  if (status === 413) return 'Dữ liệu gửi lên quá lớn'
  if (status === 429) return 'Bạn thao tác quá nhanh, vui lòng thử lại sau ít phút'
  return `Lỗi máy chủ (${status})`
}

// Authenticated download of a binary response (chat attachments): <img>/<a>
// can't send the Authorization header, so callers fetch a Blob here and use
// an object URL.
async function apiBlob(path) {
  const auth = useAuthStore.getState()
  const headers = {}
  if (auth.token) headers['authorization'] = `Bearer ${auth.token}`
  let res
  try {
    res = await fetch(`/api${path}`, { headers })
  } catch {
    throw new ApiError(0, 'Không thể kết nối tới máy chủ')
  }
  if (!res.ok) {
    if (res.status === 401) auth.clear()
    let message = statusFallback(res.status)
    try {
      const data = await res.json()
      if (data && typeof data.error === 'string') message = data.error
    } catch {
      /* not JSON */
    }
    throw new ApiError(res.status, message)
  }
  return res.blob()
}

export const api = {
  blob: apiBlob,
  get: (path) => apiFetch(path, { method: 'GET' }),
  post: (path, body) => apiFetch(path, { method: 'POST', body: body ?? {} }),
  patch: (path, body) => apiFetch(path, { method: 'PATCH', body: body ?? {} }),
  put: (path, body) => apiFetch(path, { method: 'PUT', body: body ?? {} }),
  del: (path, body) => apiFetch(path, { method: 'DELETE', body }),
}
