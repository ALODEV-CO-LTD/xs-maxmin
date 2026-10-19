'use client'
import './RecoveryCodeDisplay.css'
import { useState } from 'react'
import AppButton from './AppButton'

// Shows a mã khôi phục exactly once and makes the user confirm they saved it before continuing. Used by Register,
// Login (after a reset) and RecoveryCodePanel (Tài khoản). `onConfirmed` fires when they continue. The code is only
// held in the parent's memory - never stored client-side.
export default function RecoveryCodeDisplay({ code, continueText = 'Tiếp tục', onConfirmed }: { code: string; continueText?: string; onConfirmed: () => void }) {
  const [saved, setSaved] = useState(false)
  const [copied, setCopied] = useState(false)

  async function copy() {
    try {
      await navigator.clipboard.writeText(code)
      setCopied(true)
    } catch {
      setCopied(false)
    }
  }

  return (
    <div className="rc">
      <div className="alert alert-warning">
        Đây là <strong>mã khôi phục</strong> của bạn. Mã chỉ hiển thị <strong>một lần duy nhất</strong> và không ai (kể cả quản trị viên) xem lại được. Hãy ghi lại hoặc lưu ở nơi an toàn. Có mã này, bạn đặt lại được mật khẩu khi quên - vì vậy đừng chia sẻ cho người khác.
      </div>
      <div className="rc-code" aria-label="Mã khôi phục">{code}</div>
      <AppButton variant="secondary" block onClick={copy}>{copied ? 'Đã sao chép' : 'Sao chép mã'}</AppButton>
      <label className="rc-ack">
        <input type="checkbox" checked={saved} onChange={(e) => setSaved(e.target.checked)} />
        <span>Tôi đã lưu mã khôi phục ở nơi an toàn.</span>
      </label>
      <AppButton variant="primary" block disabled={!saved} onClick={onConfirmed}>{continueText}</AppButton>
    </div>
  )
}
