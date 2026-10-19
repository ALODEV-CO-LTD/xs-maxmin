'use client'
import './AnnouncementBanner.css'
import { useEffect, useState } from 'react'
import { api } from '@/lib/api'

// Banner for admin notices (A12/A16): maintenance mode (not dismissable while it is on) and announcements
// (maintenance / policy change / info) that the user can close for the current session. GET /announcements, refreshed
// every 5 minutes; silently ignored while offline.
const KIND_LABEL: Record<string, string> = { maintenance: 'Bảo trì', policy: 'Chính sách', info: 'Thông báo' }
const DISMISSED_KEY = 'xoso_dismissed_notices'

interface Announcement { id: string; kind: string; title: string; body?: string }

function readDismissed(): Set<string> {
  try {
    return new Set(JSON.parse(sessionStorage.getItem(DISMISSED_KEY) || '[]'))
  } catch {
    return new Set()
  }
}

export default function AnnouncementBanner() {
  const [maintenance, setMaintenance] = useState({ enabled: false, message: '' })
  const [announcements, setAnnouncements] = useState<Announcement[]>([])
  const [dismissed, setDismissed] = useState<Set<string>>(() => new Set())

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- sessionStorage exists only on the client
    setDismissed(readDismissed())
    let alive = true
    const load = async () => {
      try {
        const data = await api.get('/announcements')
        if (!alive) return
        setMaintenance(data.maintenance || { enabled: false, message: '' })
        setAnnouncements(data.announcements || [])
      } catch {
        /* offline or not allowed - keep what we have */
      }
    }
    load()
    const timer = setInterval(load, 5 * 60 * 1000)
    return () => {
      alive = false
      clearInterval(timer)
    }
  }, [])

  const visible = announcements.filter((a) => !dismissed.has(a.id))

  function dismiss(id: string) {
    const next = new Set([...dismissed, id])
    setDismissed(next)
    try {
      sessionStorage.setItem(DISMISSED_KEY, JSON.stringify([...next]))
    } catch {
      /* ignore */
    }
  }

  if (!maintenance.enabled && !visible.length) return null
  return (
    <div className="notices">
      {maintenance.enabled && (
        <div className="alert alert-warning notice" role="status">
          <div className="notice-text">
            <strong>Hệ thống đang bảo trì.</strong> {maintenance.message || 'Một số chức năng có thể tạm thời không hoạt động.'}
          </div>
        </div>
      )}
      {visible.map((a) => (
        <div key={a.id} className={`alert notice ${a.kind === 'maintenance' ? 'alert-warning' : 'alert-success'}`} role="status">
          <div className="notice-text">
            <strong>{KIND_LABEL[a.kind] || 'Thông báo'}: {a.title}</strong>
            {a.body && <div className="notice-body">{a.body}</div>}
          </div>
          <button type="button" className="notice-close" aria-label="Ẩn thông báo" onClick={() => dismiss(a.id)}>×</button>
        </div>
      ))}
    </div>
  )
}
