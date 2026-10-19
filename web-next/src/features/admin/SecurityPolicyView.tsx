'use client'
import './SecurityPolicyView.css'
import { useEffect, useState } from 'react'
import AppButton from '@/components/AppButton'
import { api } from '@/lib/api'
import { showConfirm } from '@/lib/confirm'
import { errMsg } from './common'
import { POLICY_DEFAULT, lockExample, policyBody } from './settingsLogic'

type Form = typeof POLICY_DEFAULT
type NumKey = { [K in keyof Form]: Form[K] extends number ? K : never }[keyof Form]
type BoolKey = { [K in keyof Form]: Form[K] extends boolean ? K : never }[keyof Form]

// Chính sách bảo mật (permission security.policy), embedded in Cài đặt. API: GET/PUT/DELETE /admin/security-policy
export default function SecurityPolicyView({ embedded = false }: { embedded?: boolean }) {
  const [loading, setLoading] = useState(true)
  const [editing, setEditing] = useState(false) // values are only displayed until "Sửa"
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [defaults, setDefaults] = useState<Partial<Form>>({})
  const [form, setForm] = useState<Form>({ ...POLICY_DEFAULT })
  const [saved, setSaved] = useState(JSON.stringify(POLICY_DEFAULT))
  const dirty = JSON.stringify(form) !== saved

  function fill(res: { policy: Form; defaults: Partial<Form> }) {
    setForm({ ...res.policy })
    setDefaults(res.defaults)
    setSaved(JSON.stringify(res.policy))
  }
  useEffect(() => {
    api
      .get('/admin/security-policy')
      .then(fill)
      .catch((err) => setError(errMsg(err, 'Không tải được chính sách bảo mật')))
      .finally(() => setLoading(false))
  }, [])

  const num = (k: NumKey, min: number, max: number, hint: string, label: string, extra = '') => (
    <label>
      {label}
      <input value={form[k]} onChange={(e) => setForm({ ...form, [k]: e.target.value === '' ? '' : Number(e.target.value) })} type="number" min={min} max={max} />
      <small>{hint} (mặc định {String(defaults[k])}){extra}</small>
    </label>
  )
  const check = (k: BoolKey, text: string) => (
    <label className="check">
      <input checked={form[k]} onChange={(e) => setForm({ ...form, [k]: e.target.checked })} type="checkbox" /> {text}
    </label>
  )

  async function save(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    setError('')
    setNotice('')
    try {
      fill(await api.put('/admin/security-policy', policyBody(form)))
      setNotice('Đã lưu chính sách bảo mật.')
      setEditing(false)
    } catch (err) {
      setError(errMsg(err, 'Không lưu được'))
    } finally {
      setSaving(false)
    }
  }
  function cancel() {
    setForm(JSON.parse(saved))
    setError('')
    setEditing(false)
  }
  async function reset() {
    if (!(await showConfirm({ title: 'Đặt lại mặc định', message: 'Đặt lại toàn bộ chính sách bảo mật về giá trị mặc định?', confirmText: 'Đặt lại' }))) return
    setSaving(true)
    setError('')
    try {
      fill(await api.del('/admin/security-policy'))
      setNotice('Đã đặt lại về mặc định.')
      setEditing(false)
    } catch (err) {
      setError(errMsg(err, 'Không đặt lại được'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="adm-policy">
      <div className={embedded ? 'embedded' : 'page'}>
        {!embedded && <h1 className="page-title">Chính sách bảo mật</h1>}
        <p className="page-subtitle">Áp dụng cho toàn hệ thống. Mọi thay đổi được ghi vào nhật ký bảo mật.</p>

        {error && <div className="alert alert-error">{error}</div>}
        {notice && <div className="alert alert-success">{notice}</div>}
        {loading ? (
          <div className="card">Đang tải...</div>
        ) : (
          <form onSubmit={save}>
            <fieldset className="ro" disabled={!editing}>
              <section className="card block">
                <h2>Chống đoán mật khẩu</h2>
                <p className="hint">Áp dụng cho đăng nhập, mật khẩu lớp hai và các ô nhập lại mật khẩu. Nhập sai quá số lần cho phép thì bị khoá tạm theo tài khoản và địa chỉ IP; mỗi lần sai tiếp theo, thời gian khoá nhân đôi đến mức tối đa.</p>
                <div className="grid">
                  {num('loginFreeAttempts', 3, 20, '3 đến 20', 'Số lần nhập sai được phép')}
                  {num('loginBaseLockSeconds', 5, 3600, '5 đến 3600', 'Khoá lần đầu (giây)')}
                  {num('loginMaxLockSeconds', 30, 86400, '30 đến 86400', 'Khoá tối đa (giây)')}
                </div>
                <p className="hint">Các lần khoá liên tiếp: {lockExample(form.loginBaseLockSeconds, form.loginMaxLockSeconds)}</p>
              </section>

              <section className="card block">
                <h2>Phiên đăng nhập</h2>
                <div className="grid">
                  {num('tokenDays', 1, 365, '1 đến 365', 'Thời hạn đăng nhập (ngày)', '. Chỉ áp dụng cho lần đăng nhập mới; phiên hiện có giữ hạn cũ.')}
                  {num('autoLockMinutes', 0, 240, '0 là tắt', 'Tự khoá màn hình mặc định (phút)', '. Chỉ dùng cho người chưa tự chọn trong Tài khoản.')}
                </div>
              </section>

              <section className="card block">
                <h2>Đóng dấu màn hình</h2>
                <p className="hint">Web không chặn được chụp màn hình. Dấu tên người xem mờ (tên, tên đăng nhập, giờ, 4 ký tự cuối mã tài khoản) phủ trên mọi màn hình, để ảnh bị lộ truy ra được tài khoản và thời điểm chụp.</p>
                {check('watermarkEnabled', 'Bật đóng dấu tên người xem')}
                <p className="hint" style={{ marginTop: 14 }}>Trên máy tính, màn hình tự bị phủ đen ngay khi giữ tổ hợp phím chụp (Cmd+Shift+3/4/5 trên Mac, Win+Shift+S trên Windows), nên ảnh chụp ra màu đen. PrintScreen chỉ đến được trang sau khi ảnh đã chụp nên chỉ xoá clipboard. Không chặn được chụp bằng điện thoại, nút cứng trên điện thoại hay quay bằng thiết bị khác; muốn chặn thật cần app.</p>
                {check('screenshotGuardEnabled', 'Phủ đen màn hình khi bấm phím chụp màn hình (máy tính)')}
                <p className="hint" style={{ marginTop: 14 }}>Làm mờ toàn bộ nội dung khi người dùng chuyển sang tab/cửa sổ khác hoặc trang mất focus (tạm bỏ qua khi đang gọi). Khi bật, mỗi người vẫn tự tắt được trong Tài khoản.</p>
                {check('blurOnHideEnabled', 'Làm mờ màn hình khi ẩn trang hoặc mất focus')}
              </section>
            </fieldset>

            <div className="actions">
              {!editing ? (
                <AppButton variant="secondary" onClick={() => setEditing(true)}>Sửa</AppButton>
              ) : (
                <>
                  <AppButton variant="ghost" disabled={saving} onClick={reset}>Đặt lại mặc định</AppButton>
                  <AppButton variant="ghost" disabled={saving} onClick={cancel}>Huỷ</AppButton>
                  <AppButton variant="primary" type="submit" disabled={saving || !dirty}>{saving ? 'Đang lưu...' : 'Lưu chính sách'}</AppButton>
                </>
              )}
            </div>
          </form>
        )}
      </div>
    </div>
  )
}
