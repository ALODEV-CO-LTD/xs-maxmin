'use client'
import { useEffect, useState } from 'react'
import { api } from '@/lib/api'
import ModalDialog from './ModalDialog'
import AppButton from './AppButton'
import PasswordInput from './PasswordInput'

// Asks for the account password and checks it with POST /me/verify-password ({ password } -> 200 ok, 403 wrong, 429
// locked out with a message). Calls onVerified on success and onClose on cancel/Esc. Errors stay in the dialog.
export default function PasswordPromptDialog({
  open = false,
  title = 'Nhập mật khẩu',
  description = 'Nhập mật khẩu đăng nhập để tiếp tục.',
  confirmText = 'Xác nhận',
  onVerified,
  onClose,
}: {
  open?: boolean
  title?: string
  description?: string
  confirmText?: string
  onVerified: () => void
  onClose: () => void
}) {
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    if (open) {
      /* eslint-disable react-hooks/set-state-in-effect -- the form starts empty on every open */
      setPassword('')
      setError('')
      setBusy(false)
      /* eslint-enable react-hooks/set-state-in-effect */
    }
  }, [open])

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    if (busy) return
    if (!password) return setError('Vui lòng nhập mật khẩu')
    setBusy(true)
    setError('')
    try {
      await api.post('/me/verify-password', { password })
      setPassword('')
      onVerified()
    } catch (err) {
      setError((err as Error).message || 'Không xác nhận được mật khẩu')
    } finally {
      setBusy(false)
    }
  }

  return (
    <ModalDialog
      open={open}
      title={title}
      description={description}
      onClose={onClose}
      footer={
        <>
          <AppButton variant="ghost" disabled={busy} onClick={onClose}>Huỷ</AppButton>
          <AppButton variant="primary" type="submit" form="pwd-prompt-form" loading={busy}>{busy ? 'Đang kiểm tra...' : confirmText}</AppButton>
        </>
      }
    >
      <form id="pwd-prompt-form" onSubmit={submit}>
        <div className="field" style={{ marginBottom: 0 }}>
          <label htmlFor="pwd-prompt-input">Mật khẩu đăng nhập</label>
          <PasswordInput id="pwd-prompt-input" value={password} onChange={setPassword} data-autofocus autoComplete="current-password" disabled={busy} />
        </div>
        {error && <div className="alert alert-error" role="alert" style={{ margin: '12px 0 0' }}>{error}</div>}
      </form>
    </ModalDialog>
  )
}
