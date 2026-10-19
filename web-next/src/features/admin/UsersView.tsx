'use client'
import './UsersView.css'
import { useCallback, useEffect, useRef, useState } from 'react'
import AppButton from '@/components/AppButton'
import AppIcon from '@/components/AppIcon'
import { api } from '@/lib/api'
import { showConfirm } from '@/lib/confirm'
import { useAuthStore } from '@/lib/authStore'
import AdminRecoveryRequests from './AdminRecoveryRequests'
import { copyToClipboard, errMsg, fmtDate, fmtDateTime } from './common'
import { generatePassword, listPath, lockConfirm, mergeRow, statusLabel, supportBody, supportNoteOf } from './usersLogic'

interface User {
  id: string
  name: string
  username: string
  status: string
  accountLocked?: boolean
  package: { label: string; expiresAt?: string | null }
}
interface Session {
  id: string
  deviceLabel: string
  ip?: string
  lastSeen?: string
}

// /admin/users - searchable subscriber table + detail panel.
// API: GET /admin/users?q=, GET/PATCH/DELETE /admin/users/:id, GET/DELETE /admin/users/:id/sessions[/:sid]
export default function UsersView() {
  const can = useAuthStore((s) => s.can)
  const canLock = can('users.lock')
  const canRecovery = can('users.recovery')
  const canDelete = can('users.delete')

  const [q, setQ] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [total, setTotal] = useState(0)
  const [subscribers, setSubscribers] = useState<User[]>([])

  const [open, setOpen] = useState(false)
  const [selected, setSelected] = useState<User | null>(null)
  const [detailLoading, setDetailLoading] = useState(false)
  const [detailError, setDetailError] = useState('')
  const [actionBusy, setActionBusy] = useState(false)
  const [actionError, setActionError] = useState('')
  const [showReset, setShowReset] = useState(false)
  const [newPassword, setNewPassword] = useState('')
  const [lastSetPassword, setLastSetPassword] = useState('')
  const [lastRecoveryCode, setLastRecoveryCode] = useState('')
  const [supportNote, setSupportNote] = useState('')
  const [copied, setCopied] = useState('')
  const [userSessions, setUserSessions] = useState<Session[]>([])
  const [sessionsError, setSessionsError] = useState('')
  const copyTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  const loadList = useCallback(async (query: string) => {
    setLoading(true)
    setError('')
    try {
      const res = await api.get(listPath(query))
      setTotal(res.total)
      setSubscribers(res.subscribers)
    } catch (err) {
      setError(errMsg(err, 'Không thể tải danh sách'))
    } finally {
      setLoading(false)
    }
  }, [])
  // first load at once, later keystrokes debounced 300 ms
  const first = useRef(true)
  useEffect(() => {
    const t = setTimeout(() => loadList(q), first.current ? 0 : 300)
    first.current = false
    return () => clearTimeout(t)
  }, [q, loadList])
  useEffect(() => () => void (copyTimer.current && clearTimeout(copyTimer.current)), [])

  async function copyText(text: string, key: string) {
    if (!(await copyToClipboard(text))) return
    setCopied(key)
    if (copyTimer.current) clearTimeout(copyTimer.current)
    copyTimer.current = setTimeout(() => setCopied(''), 2000)
  }

  async function loadUserSessions(id: string) {
    setSessionsError('')
    if (!canLock) return
    try {
      setUserSessions((await api.get(`/admin/users/${id}/sessions`)).sessions || [])
    } catch (err) {
      setUserSessions([])
      setSessionsError(errMsg(err, 'Không thể tải danh sách thiết bị'))
    }
  }
  async function revokeUserSession(sid: string | null) {
    if (!selected) return
    setSessionsError('')
    try {
      if (sid) await api.del(`/admin/users/${selected.id}/sessions/${sid}`)
      else await api.del(`/admin/users/${selected.id}/sessions`)
      await loadUserSessions(selected.id)
    } catch (err) {
      setSessionsError(errMsg(err, 'Không thể thu hồi phiên'))
    }
  }

  async function openUser(id: string) {
    setOpen(true)
    setSelected(null)
    setUserSessions([])
    setDetailLoading(true)
    setDetailError('')
    setActionError('')
    try {
      setSelected(await api.get(`/admin/users/${id}`))
      loadUserSessions(id)
    } catch (err) {
      setDetailError(errMsg(err, 'Không thể tải chi tiết'))
    } finally {
      setDetailLoading(false)
    }
  }
  function closeDetail() {
    setOpen(false)
    setSelected(null)
    setDetailError('')
    setActionError('')
    setShowReset(false)
    setNewPassword('')
    setLastSetPassword('')
    setLastRecoveryCode('')
    setSupportNote('')
  }

  async function supportAction(kind: 'code' | 'unlock') {
    if (!selected) return
    setActionBusy(true)
    setActionError('')
    setSupportNote('')
    try {
      const updated = await api.patch(`/admin/users/${selected.id}`, supportBody(kind))
      if (updated.recoveryCode) setLastRecoveryCode(updated.recoveryCode)
      setSupportNote(supportNoteOf(kind))
      setSelected({ ...selected, ...updated })
    } catch (err) {
      setActionError(errMsg(err, 'Không thể thực hiện'))
    } finally {
      setActionBusy(false)
    }
  }

  async function resetPassword() {
    if (!selected || !newPassword.trim()) return
    setActionBusy(true)
    setActionError('')
    try {
      const pw = newPassword.trim()
      const updated = await api.patch(`/admin/users/${selected.id}`, { newPassword: pw })
      setLastSetPassword(pw)
      setLastRecoveryCode(updated.recoveryCode || '')
      setSupportNote('')
      setNewPassword('')
      setShowReset(false)
      setSelected({ ...selected, ...updated })
    } catch (err) {
      setActionError(errMsg(err, 'Không thể đặt lại mật khẩu'))
    } finally {
      setActionBusy(false)
    }
  }

  async function toggleLock() {
    if (!selected) return
    if (!(await showConfirm(lockConfirm(selected)))) return
    setActionBusy(true)
    setActionError('')
    try {
      const updated = await api.patch(`/admin/users/${selected.id}`, { locked: !selected.accountLocked })
      setSelected(updated)
      setSubscribers((l) => mergeRow(l, updated))
    } catch (err) {
      setActionError(errMsg(err, 'Không thể cập nhật'))
    } finally {
      setActionBusy(false)
    }
  }

  async function deleteUser() {
    if (!selected) return
    if (!(await showConfirm({ title: 'Xoá tài khoản', message: 'Xoá vĩnh viễn tài khoản này và toàn bộ dữ liệu liên quan?', confirmText: 'Xoá', danger: true }))) return
    setActionBusy(true)
    setActionError('')
    try {
      await api.del(`/admin/users/${selected.id}`)
      const rest = subscribers.filter((s) => s.id !== selected.id)
      setSubscribers(rest)
      setTotal(rest.length)
      closeDetail()
    } catch (err) {
      setActionError(errMsg(err, 'Không thể xoá tài khoản'))
    } finally {
      setActionBusy(false)
    }
  }

  return (
    <div className="adm-users">
      <div className="page">
        <h1 className="page-title">Quản lý khách hàng</h1>
        <p className="page-subtitle">Tổng cộng {total} khách hàng</p>

        {canRecovery && <AdminRecoveryRequests />}

        <div className="field search-field">
          <div className="input-wrap">
            <AppIcon name="search" className="search-icon" />
            <input value={q} onChange={(e) => setQ(e.target.value)} type="text" placeholder="Tìm theo tên..." aria-label="Tìm theo tên" />
          </div>
        </div>

        {error && <div className="alert alert-error">{error}</div>}

        <div className="card table-card">
          <table className="table users-table stack-table">
            <thead>
              <tr>
                <th>Khách hàng</th>
                <th>Tài khoản</th>
                <th>Gói</th>
                <th>Hết hạn</th>
                <th>Trạng thái</th>
                <th className="col-action">Chi tiết</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr><td colSpan={6}>Đang tải...</td></tr>
              ) : subscribers.length === 0 ? (
                <tr><td colSpan={6}>Không có khách hàng nào</td></tr>
              ) : (
                subscribers.map((s) => (
                  <tr key={s.id} className="row-click" onClick={() => openUser(s.id)}>
                    <td data-label="Khách hàng">{s.name}</td>
                    <td data-label="Tài khoản">{s.username}</td>
                    <td data-label="Gói">{s.package.label}</td>
                    <td data-label="Hết hạn">{fmtDate(s.package.expiresAt)}</td>
                    <td data-label="Trạng thái">
                      <div className="status-cell">
                        <span className={`chip ${s.status === 'active' ? 'chip-accent' : 'chip-warning'}`}>{statusLabel(s.status)}</span>
                        {s.accountLocked && <span className="chip chip-danger">Đã khoá</span>}
                      </div>
                    </td>
                    <td className="col-action" data-label="Chi tiết">
                      <button type="button" className="btn btn-secondary btn-sm detail-btn" onClick={(e) => { e.stopPropagation(); openUser(s.id) }}>Xem chi tiết</button>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>

        {open && (
          <div className="overlay" onMouseDown={(e) => e.target === e.currentTarget && closeDetail()}>
            <div className="card detail-panel" role="dialog" aria-modal="true" aria-labelledby="detail-title">
              {detailLoading ? (
                <div>Đang tải chi tiết...</div>
              ) : detailError ? (
                <>
                  <div className="alert alert-error">{detailError}</div>
                  <AppButton variant="ghost" onClick={closeDetail}>Đóng</AppButton>
                </>
              ) : (
                selected && (
                  <div>
                    <div className="modal-head">
                      <div className="modal-title-wrap">
                        <h2 id="detail-title" className="modal-title">{selected.name}</h2>
                        <p className="modal-username">@{selected.username}</p>
                      </div>
                      <button className="modal-close" aria-label="Đóng" title="Đóng" onClick={closeDetail}>
                        <AppIcon name="x" />
                      </button>
                    </div>

                    <div className="modal-chips">
                      <span className={`chip ${selected.status === 'active' ? 'chip-accent' : 'chip-warning'}`}>{selected.status === 'active' ? 'Gói hoạt động' : 'Gói hết hạn'}</span>
                      <span className={`chip ${selected.accountLocked ? 'chip-danger' : 'chip-accent'}`}>{selected.accountLocked ? 'Tài khoản đã khoá' : 'Tài khoản đang mở'}</span>
                    </div>

                    <div className="info-card">
                      <p className="info-row"><strong>Gói:</strong> <span>{selected.package.label}</span></p>
                      <p className="info-row"><strong>Hết hạn:</strong> <span>{fmtDateTime(selected.package.expiresAt)}</span></p>
                    </div>

                    {canLock && (
                      <div className="info-card">
                        <p className="info-row">
                          <strong>Thiết bị đang đăng nhập ({userSessions.length})</strong>
                          {userSessions.length > 0 && <AppButton variant="secondary" size="sm" onClick={() => revokeUserSession(null)}>Thu hồi tất cả</AppButton>}
                        </p>
                        {sessionsError && <div className="alert alert-error">{sessionsError}</div>}
                        {userSessions.map((s) => (
                          <p key={s.id} className="info-row">
                            <span>
                              {s.deviceLabel} · IP {s.ip || '-'}<br />
                              <small>Gần nhất: {fmtDateTime(s.lastSeen)}</small>
                            </span>
                            <AppButton variant="secondary" size="sm" onClick={() => revokeUserSession(s.id)}>Thu hồi</AppButton>
                          </p>
                        ))}
                      </div>
                    )}

                    {actionError && <div className="alert alert-error">{actionError}</div>}
                    {supportNote && <div className="alert alert-success">{supportNote}</div>}
                    {(lastSetPassword || lastRecoveryCode) && (
                      <div className="alert alert-success recovery-result">
                        {lastSetPassword && (
                          <p>
                            Mật khẩu mới: <strong>{lastSetPassword}</strong>
                            <AppButton variant="ghost" size="sm" onClick={() => copyText(lastSetPassword, 'pw')}>{copied === 'pw' ? 'Đã chép' : 'Chép'}</AppButton>
                          </p>
                        )}
                        {lastRecoveryCode && (
                          <p>
                            Mã khôi phục mới: <strong>{lastRecoveryCode}</strong>
                            <AppButton variant="ghost" size="sm" onClick={() => copyText(lastRecoveryCode, 'rc')}>{copied === 'rc' ? 'Đã chép' : 'Chép'}</AppButton>
                          </p>
                        )}
                        <p className="recovery-hint">
                          Gửi cho khách hàng qua kênh riêng ngay bây giờ: hai giá trị này không xem lại được. Mọi thiết bị của khách đã bị đăng xuất, các khoá đăng nhập đã được gỡ và mã khôi phục cũ không còn dùng được.
                        </p>
                      </div>
                    )}

                    {/* The original password is hashed one-way, so this is the only way for Admin to set a new one. */}
                    {showReset && (
                      <div className="reset-box">
                        <label className="reset-label" htmlFor="new-password">Mật khẩu mới cho tài khoản này</label>
                        <div className="reset-row">
                          <input id="new-password" value={newPassword} onChange={(e) => setNewPassword(e.target.value)} type="text" placeholder="Mật khẩu mới" autoComplete="off" />
                          <AppButton variant="secondary" size="sm" disabled={actionBusy} onClick={() => setNewPassword(generatePassword())}>Tạo ngẫu nhiên</AppButton>
                          <AppButton variant="primary" size="sm" disabled={actionBusy || !newPassword.trim()} onClick={resetPassword}>Lưu</AppButton>
                          <AppButton variant="ghost" size="sm" disabled={actionBusy} onClick={() => { setShowReset(false); setNewPassword('') }}>Huỷ</AppButton>
                        </div>
                      </div>
                    )}

                    <div className="modal-actions">
                      <div className="actions-main">
                        {canLock && <AppButton variant="secondary" disabled={actionBusy} onClick={toggleLock}>{selected.accountLocked ? 'Mở khoá tài khoản' : 'Khoá tài khoản'}</AppButton>}
                        {!showReset && canRecovery && <AppButton variant="secondary" disabled={actionBusy} onClick={() => { setShowReset(true); setLastSetPassword('') }}>Đặt lại mật khẩu</AppButton>}
                        {canRecovery && <AppButton variant="secondary" disabled={actionBusy} onClick={() => supportAction('code')}>Cấp lại mã khôi phục</AppButton>}
                        {canRecovery && <AppButton variant="secondary" disabled={actionBusy} onClick={() => supportAction('unlock')}>Gỡ khoá đăng nhập</AppButton>}
                      </div>
                      {canDelete && (
                        <div className="actions-danger">
                          <AppButton variant="danger" disabled={actionBusy} onClick={deleteUser}>Xoá tài khoản</AppButton>
                        </div>
                      )}
                    </div>
                  </div>
                )
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
