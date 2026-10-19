'use client'
import './DeletionSchedules.css'
import { useEffect, useRef, useState } from 'react'
import AppButton from '@/components/AppButton'
import AppDatePicker from '@/components/AppDatePicker'
import AppSelect from '@/components/AppSelect'
import PasswordInput from '@/components/PasswordInput'
import { api } from '@/lib/api'
import { showConfirm } from '@/lib/confirm'
import { buildScheduleBody, confirmMessage, defaultRunAt, describe, fmt, repeatText, statusText } from './scheduleLogic'

// "Lịch xoá dữ liệu": đặt lịch tự xoá số liệu đã lưu (một khách hoặc tất cả, khoảng ngày tuỳ chọn - hoặc lặp lại, giữ lại
// N ngày gần nhất) và xem/huỷ mọi lịch đang chờ, kể cả lịch tự xoá đặt trên cuộc trò chuyện với bạn bè (ChatRetentionPanel).
// Dùng chung cho trang Tài khoản (thẻ) và trang Tính điểm (trong hộp thoại, `embedded`). Trước khi lưu, máy chủ trả bản xem
// trước (xoá gì, lần chạy đầu, chạy ngay sẽ xoá bao nhiêu) hiện trong hộp xác nhận; không có bước đó thì không tạo gì.
// API: GET/POST /me/deletion-schedules, DELETE /me/deletion-schedules/:id, GET /me/customers
// Lịch lặp không bao giờ kèm dateFrom/dateTo (máy chủ từ chối).
export interface DeletionSchedulesProps {
  customerName?: string // khách chọn sẵn ('' = tất cả)
  embedded?: boolean // không thẻ/tiêu đề ngoài (dùng trong hộp thoại)
  onChanged?: () => void
}

interface Form {
  customerName: string
  dateFrom: string
  dateTo: string
  repeat: 'none' | '1w' | '10d' | '1m' | 'custom'
  customN: string
  customUnit: 'day' | 'week' | 'month'
  keepDays: string
  runAt: string
  password: string
}

