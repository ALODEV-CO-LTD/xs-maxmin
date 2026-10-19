'use client'
import './DeleteDataDialog.css'
import { useEffect, useRef, useState } from 'react'
import AppButton from '@/components/AppButton'
import AppDatePicker from '@/components/AppDatePicker'
import AppSelect from '@/components/AppSelect'
import ModalDialog from '@/components/ModalDialog'
import PasswordInput from '@/components/PasswordInput'
import { api } from '@/lib/api'
import { deleteBody, deleteProblem, hasLimit as hasLimitOf, keepOf, scopeText as scopeTextOf } from './deleteLogic'

// "Xóa số liệu": xoá ngay số liệu đã lưu - một khách hoặc tất cả, khoảng ngày tuỳ chọn, tuỳ chọn giữ lại N ngày gần nhất.
// Hiện số dòng sẽ bị xoá (chạy thử, không cần mật khẩu) và cần mật khẩu đăng nhập.
// API: POST /me/entries/bulk-delete { customerName, dateFrom, dateTo, keepDays, dryRun, password, allDataConfirmed }
//      -> { count } (dryRun) | { deleted }.  403 sai mật khẩu, 429 bị khoá.
export interface DeleteDataDialogProps {
  open?: boolean
  customerName?: string // khách đang chọn trên màn
  dateFrom?: string // khoảng đang xem
  dateTo?: string
  singleDay?: string // có giá trị khi mở từ thẻ một ngày
  onDeleted?: (n: number) => void
  onClose?: () => void
}

// Mỗi lần mở là một bản mới (state khởi tạo từ props, như watch(open) bên Vue).
export default function DeleteDataDialog(props: DeleteDataDialogProps) {
  return props.open ? <Inner {...props} /> : null
}

function Inner({ customerName = '', dateFrom = '', dateTo = '', singleDay = '', onDeleted, onClose }: DeleteDataDialogProps) {
  const [scope, setScope] = useState<'customer' | 'all'>(customerName ? 'customer' : 'all')
  const [from, setFrom] = useState(singleDay || dateFrom)
  const [to, setTo] = useState(singleDay || dateTo)
  const [keepDays, setKeepDays] = useState<string>('0')
  const [password, setPassword] = useState('')
  const [allConfirmed, setAllConfirmed] = useState(false)
  const [count, setCount] = useState<number | null>(null)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  const st = { scope, customerName, from, to, keepDays }
  const keep = keepOf(keepDays)
  const hasLimit = hasLimitOf(st)

  // Đếm số liệu sẽ bị xoá, chờ 200ms sau lần đổi cuối; bỏ kết quả của lần gọi cũ.
  const seq = useRef(0)
  const bodyNow = useRef(st)
  bodyNow.current = st
  useEffect(() => {
    const timer = setTimeout(async () => {
      const mine = ++seq.current
      setCount(null)
      try {
        const r = await api.post('/me/entries/bulk-delete', deleteBody(bodyNow.current, { dryRun: true }))
        if (mine === seq.current) setCount(r.count)
      } catch (err) {
        if (mine === seq.current) setError((err as Error).message || 'Không đếm được số liệu sẽ bị xoá')
      }
    }, 200)
    return () => clearTimeout(timer)
  }, [scope, from, to, keep])

  const change = <T,>(set: (v: T) => void) => (v: T) => {
    setError('')
    set(v)
  }

  async function submit(e?: React.FormEvent) {
    e?.preventDefault()
    if (busy) return
    setError('')
    const problem = deleteProblem(st, allConfirmed, password)
    if (problem) return setError(problem)
    setBusy(true)
    try {
      const r = await api.post('/me/entries/bulk-delete', deleteBody(st, { password }))
      setPassword('')
      onDeleted?.(r.deleted)
    } catch (err) {
      setError((err as Error).message || 'Không xoá được số liệu')
    } finally {
      setBusy(false)
    }
  }

  const rangeIsDay = from === singleDay && to === singleDay
  return (
    <ModalDialog
      open
      title="Xóa số liệu"
      description="Chọn phạm vi cần xóa. Số liệu đã xóa không thể khôi phục."
      onClose={onClose}
      footer={
        <>
          <AppButton variant="ghost" disabled={busy} onClick={onClose}>Huỷ</AppButton>
          <AppButton variant="danger" type="submit" form="del-data-form" loading={busy} disabled={count === 0}>{busy ? 'Đang xóa...' : 'Xóa'}</AppButton>
        </>
      }
    >
      <form id="del-data-form" className="dd-root" onSubmit={submit}>
        <div className="field">
          <label>Phạm vi</label>
          <AppSelect value={scope} onChange={change(setScope)}>
            {customerName && <option value="customer">Khách đang chọn: {customerName}</option>}
            <option value="all">Tất cả khách hàng</option>
          </AppSelect>
        </div>
        {singleDay && (
          <div className="dd-chips">
            <button type="button" className={`dd-chip${rangeIsDay ? ' on' : ''}`} onClick={() => { setError(''); setFrom(singleDay); setTo(singleDay) }}>
              Chỉ ngày này
            </button>
            <button type="button" className={`dd-chip${from === dateFrom && to === dateTo && !rangeIsDay ? ' on' : ''}`} onClick={() => { setError(''); setFrom(dateFrom); setTo(dateTo) }}>
              Khoảng đang xem
            </button>
          </div>
        )}
        <div className="dd-dates">
          <div className="field">
            <label>Từ ngày</label>
            <AppDatePicker value={from} onChange={change(setFrom)} />
          </div>
          <div className="field">
            <label>Đến ngày</label>
            <AppDatePicker value={to} onChange={change(setTo)} />
          </div>
        </div>
        <div className="field">
          <label htmlFor="dd-keep">Giữ lại N ngày gần nhất (tuỳ chọn)</label>
          <input id="dd-keep" value={keepDays} onChange={(e) => change(setKeepDays)(e.target.value)} type="number" min={0} max={3650} inputMode="numeric" />
        </div>

        <div className={`dd-count${count === 0 ? ' zero' : ''}`} aria-live="polite">
          {count === null ? 'Đang đếm số liệu...' : <>Sẽ xóa <strong>{count}</strong> số liệu của {scopeTextOf(st)}. Không thể khôi phục.</>}
        </div>

        {!hasLimit && (
          <label className="dd-check">
            <input checked={allConfirmed} onChange={(e) => setAllConfirmed(e.target.checked)} type="checkbox" />
            Tôi hiểu: xóa TOÀN BỘ số liệu của tất cả khách hàng
          </label>
        )}

        <div className="field">
          <label htmlFor="dd-password">Mật khẩu đăng nhập</label>
          <PasswordInput id="dd-password" value={password} onChange={setPassword} data-autofocus autoComplete="current-password" disabled={busy} />
        </div>
        {error && <div className="alert alert-error" role="alert" style={{ margin: 0 }}>{error}</div>}
      </form>
    </ModalDialog>
  )
}
