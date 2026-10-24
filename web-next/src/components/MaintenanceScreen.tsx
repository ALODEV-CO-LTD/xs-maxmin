'use client'
import './MaintenanceScreen.css'
import { useEffect, useState } from 'react'
import { api } from '@/lib/api'
import { useAuthStore } from '@/lib/authStore'
import { applyNotices, useMaintenanceStore } from '@/lib/maintenanceStore'

// Full-screen notice for CUSTOMERS while Admin's "Chế độ bảo trì" is on (see lib/maintenanceStore.js). It re-checks the
// notice feed every 20 s and on "Thử lại"; "Đăng xuất" is handed in by the shell. Admins are never covered.
export default function MaintenanceScreen({ onLogout }: { onLogout: () => void }) {
  const message = useMaintenanceStore((s) => s.message)
  const role = useAuthStore((s) => s.role)
  const [busy, setBusy] = useState(false)
  const on = message !== null && role !== 'admin'

  async function check() {
    setBusy(true)
    try {
      const data = await api.get('/announcements')
      applyNotices(data?.maintenance)
    } catch {
      /* still down or offline: keep the notice */
    } finally {
      setBusy(false)
    }
  }

  useEffect(() => {
    if (!on) return
    const t = setInterval(() => {
      api.get('/announcements').then((d: { maintenance?: unknown }) => applyNotices(d?.maintenance)).catch(() => {})
    }, 20000)
    return () => clearInterval(t)
  }, [on])

  if (!on) return null
  return (
    <div className="maint-screen" role="alertdialog" aria-modal="true" aria-labelledby="maint-title">
      <div className="maint-box">
        <div className="maint-icon" aria-hidden="true">⚠</div>
        <h1 id="maint-title">Hệ thống đang bảo trì</h1>
        <p className="maint-msg">{message}</p>
        <button type="button" className="btn btn-primary" disabled={busy} onClick={check}>{busy ? 'Đang kiểm tra...' : 'Thử lại'}</button>
        <button type="button" className="btn btn-ghost" onClick={onLogout}>Đăng xuất</button>
      </div>
    </div>
  )
}
