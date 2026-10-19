'use client'
import './SyncStatus.css'
import { useState } from 'react'
import { createPortal } from 'react-dom'
import AppButton from './AppButton'
import { betTypeLabel } from '@/lib/betTypes'
import { dismissFailure, flushQueue, resolveConflict, useSyncStore } from '@/lib/offline'

// Connection / sync indicator for the top bar (Offline, Đang đồng bộ, n chờ đồng bộ) + the dialog that asks the user
// what to do when the same record was edited elsewhere while this device was offline (see lib/offline.js).
const FIELDS = [
  { key: 'customerName', label: 'Khách hàng' },
  { key: 'entryDate', label: 'Ngày' },
  { key: 'betType', label: 'Hạng mục' },
  { key: 'value', label: 'Số' },
  { key: 'score', label: 'Điểm vào' },
  { key: 'note', label: 'Ghi chú' },
]

export function syncLabel(s: { syncing: boolean; online: boolean; pending: number }) {
  if (s.syncing) return 'Đang đồng bộ...'
  if (!s.online) return s.pending ? `Offline · ${s.pending} chờ đồng bộ` : 'Offline'
  if (s.pending) return `${s.pending} chờ đồng bộ`
  return ''
}

function show(src: Record<string, unknown> | undefined, key: string) {
  const v = src?.[key]
  if (key === 'betType') return betTypeLabel((v as string) || 'de')
  return (v as string) || '-'
}

interface Conflict { opId: string | null; entryId: string; mine: Record<string, unknown>; server: Record<string, unknown> }

export default function SyncStatus() {
  const { online, syncing, pending, conflicts, failures } = useSyncStore()
  const label = syncLabel({ syncing, online, pending })
  const kind = syncing ? 'syncing' : online ? 'pending' : 'offline'

  const conflict = ((conflicts as Conflict[])[0] as Conflict | undefined) || null
  const [resolving, setResolving] = useState(false)
  const [resolveError, setResolveError] = useState('')
  // only the fields the user actually changed
  const changed = conflict ? FIELDS.filter((f) => f.key in conflict.mine) : FIELDS
  const rows = changed.length ? changed : FIELDS

  async function choose(choice: 'mine' | 'server') {
    setResolving(true)
    setResolveError('')
    try {
      await resolveConflict(conflict, choice)
    } catch (err) {
      setResolveError((err as Error).message || 'Không xử lý được xung đột')
    } finally {
      setResolving(false)
    }
  }

  return (
    <>
      {label && (
        <button
          type="button"
          className={`sync-chip sync-${kind}`}
          disabled={!online || syncing}
          title={online ? 'Bấm để đồng bộ ngay' : 'Mất kết nối. Số liệu nhập sẽ được lưu trên máy và gửi lên khi có mạng'}
          role="status"
          onClick={() => flushQueue()}
        >
          <span className="sync-dot" aria-hidden="true" />
          {label}
        </button>
      )}
      {typeof document !== 'undefined' &&
        createPortal(
          <>
            {failures.length > 0 && (
              <div className="sync-failures" role="alert">
                {failures.map((f: { id: string; message: string }) => (
                  <div key={f.id} className="sync-failure">
                    <span>{f.message}</span>
                    <AppButton variant="ghost" size="sm" onClick={() => dismissFailure(f.id)}>Đóng</AppButton>
                  </div>
                ))}
              </div>
            )}
            {conflict && (
              <div className="sync-overlay">
                <div className="sync-box" role="dialog" aria-modal="true" aria-labelledby="sync-title">
                  <h2 id="sync-title" className="sync-title">Số liệu đã được sửa ở nơi khác</h2>
                  <p className="sync-text">Bản ghi này vừa được sửa ở thiết bị khác trong lúc bạn chỉnh sửa. Chọn bản bạn muốn giữ.</p>
                  {resolveError && <div className="alert alert-error">{resolveError}</div>}
                  <table className="table sync-table">
                    <thead>
                      <tr><th></th><th>Bản của bạn</th><th>Bản trên máy chủ</th></tr>
                    </thead>
                    <tbody>
                      {rows.map((f) => (
                        <tr key={f.key}>
                          <td>{f.label}</td>
                          <td>{show(conflict.mine, f.key)}</td>
                          <td>{show(conflict.server, f.key)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                  <div className="sync-actions">
                    <AppButton variant="secondary" disabled={resolving} onClick={() => choose('server')}>Dùng bản trên máy chủ</AppButton>
                    <AppButton variant="primary" disabled={resolving} onClick={() => choose('mine')}>Giữ bản của tôi</AppButton>
                  </div>
                </div>
              </div>
            )}
          </>,
          document.body,
        )}
    </>
  )
}
