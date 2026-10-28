'use client'
import './TrashView.css'
import { useCallback, useEffect, useState } from 'react'
import AppButton from '@/components/AppButton'
import AppIcon from '@/components/AppIcon'
import { api } from '@/lib/api'
import { showConfirm } from '@/lib/confirm'
import { errMsg, fmtDateTime } from './common'
import { countsSummary, timeLeft, trashKindIcon, trashKindLabel } from './trashLogic'

interface TrashItem {
  id: string
  kind: string
  label: string
  counts: Record<string, number>
  deletedAt?: string
  deletedByName?: string
  daysLeft: number
}

// /admin/trash (right trash.manage). What the Admin deleted stays here for 7 days: "Khôi phục" puts it back, "Xoá hẳn"
// removes it at once. The content of a customer's data is never shown, only how many rows.
// API: GET /admin/trash, POST /admin/trash/:id/restore, DELETE /admin/trash/:id
export default function TrashView() {
  const [items, setItems] = useState<TrashItem[]>([])
  const [days, setDays] = useState(7)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [busy, setBusy] = useState('')

  const apply = useCallback((res: { trashDays?: number; items?: TrashItem[] }) => {
    setDays(typeof res.trashDays === 'number' ? res.trashDays : 7)
    setItems(res.items || [])
  }, [])
  // Reload after a change (the first load is in the effect below: state is only set from promise callbacks).
  const reload = useCallback(async () => {
    try {
      apply(await api.get('/admin/trash'))
    } catch (err) {
      setError(errMsg(err, 'Không tải được thùng rác'))
    }
  }, [apply])
  useEffect(() => {
    api
      .get('/admin/trash')
      .then(apply)
      .catch((err) => setError(errMsg(err, 'Không tải được thùng rác')))
      .finally(() => setLoading(false))
  }, [apply])

  async function restore(t: TrashItem) {
    if (!(await showConfirm({ title: 'Khôi phục', message: `Khôi phục "${t.label}" (${trashKindLabel(t.kind).toLowerCase()})? Mọi dữ liệu đã xoá cùng được trả lại.`, confirmText: 'Khôi phục' }))) return
    setBusy(t.id)
    setError('')
    setMessage('')
    try {
      await api.post(`/admin/trash/${t.id}/restore`)
      setMessage(`Đã khôi phục "${t.label}".`)
      await reload()
    } catch (err) {
      setError(errMsg(err, 'Không khôi phục được'))
    } finally {
      setBusy('')
    }
  }

  async function purge(t: TrashItem) {
    if (!(await showConfirm({ title: 'Xoá hẳn', message: `Xoá hẳn "${t.label}"? Sau đó không thể khôi phục (trừ khi còn trong một bản sao lưu).`, confirmText: 'Xoá hẳn', danger: true }))) return
    setBusy(t.id)
    setError('')
    setMessage('')
    try {
      await api.del(`/admin/trash/${t.id}`)
      setMessage(`Đã xoá hẳn "${t.label}".`)
      await reload()
    } catch (err) {
      setError(errMsg(err, 'Không xoá được'))
    } finally {
      setBusy('')
    }
  }

  return (
    <div className="adm-trash">
      <div className="page">
        <h1 className="page-title">Thùng rác</h1>
        <p className="intro">Những gì Admin đã xoá được giữ {days} ngày để khôi phục khi xoá nhầm. Dữ liệu khách tự xoá không nằm ở đây: hãy khôi phục từ bản sao lưu (Cài đặt &gt; Sao lưu).</p>

        {error && <div className="alert alert-error">{error}</div>}
        {message && <div className="alert alert-success">{message}</div>}

        {loading ? (
          <div className="card empty">Đang tải...</div>
        ) : items.length === 0 ? (
          <div className="card empty">Thùng rác trống.</div>
        ) : (
          <div className="list">
            {items.map((t) => (
              <div key={t.id} className="card item" data-testid={`trash-${t.id}`}>
                <div className="item-head">
                  <AppIcon name={trashKindIcon(t.kind)} />
                  <span className="item-label">{t.label}</span>
                  <span className={`left${t.daysLeft <= 1 ? ' soon' : ''}`}>{timeLeft(t.daysLeft)}</span>
                </div>
                <div className="meta">{trashKindLabel(t.kind)} · xoá {fmtDateTime(t.deletedAt)}{t.deletedByName ? ` bởi ${t.deletedByName}` : ''}</div>
                {countsSummary(t.counts) && <div className="counts">{countsSummary(t.counts)}</div>}
                <div className="actions">
                  <AppButton variant="primary" size="sm" disabled={!!busy} onClick={() => restore(t)}>{busy === t.id ? 'Đang xử lý...' : 'Khôi phục'}</AppButton>
                  <AppButton variant="secondary" size="sm" disabled={!!busy} onClick={() => purge(t)}>Xoá hẳn</AppButton>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
