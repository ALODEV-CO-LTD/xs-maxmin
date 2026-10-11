// Package display names come from the admin-edited catalog (GET /me/packages?all=1,
// hidden packages included), so views never hard-code "1 tháng / 3 tháng ...".
import { reactive } from 'vue'
import { api } from './api'

const FIXED = { none: 'Chưa đăng ký', trial: 'Dùng thử 30 ngày' }
const labels = reactive({ ...FIXED })
let loading = null

export function loadPackageLabels(force = false) {
  if (!loading || force) {
    loading = api
      .get('/me/packages?all=1')
      .then((res) => {
        for (const p of res.packages || []) labels[p.type] = p.label
      })
      .catch(() => {
        loading = null
      })
  }
  return loading
}

// Reactive: re-renders once the catalog has loaded; unknown (deleted) codes show as-is.
export function packageLabel(code) {
  return labels[code] || code
}
