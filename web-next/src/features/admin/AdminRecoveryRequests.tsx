'use client'
import './AdminRecoveryRequests.css'
import { useCallback, useEffect, useState } from 'react'
import AppButton from '@/components/AppButton'
import { api } from '@/lib/api'
import { showConfirm } from '@/lib/confirm'
import { copyToClipboard, errMsg, fmtDateTime } from './common'
import { RECOVERY_STATUS } from './usersLogic'

interface Req {
  id: string
  name: string
  username: string
  status: string
  accountLocked?: boolean
  createdAt: string
  ip?: string
  registeredAt?: string
  ticketExpiresAt?: string
  note?: string
}
interface Issued {
  username: string
  ticket: string
  expiresAt: string
}

// Admin queue of "nhờ Admin hỗ trợ khôi phục" requests. Admin verifies the person outside the app, then approves: a
// one-time ticket (valid 24 h) is shown ONCE to pass on; the customer sets their own new password with it.
// API: GET /admin/recovery-requests, POST /admin/recovery-requests/:id {action}
export default function AdminRecoveryRequests({ onCount }: { onCount?: (n: number) => void }) {
  const [requests, setRequests] = useState<Req[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [busyId, setBusyId] = useState('')
  const [issued, setIssued] = useState<Issued | null>(null)
  const [copied, setCopied] = useState(false)

  const load = useCallback(async () => {
    setError('')
    try {
      const res = await api.get('/admin/recovery-requests')
      setRequests(res.requests)
      onCount?.(res.pending)
    } catch (err) {
      setError(errMsg(err, 'Không tải được yêu cầu khôi phục'))
    } finally {
      setLoading(false)
    }
  }, [onCount])
  useEffect(() => {
    load()
  }, [load])

  async function act(r: Req, action: 'approve' | 'reject') {
    if (action === 'reject' && !(await showConfirm({
      title: 'Từ chối yêu cầu',
      message: `Từ chối yêu cầu khôi phục của "${r.username}"? Mã hỗ trợ đã cấp (nếu có) sẽ vô hiệu.`,
      confirmText: 'Từ chối',
      danger: true,
    }))) return
    setBusyId(r.id)
    setError('')
    try {
      const res = await api.post(`/admin/recovery-requests/${r.id}`, { action })
      if (action === 'approve') {
        setIssued({ username: r.username, ticket: res.ticket, expiresAt: res.expiresAt })
        setCopied(false)
      }
      await load()
    } catch (err) {
      setError(errMsg(err, 'Không xử lý được yêu cầu'))
    } finally {
      setBusyId('')
    }
  }

  if (!(loading || requests.length || issued || error)) return null
  return (
    <div className="adm-rr">
      <section className="card rr-card" aria-label="Yêu cầu hỗ trợ khôi phục tài khoản">
        <h2 className="rr-title">Yêu cầu hỗ trợ khôi phục tài khoản</h2>
        <p className="rr-sub">
          Hãy xác minh người gửi là chủ tài khoản qua kênh riêng (số điện thoại, tin nhắn đã đăng ký...) trước khi duyệt. Khách sẽ tự đặt mật khẩu mới bằng mã hỗ trợ, Admin không biết mật khẩu.
        </p>
        {error && <div className="alert alert-error">{error}</div>}

        {issued && (
          <div className="alert alert-success rr-issued">
            <p>
              Mã hỗ trợ cho <strong>{issued.username}</strong>: <strong className="rr-code">{issued.ticket}</strong>
              <AppButton variant="ghost" size="sm" onClick={async () => setCopied(await copyToClipboard(issued.ticket))}>{copied ? 'Đã chép' : 'Chép'}</AppButton>
            </p>
            <p className="rr-hint">
              Hạn dùng đến {fmtDateTime(issued.expiresAt)}, dùng một lần. Gửi cho khách qua kênh riêng ngay bây giờ vì mã không xem lại được. Khách vào Đăng nhập, Quên mật khẩu, &quot;Tôi đã có mã hỗ trợ từ Admin&quot;.
            </p>
            <AppButton variant="secondary" size="sm" onClick={() => setIssued(null)}>Đã gửi, ẩn mã</AppButton>
          </div>
        )}

        {loading ? (
          <p>Đang tải...</p>
        ) : (
          <ul className="rr-list">
            {requests.map((r) => (
              <li key={r.id} className="rr-item">
                <div className="rr-main">
                  <div className="rr-name">
                    {r.name} <span className="rr-user">({r.username})</span>
                    <span className={`rr-status st-${r.status}`}>{RECOVERY_STATUS[r.status as keyof typeof RECOVERY_STATUS] || r.status}</span>
                    {r.accountLocked && <span className="rr-status st-expired">Tài khoản đang khoá</span>}
                  </div>
                  <div className="rr-meta">
                    Gửi lúc {fmtDateTime(r.createdAt)} · IP {r.ip || '-'} · Đăng ký {fmtDateTime(r.registeredAt)}
                    {r.status === 'approved' && <> · Mã hết hạn {fmtDateTime(r.ticketExpiresAt)}</>}
                  </div>
                  {r.note && <div className="rr-note">Ghi chú của khách: {r.note}</div>}
                </div>
                <div className="rr-actions">
                  <AppButton variant="primary" size="sm" disabled={busyId === r.id} onClick={() => act(r, 'approve')}>{r.status === 'pending' ? 'Duyệt, cấp mã' : 'Cấp lại mã'}</AppButton>
                  <button type="button" className="btn btn-ghost btn-sm rr-reject" disabled={busyId === r.id} onClick={() => act(r, 'reject')}>Từ chối</button>
                </div>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  )
}
