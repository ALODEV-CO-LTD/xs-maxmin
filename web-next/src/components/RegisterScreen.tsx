'use client'
import './AuthForms.css'
import { useState } from 'react'
import AppButton from './AppButton'
import AppIcon from './AppIcon'
import AuthLayout from './AuthLayout'
import PasswordInput from './PasswordInput'
import RecoveryCodeDisplay from './RecoveryCodeDisplay'
import { useAuthStore } from '@/lib/authStore'
import {
  REGISTER_ACCOUNT_FIELDS, REGISTER_FIELD_IDS, REGISTER_SECURITY_FIELDS, UNKNOWN_RESPONSE, errMsg,
  loginStep2, registerAccount, registerFieldErrors, registerStep2Result,
} from '@/lib/authFlow'

// /register - POST /api/auth/register always requires setting a second password, plus an optional wipe password. The
// backend always answers 'second_password_required' (registration never skips step2), so this screen re-prompts for the
// just-set second password and calls POST /api/auth/step2 exactly like the login does. The route guard sends the new
// session home.
type Stage = 'account' | 'security' | 'recovery_code' | 'second_password'
type Field = keyof ReturnType<typeof registerFieldErrors>

type Extra = Omit<React.InputHTMLAttributes<HTMLInputElement>, 'value' | 'onChange' | 'type'>

const TITLES: Record<Stage, string> = { account: 'Tạo tài khoản', security: 'Bảo vệ tài khoản', recovery_code: 'Lưu mã khôi phục', second_password: 'Xác minh lần cuối' }

