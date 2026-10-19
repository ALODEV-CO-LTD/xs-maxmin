// Package display names come from the admin-edited catalog (GET /me/packages?all=1, hidden packages included), so
// screens never hard-code "1 tháng / 3 tháng ...".
import { create } from 'zustand'
import { api } from './api'

const FIXED = { none: 'Chưa đăng ký', trial: 'Dùng thử 30 ngày' }
export const useLabelsStore = create(() => ({ labels: { ...FIXED } }))
let loading = null

export function loadPackageLabels(force = false) {
  if (!loading || force) {
    loading = api
      .get('/me/packages?all=1')
      .then((res) => {
        const next = { ...useLabelsStore.getState().labels }
        for (const p of res.packages || []) next[p.type] = p.label
        useLabelsStore.setState({ labels: next })
      })
      .catch(() => {
        loading = null
      })
  }
  return loading
}

// Unknown (deleted) codes show as-is. Plain function: use `usePackageLabel(code)` inside components so they re-render
// once the catalog has loaded.
export function packageLabel(code) {
  return useLabelsStore.getState().labels[code] || code
}
export function usePackageLabel(code) {
  return useLabelsStore((s) => s.labels[code]) || code
}
