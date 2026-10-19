'use client'
import './DeletionSchedules.css'
import { useEffect, useRef, useState } from 'react'
import AppButton from '@/components/AppButton'
import AppDatePicker from '@/components/AppDatePicker'
import AppSelect from '@/components/AppSelect'
import PasswordInput from '@/components/PasswordInput'
import { api } from '@/lib/api'
import { showConfirm } from '@/lib/confirm'
import { defaultRunAt, describeSchedule, fmtTime, repeatText, scheduleCheck, scheduleConfirmMessage, scheduleStatusText } from './accountLogic'

// "Lịch xoá dữ liệu": schedule the automatic removal of your saved entries (one customer or everyone, optionally a date
// range - or repeating, keeping the newest N days) and see/cancel every pending schedule, including the auto-delete
// rules set on friend conversations. Shared by the Tài khoản page (a card) and the Tính điểm page (inside a dialog,
// `embedded`). Before anything is saved the server returns a preview that is shown in a confirm dialog.
// API: GET/POST /me/deletion-schedules, DELETE /me/deletion-schedules/:id, GET /me/customers
// A repeating schedule never carries dateFrom/dateTo (the server refuses it).
/* eslint-disable @typescript-eslint/no-explicit-any */
export interface DeletionSchedulesProps {
  customerName?: string // pre-selected customer name ('' = all customers)
  embedded?: boolean // no outer card / heading (used inside a dialog)
  onChanged?: () => void
}

