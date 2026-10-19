'use client'
import './AuthForms.css'
import { useEffect, useState } from 'react'
import AppButton from './AppButton'
import AuthLayout from './AuthLayout'
import PasswordInput from './PasswordInput'
import RecoveryCodeDisplay from './RecoveryCodeDisplay'
import { useAuthStore } from '@/lib/authStore'
import {
  UNKNOWN_RESPONSE, confirmWipe, credentialsProblem, errMsg, helpProblem, loginStageOf, loginStep1, loginStep2,
  recoverProblem, recoverWithCode, recoverWithTicket, requestHelp, secondPasswordProblem, ticketProblem,
} from '@/lib/authFlow'

// /login - all stages POST /api/auth/login can return (see lib/authFlow.js). After a successful sign-in the route guard
// (AuthGate) sends the person to ?redirect= or their home.
type Stage = 'credentials' | 'second_password' | 'wipe_confirm' | 'wipe_done' | 'recover' | 'recover_code' | 'help_request' | 'help_sent' | 'ticket'

const TITLES: Record<Stage, string> = {
  credentials: 'Chào mừng trở lại',
  second_password: 'Xác minh tài khoản',
  recover: 'Khôi phục mật khẩu',
  help_request: 'Nhờ Admin hỗ trợ',
  help_sent: 'Nhờ Admin hỗ trợ',
  ticket: 'Nhập mã hỗ trợ',
  recover_code: 'Lưu mã khôi phục mới',
  wipe_confirm: 'Xác nhận xoá dữ liệu',
  wipe_done: 'Hoàn tất',
}

type Extra = Omit<React.InputHTMLAttributes<HTMLInputElement>, 'value' | 'onChange' | 'type'>

const Err = ({ error }: { error: string }) => (error ? <div className="alert alert-error" role="alert">{error}</div> : null)

