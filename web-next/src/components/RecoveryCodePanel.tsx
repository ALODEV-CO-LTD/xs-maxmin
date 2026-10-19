'use client'
import { useState } from 'react'
import AppButton from './AppButton'
import RecoveryCodeDisplay from './RecoveryCodeDisplay'
import { api } from '@/lib/api'
import { useAuthStore } from '@/lib/authStore'

// Tài khoản > Mã khôi phục (K07/A06): create the code for an older account that has none, or replace it (the old code
// stops working). Needs the current password. The new code is shown once via RecoveryCodeDisplay.
// API: POST /me/recovery-code { currentPassword } -> { recoveryCode }
export default function RecoveryCodePanel() {
  const hasCode = useAuthStore((s) => !!s.user?.hasRecoveryCode)
  const fetchMe = useAuthStore((s) => s.fetchMe)
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [newCode, setNewCode] = useState('')

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    setError('')
    if (!password) return setError('Nhập mật khẩu hiện tại để tiếp tục')
    setBusy(true)
    try {
      const res = await api.post('/me/recovery-code', { currentPassword: password })
      setNewCode(res.recoveryCode)
      setPassword('')
      await fetchMe()
    } catch (err) {
      setError((err as Error).message || 'Không tạo được mã khôi phục')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="card">
      <h3 style={{ marginTop: 0 }}>Mã khôi phục</h3>
      {newCode ? (
        <RecoveryCodeDisplay code={newCode} continueText="Xong" onConfirmed={() => setNewCode('')} />
      ) : (
        <form onSubmit={submit}>
          <p className="page-subtitle">
            {hasCode ? (
              <>Bạn đã có mã khôi phục. Tạo mã mới sẽ <strong>vô hiệu mã cũ</strong>. Mã chỉ hiển thị một lần.</>
            ) : (
              <>Tài khoản chưa có mã khôi phục. Tạo mã để có thể đặt lại mật khẩu khi quên (mã chỉ hiển thị một lần).</>
            )}
          </p>
          {error && <div className="alert alert-error">{error}</div>}
          <div className="field">
            <label htmlFor="rc-password">Mật khẩu hiện tại</label>
            <div className="input-wrap">
              <input id="rc-password" value={password} onChange={(e) => setPassword(e.target.value)} type="password" autoComplete="current-password" disabled={busy} />
            </div>
          </div>
          <AppButton variant="primary" size="sm" type="submit" disabled={busy}>
            {busy ? 'Đang tạo...' : hasCode ? 'Đổi mã khôi phục' : 'Tạo mã khôi phục'}
          </AppButton>
        </form>
      )}
    </div>
  )
}