export default function DeletionSchedules({ customerName = '', embedded = false, onChanged }: DeletionSchedulesProps) {
  const [schedules, setSchedules] = useState<any[]>([])
  const [customers, setCustomers] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState({
    customerName,
    dateFrom: '',
    dateTo: '',
    repeat: 'none', // none | 1w | 10d | 1m | custom
    customN: 2 as number | string,
    customUnit: 'day',
    keepDays: 0 as number | string,
    runAt: '',
    password: '',
  })
  const set = (p: Partial<typeof form>) => setForm((f) => ({ ...f, ...p }))
  const runAtTouched = useRef(false)

  // Default first run = now + one cycle, until the user types their own.
  useEffect(() => {
    if (!runAtTouched.current) setForm((f) => ({ ...f, runAt: defaultRunAt(f) }))
  }, [form.repeat, form.customN, form.customUnit])
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    if (form.repeat !== 'none') setForm((f) => ({ ...f, dateFrom: '', dateTo: '' }))
  }, [form.repeat])
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => set({ customerName }), [customerName])

  async function load() {
    setLoading(true)
    try {
      const [s, c] = await Promise.all([api.get('/me/deletion-schedules'), api.get('/me/customers')])
      setSchedules(s.schedules)
      setCustomers(c.customers)
    } catch (err) {
      setError((err as Error).message || 'Không tải được lịch xoá')
    } finally {
      setLoading(false)
    }
  }
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    load()
  }, [])

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    setError('')
    setSuccess('')
    const chk = scheduleCheck(form)
    if (chk.error) return setError(chk.error)
    const { body, repeat } = chk
    setSaving(true)
    try {
      // Step 1: the server describes exactly what would be deleted and when.
      const preview = await api.post('/me/deletion-schedules', body)
      const ok = await showConfirm({
        title: 'Xác nhận lịch xoá dữ liệu',
        message: scheduleConfirmMessage(preview, repeat, body),
        confirmText: 'Đặt lịch xoá',
        danger: true,
      })
      if (!ok) return
      // Step 2: confirmed.
      await api.post('/me/deletion-schedules', { ...body, confirm: true, password: form.password })
      set({ password: '' })
      setSuccess('Đã đặt lịch xoá.')
      await load()
      onChanged?.()
    } catch (err) {
      setError((err as Error).message || 'Không đặt được lịch xoá')
    } finally {
      setSaving(false)
    }
  }

  async function cancel(s: any) {
    if (!(await showConfirm({
      title: 'Huỷ lịch xoá',
      message: `Huỷ lịch này? ${describeSchedule(s)}. Dữ liệu đã bị xoá trước đó sẽ không được khôi phục.`,
      confirmText: 'Huỷ lịch',
    }))) return
    try {
      await api.del(`/me/deletion-schedules/${s.id}`)
      await load()
      onChanged?.()
    } catch (err) {
      setError((err as Error).message || 'Không huỷ được lịch xoá')
    }
  }

  return (
    <div className={embedded ? undefined : 'card'}>
      {!embedded && (
        <>
          <h3 style={{ marginTop: 0 }}>Lịch xoá dữ liệu</h3>
          <p className="page-subtitle" style={{ marginBottom: 12 }}>
            Đặt thời điểm hệ thống tự xoá số liệu đã lưu của bạn, một lần hoặc lặp lại. Bạn sẽ thấy cảnh báo về phạm vi xoá và thời điểm
            trước khi xác nhận, và có thể huỷ lịch bất cứ lúc nào trước khi chạy. Dữ liệu đã xoá không thể khôi phục.
          </p>
        </>
      )}
      {error && <div className="alert alert-error">{error}</div>}
      {success && <div className="alert alert-success">{success}</div>}

      <form onSubmit={submit}>
        <div className="field">
          <label>Khách hàng</label>
          <AppSelect value={form.customerName} onChange={(v) => set({ customerName: v })}>
            <option value="">Tất cả khách hàng</option>
            {customers.map((c) => <option key={c.id} value={c.name}>{c.name}</option>)}
          </AppSelect>
        </div>
        <div className="field">
          <label>Lặp lại</label>
          <AppSelect value={form.repeat} onChange={(v) => set({ repeat: v })}>
            <option value="none">Không lặp (chỉ một lần)</option>
            <option value="1w">Mỗi 1 tuần</option>
            <option value="10d">Mỗi 10 ngày</option>
            <option value="1m">Mỗi 1 tháng</option>
            <option value="custom">Tuỳ chọn</option>
          </AppSelect>
        </div>
        {form.repeat === 'custom' && (
          <div className="ds-dates">
            <div className="field">
              <label htmlFor="sched-n">Mỗi (số)</label>
              <input id="sched-n" value={form.customN} onChange={(e) => set({ customN: e.target.value === '' ? '' : Number(e.target.value) })} type="number" min={1} max={365} inputMode="numeric" />
            </div>
            <div className="field">
              <label>Đơn vị</label>
              <AppSelect value={form.customUnit} onChange={(v) => set({ customUnit: v })}>
                <option value="day">ngày</option>
                <option value="week">tuần</option>
                <option value="month">tháng</option>
              </AppSelect>
            </div>
          </div>
        )}
        {form.repeat === 'none' && (
          <div className="ds-dates">
            <div className="field">
              <label>Từ ngày (tuỳ chọn)</label>
              <AppDatePicker value={form.dateFrom} onChange={(v) => set({ dateFrom: v })} />
            </div>
            <div className="field">
              <label>Đến ngày (tuỳ chọn)</label>
              <AppDatePicker value={form.dateTo} onChange={(v) => set({ dateTo: v })} />
            </div>
          </div>
        )}
        <div className="field">
          <label htmlFor="sched-keep">Giữ lại N ngày gần nhất</label>
          <input id="sched-keep" value={form.keepDays} onChange={(e) => set({ keepDays: e.target.value === '' ? '' : Number(e.target.value) })} type="number" min={0} max={3650} inputMode="numeric" />
          {form.repeat !== 'none' && <small className="ds-hint">Mỗi lần chạy xoá số liệu cũ hơn số ngày này (0 = xoá hết).</small>}
        </div>
        <div className="field">
          <label htmlFor="sched-run-at">{form.repeat === 'none' ? 'Thời điểm xoá' : 'Thời điểm xoá đầu tiên'}</label>
          <input id="sched-run-at" value={form.runAt} onChange={(e) => set({ runAt: e.target.value })} onInput={() => (runAtTouched.current = true)} type="datetime-local" />
        </div>
        <div className="field">
          <label htmlFor="sched-password">Mật khẩu đăng nhập</label>
          <PasswordInput id="sched-password" value={form.password} onChange={(v) => set({ password: v })} autoComplete="current-password" />
        </div>
        <AppButton variant="danger" type="submit" disabled={saving}>{saving ? 'Đang xử lý...' : 'Đặt lịch xoá'}</AppButton>
      </form>

      {loading ? (
        <div style={{ marginTop: 12 }}>Đang tải...</div>
      ) : schedules.length === 0 ? (
        <div className="page-subtitle" style={{ margin: '12px 0 0' }}>Chưa có lịch xoá nào.</div>
      ) : (
        <div className="ds-list">
          {schedules.map((s) => (
            <div key={s.id} className="ds-item">
              <div className="ds-text">
                <strong>{describeSchedule(s)}</strong>
                {s.repeat && <span className="ds-status">Lặp lại mỗi {repeatText(s.repeat)}</span>}
                {s.kind === 'data' && s.repeat && s.status === 'pending' ? (
                  <span className="ds-status">Lần chạy kế tiếp: {fmtTime(s.nextRunAt || s.runAt)}</span>
                ) : (
                  <span className="ds-status">
                    {scheduleStatusText(s)}
                    {s.kind === 'chat' && !s.setByMe && ' - do bạn bè đặt'}
                  </span>
                )}
                {s.kind === 'data' && s.repeat && (
                  <span className="ds-status">
                    Đã chạy {s.runCount || 0} lần, xoá tổng {s.deletedCount || 0} số liệu
                    {s.lastRunAt && ` (lần cuối ${fmtTime(s.lastRunAt)})`}
                  </span>
                )}
              </div>
              {s.status === 'pending' && <AppButton variant="ghost" size="sm" onClick={() => cancel(s)}>Huỷ lịch</AppButton>}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