export default function RegisterScreen() {
  const [stage, setStage] = useState<Stage>('account')
  const [recoveryCode, setRecoveryCode] = useState('') // shown once, then dropped
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('') // server / network errors only; field errors are inline

  const [name, setName] = useState('')
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('') // client-side only, never sent to the API
  const [secondPassword, setSecondPassword] = useState('')
  const [wipePassword, setWipePassword] = useState('')
  const [wipeOpen, setWipeOpen] = useState(false)

  const [pendingToken, setPendingToken] = useState('')
  const [step2Password, setStep2Password] = useState('')

  // A field shows its state once it has been blurred or the form has been submitted.
  const [touched, setTouched] = useState<Record<string, boolean>>({})
  const [submitted, setSubmitted] = useState(false)
  const touch = (f: Field) => setTouched((t) => ({ ...t, [f]: true }))

  const fieldErrors = registerFieldErrors({ name, username, password, confirmPassword, secondPassword, wipePassword, wipeOpen })
  // Show only actionable errors. Successful fields do not add extra text to the form.
  const shown = (f: Field) => (submitted || touched[f]) && !!fieldErrors[f]
  const firstInvalid = (fields: string[]) => (fields as Field[]).find((f) => fieldErrors[f])
  const focusField = (f?: string) => f && setTimeout(() => document.getElementById(REGISTER_FIELD_IDS[f as Field])?.focus(), 0)

  function goToSecurity(e: React.FormEvent) {
    e.preventDefault()
    setSubmitted(true)
    const bad = firstInvalid(REGISTER_ACCOUNT_FIELDS)
    if (bad) return focusField(bad)
    setError('')
    setSubmitted(false)
    setStage('security')
  }
  function goToAccount() {
    setError('')
    setSubmitted(false)
    setStage('account')
  }
  function toggleWipe() {
    if (wipeOpen) setWipePassword('')
    setWipeOpen(!wipeOpen)
  }

  async function submitForm(e: React.FormEvent) {
    e.preventDefault()
    setError('')
    setSubmitted(true)
    const badAccount = firstInvalid(REGISTER_ACCOUNT_FIELDS)
    if (badAccount) {
      setStage('account')
      return focusField(badAccount)
    }
    const badSecurity = firstInvalid(REGISTER_SECURITY_FIELDS)
    if (badSecurity) return focusField(badSecurity)
    setLoading(true)
    try {
      const res = await registerAccount({ name, username, password, secondPassword, wipePassword })
      if (res.stage === 'second_password_required') {
        setPendingToken(res.pendingToken)
        setStep2Password('')
        // Mã khôi phục is shown once; the user must confirm they saved it first.
        setRecoveryCode(res.recoveryCode || '')
        setStage(res.recoveryCode ? 'recovery_code' : 'second_password')
      } else setError(UNKNOWN_RESPONSE)
    } catch (err) {
      setError(errMsg(err))
    } finally {
      setLoading(false)
    }
  }

  async function submitStep2(e: React.FormEvent) {
    e.preventDefault()
    setError('')
    if (!step2Password) return setError('Vui lòng nhập mật khẩu lớp hai vừa đặt')
    setLoading(true)
    try {
      const r = registerStep2Result(await loginStep2(pendingToken, step2Password))
      if (r.token) useAuthStore.getState().login(r.token, r.role)
      else setError(r.error as string)
    } catch (err) {
      setError(errMsg(err))
    } finally {
      setLoading(false)
    }
  }

  const errBox = () => (error ? <div className="alert alert-error" role="alert">{error}</div> : null)
  const msg = (id: string, f: Field, hint?: string) => (
    <p id={`msg-${id}`} className={`field-msg${shown(f) ? ' error' : ''}`} aria-live="polite">
      {shown(f) ? (
        <>
          <AppIcon name="circle-alert" />
          {fieldErrors[f]}
        </>
      ) : (
        hint
      )}
    </p>
  )
  const text = (f: Field, id: string, label: string, value: string, set: (v: string) => void, extra: Extra) => (
    <div className="field">
      <label htmlFor={id}>{label}</label>
      <div className="input-wrap">
        <input id={id} value={value} onChange={(e) => set(e.target.value)} type="text" disabled={loading} aria-invalid={shown(f)} aria-describedby={`msg-${id}`} onBlur={() => touch(f)} {...extra} />
      </div>
      {msg(id, f)}
    </div>
  )
  const pw = (f: Field, id: string, label: React.ReactNode, value: string, set: (v: string) => void, extra: Extra, hint?: string) => (
    <div className="field">
      <label htmlFor={id}>{label}</label>
      <PasswordInput id={id} value={value} onChange={set} disabled={loading} aria-invalid={shown(f)} aria-describedby={`msg-${id}`} onBlur={() => touch(f)} {...extra} />
      {msg(id, f, hint)}
    </div>
  )

  return (
    <AuthLayout mode="register" showTabs={stage === 'account' || stage === 'security'} title={TITLES[stage]} subtitle="Dùng thử miễn phí 30 ngày">
      {stage === 'account' && (
        <form noValidate onSubmit={goToSecurity}>
          <div className="step-progress" aria-label="Bước 1 trong 2">Bước 1/2 · Thông tin tài khoản</div>
          {errBox()}
          {text('name', 'name', 'Tên hiển thị', name, setName, { autoComplete: 'name', placeholder: 'Nguyễn Văn A' })}
          {text('username', 'reg-username', 'Tên đăng nhập', username, setUsername, { autoComplete: 'username', placeholder: 'Ít nhất 3 ký tự' })}
          {pw('password', 'reg-password', 'Mật khẩu', password, setPassword, { autoComplete: 'new-password', placeholder: 'Tuỳ bạn đặt' })}
          {pw('confirmPassword', 'reg-confirm-password', 'Xác nhận mật khẩu', confirmPassword, setConfirmPassword, { autoComplete: 'new-password', placeholder: 'Nhập lại mật khẩu' })}
          <AppButton variant="primary" block type="submit">Tiếp tục</AppButton>
        </form>
      )}

      {stage === 'security' && (
        <form noValidate onSubmit={submitForm}>
          <div className="step-progress" aria-label="Bước 2 trong 2">Bước 2/2 · Bảo mật</div>
          {errBox()}
          <p className="security-intro">Mật khẩu lớp hai được hỏi thêm mỗi lần đăng nhập. Bạn đặt gì tuỳ ý.</p>
          {pw('secondPassword', 'reg-second-password', <>Mật khẩu lớp hai <span className="required-note">Bắt buộc</span></>, secondPassword, setSecondPassword, { autoComplete: 'off', placeholder: 'Tuỳ bạn đặt' }, 'Tuỳ bạn đặt, dùng ở bước đăng nhập thứ hai.')}

          <button type="button" className="optional-toggle" aria-expanded={wipeOpen} aria-controls="wipe-password-fields" onClick={toggleWipe}>
            <span><strong>Mật khẩu xoá dữ liệu</strong><small>Không bắt buộc · Có thể đặt sau trong Tài khoản</small></span>
            <span aria-hidden="true">{wipeOpen ? '−' : '+'}</span>
          </button>
          {wipeOpen && (
            <div id="wipe-password-fields" className="optional-content">
              <p className="optional-desc">Nếu nhập mật khẩu này khi đăng nhập, ứng dụng sẽ mở bước xác nhận xoá dữ liệu vĩnh viễn. Mật khẩu này phải khác hai mật khẩu trên.</p>
              {pw('wipePassword', 'reg-wipe-password', 'Mật khẩu xoá dữ liệu', wipePassword, setWipePassword, { autoComplete: 'off', placeholder: 'Tuỳ bạn đặt' })}
            </div>
          )}

          <AppButton variant="primary" block type="submit" loading={loading}>{loading ? 'Đang tạo tài khoản...' : 'Tạo tài khoản'}</AppButton>
          <AppButton variant="ghost" block disabled={loading} onClick={goToAccount}>Quay lại</AppButton>
        </form>
      )}

      {stage === 'recovery_code' && (
        <div>
          <RecoveryCodeDisplay code={recoveryCode} continueText="Tiếp tục" onConfirmed={() => { setRecoveryCode(''); setStage('second_password') }} />
        </div>
      )}

      {stage === 'second_password' && (
        <form onSubmit={submitStep2}>
          {errBox()}
          <p className="security-intro">Nhập lại mật khẩu lớp hai bạn vừa đặt để hoàn tất đăng ký.</p>
          <div className="field">
            <label htmlFor="step2-password">Mật khẩu lớp hai</label>
            <PasswordInput id="step2-password" value={step2Password} onChange={setStep2Password} autoComplete="off" placeholder="Nhập mật khẩu lớp hai" disabled={loading} aria-invalid={!!error} />
          </div>
          <AppButton variant="primary" block type="submit" loading={loading}>{loading ? 'Đang xử lý...' : 'Hoàn tất đăng ký'}</AppButton>
        </form>
      )}
    </AuthLayout>
  )
}