export default function DeletionSchedules({ customerName = '', embedded = false, onChanged }: DeletionSchedulesProps) {
  const [schedules, setSchedules] = useState<any[]>([])
  const [customers, setCustomers] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')
  const [saving, setSaving] = useState(false)
  const [form, setForm] = useState<Form>({
    customerName, dateFrom: '', dateTo: '', repeat: 'none', customN: '2', customUnit: 'day', keepDays: '0', runAt: '', password: '',
  })
  const runAtTouched = useRef(false)

  // Khách chọn sẵn đổi theo props (như watch(customerName) bên Vue).
  const [prevCustomer, setPrevCustomer] = useState(customerName)
  if (prevCustomer !== customerName) {
    setPrevCustomer(customerName)
    setForm((f) => ({ ...f, customerName }))
  }

  // Đổi lặp: lần chạy đầu mặc định đi theo chu kỳ cho tới khi người dùng tự nhập; lặp thì bỏ khoảng ngày.
  function update(patch: Partial<Form>) {
    setForm((f) => {
      const next = { ...f, ...patch }
      if ('repeat' in patch || 'customN' in patch || 'customUnit' in patch) {
        if (!runAtTouched.current) next.runAt = defaultRunAt(next)
      }
      if ('repeat' in patch && patch.repeat !== 'none') {
        next.dateFrom = ''
        next.dateTo = ''
      }
      return next
    })
  }

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
    // eslint-disable-next-line react-hooks/set-state-in-effect -- the first run time is "now + one cycle", known only on the client
    setForm((f) => ({ ...f, runAt: defaultRunAt(f) }))
    load()
  }, [])

  async function submit(e: React.FormEvent) {
    e.preventDefault()
    setError('')
    setSuccess('')
    const built = buildScheduleBody(form)
    if (built.error) return setError(built.error)
    const { body, repeat } = built
    setSaving(true)
    try {
      // Bước 1: máy chủ mô tả chính xác sẽ xoá gì và khi nào.
      const preview = await api.post('/me/deletion-schedules', body)
      const ok = await showConfirm({
        title: 'Xác nhận lịch xoá dữ liệu',
        message: confirmMessage(preview, body, repeat),
        confirmText: 'Đặt lịch xoá',
        danger: true,
      })
      if (!ok) return
      // Bước 2: đã xác nhận.
      await api.post('/me/deletion-schedules', { ...body, confirm: true, password: form.password })
      setForm((f) => ({ ...f, password: '' }))
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
      message: `Huỷ lịch này? ${describe(s)}. Dữ liệu đã bị xoá trước đó sẽ không được khôi phục.`,
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
    <div className={`ds-root${embedded ? '' : ' card'}`}>
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

      <form className="sched-form" onSubmit={submit}>
        <div className="field">
          <label>Khách hàng</label>
          <AppSelect value={form.customerName} onChange={(v) => update({ customerName: v })}>
            <option value="">Tất cả khách hàng</option>
            {customers.map((c) => <option key={c.id} value={c.name}>{c.name}</option>)}
          </AppSelect>
        </div>
        <div className="field">
          <label>Lặp lại</label>
          <AppSelect value={form.repeat} onChange={(v) => update({ repeat: v })}>
            <option value="none">Không lặp (chỉ một lần)</option>
            <option value="1w">Mỗi 1 tuần</option>
            <option value="10d">Mỗi 10 ngày</option>
            <option value="1m">Mỗi 1 tháng</option>
            <option value="custom">Tuỳ chọn</option>
          </AppSelect>
        </div>
        {form.repeat === 'custom' && (
          <div className="sched-dates">
            <div className="field">
              <label htmlFor="sched-n">Mỗi (số)</label>
              <input id="sched-n" value={form.customN} onChange={(e) => update({ customN: e.target.value })} type="number" min={1} max={365} inputMode="numeric" />
            </div>
            <div className="field">
              <label>Đơn vị</label>
              <AppSelect value={form.customUnit} onChange={(v) => update({ customUnit: v })}>
                <option value="day">ngày</option>
                <option value="week">tuần</option>
                <option value="month">tháng</option>
              </AppSelect>
            </div>
          </div>
        )}
        {form.repeat === 'none' && (
          <div className="sched-dates">
            <div className="field">
              <label>Từ ngày (tuỳ chọn)</label>
              <AppDatePicker value={form.dateFrom} onChange={(v) => update({ dateFrom: v })} />
            </div>
            <div className="field">
              <label>Đến ngày (tuỳ chọn)</label>
              <AppDatePicker value={form.dateTo} onChange={(v) => update({ dateTo: v })} />
            </div>
          </div>
        )}
        <div className="field">
          <label htmlFor="sched-keep">Giữ lại N ngày gần nhất</label>
          <input id="sched-keep" value={form.keepDays} onChange={(e) => update({ keepDays: e.target.value })} type="number" min={0} max={3650} inputMode="numeric" />
          {form.repeat !== 'none' && <small className="sched-hint">Mỗi lần chạy xoá số liệu cũ hơn số ngày này (0 = xoá hết).</small>}
        </div>
        <div className="field">
          <label htmlFor="sched-run-at">{form.repeat === 'none' ? 'Thời điểm xoá' : 'Thời điểm xoá đầu tiên'}</label>
          <input
            id="sched-run-at"
            value={form.runAt}
            onChange={(e) => {
              runAtTouched.current = true
              update({ runAt: e.target.value })
            }}
            type="datetime-local"
          />
        </div>
        <div className="field">
          <label htmlFor="sched-password">Mật khẩu đăng nhập</label>
          <PasswordInput id="sched-password" value={form.password} onChange={(v) => update({ password: v })} autoComplete="current-password" />
        </div>
        <AppButton variant="danger" type="submit" disabled={saving}>{saving ? 'Đang xử lý...' : 'Đặt lịch xoá'}</AppButton>
      </form>

      {loading ? (
        <div style={{ marginTop: 12 }}>Đang tải...</div>
      ) : schedules.length === 0 ? (
        <div className="page-subtitle" style={{ margin: '12px 0 0' }}>Chưa có lịch xoá nào.</div>
      ) : (
        <div className="sched-list">
          {schedules.map((s) => (
            <div key={s.id} className="sched-item">
              <div className="sched-text">
                <strong>{describe(s)}</strong>
                {s.repeat && <span className="sched-status">Lặp lại mỗi {repeatText(s.repeat)}</span>}
                {s.kind === 'data' && s.repeat && s.status === 'pending' ? (
                  <span className="sched-status">Lần chạy kế tiếp: {fmt(s.nextRunAt || s.runAt)}</span>
                ) : (
                  <span className="sched-status">
                    {statusText(s)}
                    {s.kind === 'chat' && !s.setByMe ? ' - do bạn bè đặt' : null}
                  </span>
                )}
                {s.kind === 'data' && s.repeat && (
                  <span className="sched-status">
                    Đã chạy {s.runCount || 0} lần, xoá tổng {s.deletedCount || 0} số liệu
                    {s.lastRunAt ? ` (lần cuối ${fmt(s.lastRunAt)})` : null}
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
