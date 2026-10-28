'use client'
import { useEffect, useState } from 'react'
import AppButton from '@/components/AppButton'
import RecoveryCodePanel from '@/components/RecoveryCodePanel'
import { api } from '@/lib/api'
import { useAuthStore } from '@/lib/authStore'
import { showConfirm } from '@/lib/confirm'
import ChatDevicesCard from './ChatDevicesCard'
import { fmtSeen } from './accountLogic'
import PrivacySettings from './PrivacySettings'

/* eslint-disable @typescript-eslint/no-explicit-any */
// Tài khoản > Thiết bị & riêng tư: signed-in devices (remote sign-out), Mã khôi phục and Cài đặt quyền riêng tư.
// API: GET /me/sessions, DELETE /me/sessions/:id, DELETE /me/sessions (all but this device)
export default function DevicesTab() {
  const isAdmin = useAuthStore((s) => s.role === 'admin')
  const [sessions, setSessions] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  async function load() {
    setError('')
    try {
      const data = await api.get('/me/sessions')
      setSessions(data.sessions || [])
    } catch (err) {
      setError((err as Error).message || 'Không tải được danh sách thiết bị')
    } finally {
      setLoading(false)
    }
  }
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    load()
  }, [])

  async function revoke(s: any) {
    if (!(await showConfirm({ title: 'Đăng xuất thiết bị', message: `Đăng xuất "${s.deviceLabel}" khỏi tài khoản?`, confirmText: 'Đăng xuất' }))) return
    setError('')
    try {
      await api.del(`/me/sessions/${s.id}`)
      await load()
    } catch (err) {
      setError((err as Error).message || 'Không đăng xuất được thiết bị')
    }
  }
  async function revokeOthers() {
    if (!(await showConfirm({ title: 'Đăng xuất thiết bị khác', message: 'Đăng xuất tất cả thiết bị khác, chỉ giữ thiết bị này?', confirmText: 'Đăng xuất' }))) return
    setError('')
    try {
      await api.del('/me/sessions')
      await load()
    } catch (err) {
      setError((err as Error).message || 'Không đăng xuất được các thiết bị khác')
    }
  }

  return (
    <>
      <div className="card" style={{ marginBottom: 16 }}>
        <div className="acct-card-head">
          <h3 className="acct-h3">Thiết bị đang đăng nhập</h3>
          {sessions.length > 1 && <AppButton variant="secondary" size="sm" onClick={revokeOthers}>Đăng xuất thiết bị khác</AppButton>}
        </div>
        {error && <div className="alert alert-error">{error}</div>}
        {loading ? (
          <div>Đang tải...</div>
        ) : sessions.length === 0 ? (
          <div className="page-subtitle" style={{ marginBottom: 0 }}>
            Chưa có thông tin thiết bị (phiên đăng nhập cũ). Đăng nhập lại để theo dõi thiết bị.
          </div>
        ) : (
          <div className="acct-code-list">
            {sessions.map((s) => (
              <div key={s.id} className="acct-code-item">
                <div>
                  <strong>{s.deviceLabel}</strong>
                  {s.current && <span className="chip chip-accent" style={{ marginLeft: 8 }}>Thiết bị này</span>}
                  <div className="page-subtitle" style={{ margin: '2px 0 0' }}>
                    Hoạt động gần nhất: {fmtSeen(s.lastSeen)} · IP {s.ip || '-'}
                  </div>
                </div>
                {!s.current && (
                  <div className="acct-code-actions">
                    <AppButton variant="ghost" size="sm" onClick={() => revoke(s)}>Đăng xuất</AppButton>
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Admin accounts have no friend chat, so no chat devices. */}
      {!isAdmin && <ChatDevicesCard />}

      {/* Mã khôi phục + quyền riêng tư */}
      <div className="acct-top">
        {!isAdmin && <RecoveryCodePanel />}
        <PrivacySettings />
      </div>
    </>
  )
}
