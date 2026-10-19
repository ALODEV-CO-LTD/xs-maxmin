'use client'
import './PrivacyGuard.css'
import { useEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import AppButton from './AppButton'
import PasswordInput from './PasswordInput'
import { ApiError } from '@/lib/api'
import { useAuthStore } from '@/lib/authStore'
import { navigate } from '@/lib/hooks'
import { teardownSession } from '@/lib/session'
import { usePrivacyStore } from '@/lib/privacyStore'

// Auto-lock screen + hide-when-away blur (K09/K40/S02, K32/S10). Mounted once for logged-in users; all logic lives in
// lib/privacyStore.js. The screens underneath stay mounted (only covered and made inert, via #app) so half-typed input
// is not lost. A web page cannot stop screenshots (K33).
export default function PrivacyGuard() {
  const locked = usePrivacyStore((s) => s.locked)
  const away = usePrivacyStore((s) => s.away)
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const field = useRef<HTMLDivElement>(null)

  useEffect(() => {
    usePrivacyStore.getState().start()
    return () => {
      usePrivacyStore.getState().stop()
      document.documentElement.classList.remove('privacy-away')
      document.getElementById('app')?.removeAttribute('inert')
    }
  }, [])

  useEffect(() => {
    document.documentElement.classList.toggle('privacy-away', away && !locked)
    const root = document.getElementById('app')
    if (root) {
      if (locked) root.setAttribute('inert', '')
      else root.removeAttribute('inert')
    }
  }, [away, locked])

  useEffect(() => {
    if (!locked) return
    /* eslint-disable react-hooks/set-state-in-effect -- the unlock form starts empty each time the app locks */
    setPassword('')
    setError('')
    /* eslint-enable react-hooks/set-state-in-effect */
    // drop focus from any field underneath so typing can't reach it
    if (document.activeElement instanceof HTMLElement) document.activeElement.blur()
    field.current?.querySelector('input')?.focus()
  }, [locked])

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    setError('')
    if (!password) return setError('Vui lòng nhập mật khẩu')
    setBusy(true)
    try {
      await usePrivacyStore.getState().unlock(password)
      setPassword('')
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Đã xảy ra lỗi, vui lòng thử lại')
    } finally {
      setBusy(false)
    }
  }

  function logoutNow() {
    teardownSession()
    useAuthStore.getState().logout()
    navigate('/login')
  }

  if (typeof document === 'undefined') return null
  if (locked) {
    return createPortal(
      <div className="pl-overlay" role="dialog" aria-modal="true" aria-labelledby="pl-title">
        <form className="pl-box" onSubmit={submit}>
          <h2 id="pl-title" className="pl-title">Ứng dụng đã khoá</h2>
          <p className="pl-msg">
            Để bảo vệ dữ liệu, ứng dụng đã khoá. Nhập mật khẩu (hoặc mật khẩu lớp hai) để tiếp tục. Dữ liệu bạn đang nhập vẫn được giữ nguyên.
          </p>
          {error && <div className="alert alert-error" role="alert">{error}</div>}
          <div ref={field} className="field">
            <label htmlFor="pl-password">Mật khẩu</label>
            <PasswordInput id="pl-password" value={password} onChange={setPassword} autoComplete="current-password" disabled={busy} />
          </div>
          <AppButton variant="primary" block type="submit" loading={busy}>{busy ? 'Đang kiểm tra...' : 'Mở khoá'}</AppButton>
          <AppButton variant="ghost" block onClick={logoutNow}>Đăng xuất</AppButton>
        </form>
      </div>,
      document.body,
    )
  }
  if (away) return createPortal(<div className="pl-veil" aria-hidden="true" />, document.body)
  return null
}