export default function LoginScreen() {
  const [stage, setStage] = useState<Stage>('credentials')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [secondPassword, setSecondPassword] = useState('')
  const [pendingToken, setPendingToken] = useState('')
  const [wipeToken, setWipeToken] = useState('')
  const [wipeAck, setWipeAck] = useState(false)

  const [recoverUsername, setRecoverUsername] = useState('')
  const [recoverCode, setRecoverCode] = useState('')
  const [recoverNewPassword, setRecoverNewPassword] = useState('')
  const [recoverConfirm, setRecoverConfirm] = useState('')
  const [newRecoveryCode, setNewRecoveryCode] = useState('')
  const [helpNote, setHelpNote] = useState('')
  const [helpMessage, setHelpMessage] = useState('')
  const [ticketCode, setTicketCode] = useState('')

  // Cursor starts in the username box.
  useEffect(() => document.getElementById('username')?.focus({ preventScroll: true }), [])

  // Runs one request: shows the error, keeps the busy flag.
  async function run(fn: () => Promise<void>) {
    setError('')
    setLoading(true)
    try {
      await fn()
    } catch (e) {
      setError(errMsg(e))
    } finally {
      setLoading(false)
    }
  }
  const fail = (msg: string) => (setError(msg), true)

  function handleStage(res: unknown) {
    const s = loginStageOf(res)
    if (s.kind === 'done') return useAuthStore.getState().login(s.token, s.role)
    if (s.kind === 'second_password') {
      setPendingToken(s.pendingToken)
      setSecondPassword('')
      return setStage('second_password')
    }
    if (s.kind === 'wipe_confirm') {
      setWipeToken(s.wipeToken)
      setWipeAck(false)
      return setStage('wipe_confirm')
    }
    setError(UNKNOWN_RESPONSE)
  }

  const submitCredentials = (e: React.FormEvent) => {
    e.preventDefault()
    const p = credentialsProblem(username, password)
    if (p) return void fail(p)
    run(async () => handleStage(await loginStep1(username, password)))
  }
  const submitSecond = (e: React.FormEvent) => {
    e.preventDefault()
    const p = secondPasswordProblem(secondPassword)
    if (p) return void fail(p)
    run(async () => handleStage(await loginStep2(pendingToken, secondPassword)))
  }
  const doConfirmWipe = () => {
    if (!wipeAck) return
    run(async () => {
      await confirmWipe(wipeToken)
      setStage('wipe_done')
    })
  }

  function backToCredentials() {
    setStage('credentials')
    setPassword('')
    setSecondPassword('')
    setError('')
  }
  function startRecover() {
    setError('')
    setRecoverUsername(username.trim())
    setRecoverCode('')
    setRecoverNewPassword('')
    setRecoverConfirm('')
    setStage('recover')
  }
  const submitRecover = (e: React.FormEvent) => {
    e.preventDefault()
    const p = recoverProblem({ username: recoverUsername, code: recoverCode, newPassword: recoverNewPassword, confirm: recoverConfirm })
    if (p) return void fail(p)
    run(async () => {
      const res = await recoverWithCode({ username: recoverUsername, code: recoverCode, newPassword: recoverNewPassword })
      setNewRecoveryCode(res.recoveryCode)
      setRecoverCode('')
      setRecoverNewPassword('')
      setRecoverConfirm('')
      setStage('recover_code')
    })
  }

  // ---- Admin-assisted recovery (A06): lost the recovery code too ----
  function startHelp() {
    setError('')
    setRecoverUsername(recoverUsername || username.trim())
    setHelpNote('')
    setStage('help_request')
  }
  const submitHelp = (e: React.FormEvent) => {
    e.preventDefault()
    const p = helpProblem(recoverUsername)
    if (p) return void fail(p)
    run(async () => {
      const res = await requestHelp(recoverUsername, helpNote)
      setHelpMessage(res.message)
      setStage('help_sent')
    })
  }
  function startTicket() {
    setError('')
    setRecoverUsername(recoverUsername || username.trim())
    setTicketCode('')
    setRecoverNewPassword('')
    setRecoverConfirm('')
    setStage('ticket')
  }
  const submitTicket = (e: React.FormEvent) => {
    e.preventDefault()
    const p = ticketProblem({ username: recoverUsername, ticket: ticketCode, newPassword: recoverNewPassword, confirm: recoverConfirm })
    if (p) return void fail(p)
    run(async () => {
      const res = await recoverWithTicket({ username: recoverUsername, ticket: ticketCode, newPassword: recoverNewPassword })
      setNewRecoveryCode(res.recoveryCode)
      setTicketCode('')
      setRecoverNewPassword('')
      setRecoverConfirm('')
      setStage('recover_code')
    })
  }
  function recoverDone() {
    setNewRecoveryCode('')
    backToCredentials()
  }

  const textField = (id: string, label: string, value: string, set: (v: string) => void, extra: Extra = {}) => (
    <div className="field">
      <label htmlFor={id}>{label}</label>
      <div className="input-wrap">
        <input id={id} value={value} onChange={(e) => set(e.target.value)} type="text" disabled={loading} {...extra} />
      </div>
    </div>
  )
  const pwField = (id: string, label: string, value: string, set: (v: string) => void, extra: Extra = {}) => (
    <div className="field">
      <label htmlFor={id}>{label}</label>
      <PasswordInput id={id} value={value} onChange={set} disabled={loading} {...extra} />
    </div>
  )

  return (
    <AuthLayout mode="login" showTabs={stage === 'credentials'} title={TITLES[stage]} subtitle="Dữ liệu của bạn, trong tầm kiểm soát">
      {stage === 'credentials' && (
        <form onSubmit={submitCredentials}>
          <Err error={error} />
          {textField('username', 'Tên đăng nhập', username, setUsername, { autoComplete: 'username', placeholder: 'Nhập tên đăng nhập', 'aria-invalid': !!error })}
          {pwField('password', 'Mật khẩu', password, setPassword, { autoComplete: 'current-password', placeholder: 'Nhập mật khẩu', 'aria-invalid': !!error })}
          <div className="auth-link-row"><button type="button" className="auth-link-button" onClick={startRecover}>Quên mật khẩu?</button></div>
          <AppButton variant="primary" block type="submit" loading={loading}>{loading ? 'Đang xử lý...' : 'Đăng nhập'}</AppButton>
        </form>
      )}

      {stage === 'second_password' && (
        <form onSubmit={submitSecond}>
          <Err error={error} />
          <p className="auth-stage-description">Nhập mật khẩu lớp hai để tiếp tục.</p>
          {pwField('second-password', 'Mật khẩu lớp hai', secondPassword, setSecondPassword, { autoComplete: 'off', placeholder: 'Nhập mật khẩu lớp hai', 'aria-invalid': !!error })}
          <AppButton variant="primary" block type="submit" loading={loading}>{loading ? 'Đang xử lý...' : 'Xác nhận'}</AppButton>
          <AppButton variant="ghost" block onClick={backToCredentials}>Quay lại</AppButton>
        </form>
      )}

      {stage === 'recover' && (
        <form onSubmit={submitRecover}>
          <Err error={error} />
          <p className="auth-stage-description">
            Nhập tên đăng nhập và mã khôi phục để đặt mật khẩu mới. Sau khi đặt lại, bạn sẽ nhận một mã khôi phục mới (mã cũ không dùng được nữa).
          </p>
          {textField('rec-username', 'Tên đăng nhập', recoverUsername, setRecoverUsername, { autoComplete: 'username' })}
          {textField('rec-code', 'Mã khôi phục', recoverCode, setRecoverCode, { autoComplete: 'off', placeholder: 'XXXX-XXXX-XXXX-XXXX' })}
          {pwField('rec-new', 'Mật khẩu mới', recoverNewPassword, setRecoverNewPassword, { autoComplete: 'new-password', placeholder: 'Tuỳ bạn đặt' })}
          {pwField('rec-confirm', 'Nhập lại mật khẩu mới', recoverConfirm, setRecoverConfirm, { autoComplete: 'new-password' })}
          <AppButton variant="primary" block type="submit" loading={loading}>{loading ? 'Đang xử lý...' : 'Đặt lại mật khẩu'}</AppButton>
          <div className="auth-link-row"><button type="button" className="auth-link-button" onClick={startHelp}>Mất cả mã khôi phục? Nhờ Admin hỗ trợ</button></div>
          <div className="auth-link-row"><button type="button" className="auth-link-button" onClick={startTicket}>Tôi đã có mã hỗ trợ từ Admin</button></div>
          <AppButton variant="ghost" block onClick={backToCredentials}>Quay lại đăng nhập</AppButton>
        </form>
      )}

      {stage === 'help_request' && (
        <form onSubmit={submitHelp}>
          <Err error={error} />
          <p className="auth-stage-description">
            Gửi yêu cầu để quản trị viên hỗ trợ. Admin sẽ xác minh bạn là chủ tài khoản qua kênh hỗ trợ (ví dụ số điện thoại hoặc tin nhắn đã đăng ký);
            khi được duyệt bạn nhận một <strong>mã hỗ trợ dùng một lần, hạn 24 giờ</strong> để tự đặt mật khẩu mới. Admin không biết mật khẩu của bạn.
          </p>
          {textField('help-username', 'Tên đăng nhập', recoverUsername, setRecoverUsername, { autoComplete: 'username' })}
          {textField('help-note', 'Thông tin giúp Admin xác minh (không bắt buộc)', helpNote, setHelpNote, { maxLength: 300, placeholder: 'Ví dụ: tên, số điện thoại liên hệ' })}
          <AppButton variant="primary" block type="submit" loading={loading}>{loading ? 'Đang gửi...' : 'Gửi yêu cầu'}</AppButton>
          <AppButton variant="ghost" block onClick={() => setStage('recover')}>Quay lại</AppButton>
        </form>
      )}

      {stage === 'help_sent' && (
        <div>
          <div className="alert alert-success">{helpMessage}</div>
          <AppButton variant="primary" block onClick={startTicket}>Tôi đã có mã hỗ trợ</AppButton>
          <AppButton variant="ghost" block onClick={backToCredentials}>Về trang đăng nhập</AppButton>
        </div>
      )}

      {stage === 'ticket' && (
        <form onSubmit={submitTicket}>
          <Err error={error} />
          <p className="auth-stage-description">Nhập mã hỗ trợ Admin đã gửi cho bạn và đặt mật khẩu mới. Mã chỉ dùng được một lần.</p>
          {textField('tk-username', 'Tên đăng nhập', recoverUsername, setRecoverUsername, { autoComplete: 'username' })}
          {textField('tk-code', 'Mã hỗ trợ', ticketCode, setTicketCode, { autoComplete: 'off', placeholder: 'XXXX-XXXX-XXXX-XXXX' })}
          {pwField('tk-new', 'Mật khẩu mới', recoverNewPassword, setRecoverNewPassword, { autoComplete: 'new-password', placeholder: 'Tuỳ bạn đặt' })}
          {pwField('tk-confirm', 'Nhập lại mật khẩu mới', recoverConfirm, setRecoverConfirm, { autoComplete: 'new-password' })}
          <AppButton variant="primary" block type="submit" loading={loading}>{loading ? 'Đang xử lý...' : 'Đặt lại mật khẩu'}</AppButton>
          <AppButton variant="ghost" block onClick={backToCredentials}>Quay lại đăng nhập</AppButton>
        </form>
      )}

      {stage === 'recover_code' && (
        <div>
          <div className="alert alert-success">Đã đặt lại mật khẩu. Đây là mã khôi phục mới của bạn.</div>
          <RecoveryCodeDisplay code={newRecoveryCode} continueText="Về trang đăng nhập" onConfirmed={recoverDone} />
        </div>
      )}

      {stage === 'wipe_confirm' && (
        <div>
          <div className="alert alert-warning">
            Cảnh báo: mật khẩu bạn vừa nhập là <strong>mật khẩu xoá dữ liệu</strong>. Nếu tiếp tục, số liệu đã nhập, danh sách khách hàng, mẫu cú pháp, lịch xoá tự động,
            nhật ký cuộc gọi, tin nhắn phản hồi với Admin, lịch sử giao dịch và yêu cầu thanh toán chưa duyệt của tài khoản này
            sẽ bị xoá <strong>vĩnh viễn và không thể khôi phục</strong>. Tài khoản, bạn bè và tin nhắn với bạn bè được giữ nguyên. Thao tác này
            sẽ không đăng nhập bạn vào tài khoản.
          </div>
          <Err error={error} />
          <label style={{ display: 'flex', gap: 8, alignItems: 'flex-start', fontSize: 14, marginBottom: 16, cursor: 'pointer' }}>
            <input checked={wipeAck} onChange={(e) => setWipeAck(e.target.checked)} type="checkbox" style={{ marginTop: 3 }} />
            <span>Tôi hiểu rằng thao tác này sẽ xoá vĩnh viễn các dữ liệu nêu trên của tài khoản này.</span>
          </label>
          <AppButton variant="danger" block disabled={!wipeAck || loading} onClick={doConfirmWipe}>{loading ? 'Đang xử lý...' : 'Xác nhận xoá dữ liệu'}</AppButton>
          <AppButton variant="ghost" block onClick={backToCredentials}>Huỷ, quay lại đăng nhập</AppButton>
        </div>
      )}

      {stage === 'wipe_done' && (
        <div>
          <div className="alert alert-success">Dữ liệu của tài khoản đã được xoá. Bạn có thể đăng nhập lại bình thường.</div>
          <AppButton variant="primary" block onClick={backToCredentials}>Về trang đăng nhập</AppButton>
        </div>
      )}
    </AuthLayout>
  )
}
