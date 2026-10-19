'use client'
import { useEffect, useState } from 'react'
import AppButton from '@/components/AppButton'
import AppIcon from '@/components/AppIcon'
import ModalDialog from '@/components/ModalDialog'
import { api } from '@/lib/api'
import { useAuthStore } from '@/lib/authStore'
import { showConfirm } from '@/lib/confirm'
import {
  atCodeLimit, newCodePayload, passwordCheck, profileCheck, secondCheck, usernameChanged, wipeCheck, wipeVerb,
} from './accountLogic'

/* eslint-disable @typescript-eslint/no-explicit-any */
// Tài khoản > Hồ sơ: personal info (edit name / username), the package summary, the password buttons (+ their dialogs),
// logout (phones) and the Mã ID kết bạn card.
// API: PATCH /me, POST /me/password, POST /me/second-password, POST /me/wipe-password,
//      GET/POST /me/customer-codes, DELETE/PATCH /me/customer-codes/:id

type SecDialog = '' | 'password' | 'second' | 'wipe'
const Err = ({ text }: { text: string }) => (text ? <div className="alert alert-error">{text}</div> : null)
const Ok = ({ text }: { text: string }) => (text ? <div className="alert alert-success">{text}</div> : null)

export default function ProfileTab({ onLogout }: { onLogout: () => void }) {
  const user = useAuthStore((s) => s.user) as any
  const isAdmin = useAuthStore((s) => s.role === 'admin')
  const fetchMe = useAuthStore((s) => s.fetchMe)
  const [secDialog, setSecDialog] = useState<SecDialog>('')

  // --- Edit own profile (name + username) ---
  const [editing, setEditing] = useState(false)
  const [pf, setPf] = useState({ name: '', username: '', currentPassword: '' })
  const [profileError, setProfileError] = useState('')
  const [profileSuccess, setProfileSuccess] = useState('')
  const [profileSaving, setProfileSaving] = useState(false)

  function startEdit() {
    setPf({ name: user?.name || '', username: user?.username || '', currentPassword: '' })
    setProfileError('')
    setProfileSuccess('')
    setEditing(true)
  }
  function cancelEdit() {
    setEditing(false)
    setProfileError('')
  }
  async function saveProfile(e: React.FormEvent) {
    e.preventDefault()
    setProfileError('')
    setProfileSuccess('')
    const chk = profileCheck(pf, user)
    if (chk.error) return setProfileError(chk.error)
    setProfileSaving(true)
    try {
      const me = await api.patch('/me', chk.payload)
      useAuthStore.setState({ user: me })
      setEditing(false)
      setProfileSuccess('Đã cập nhật thông tin tài khoản')
    } catch (err) {
      setProfileError((err as Error).message || 'Không cập nhật được thông tin')
    } finally {
      setProfileSaving(false)
    }
  }

  // --- Change primary password ---
  const [pw, setPw] = useState({ currentPassword: '', newPassword: '', confirmPassword: '' })
  const [pwError, setPwError] = useState('')
  const [pwSuccess, setPwSuccess] = useState('')
  const [pwBusy, setPwBusy] = useState(false)
  async function submitPassword(e: React.FormEvent) {
    e.preventDefault()
    setPwError('')
    setPwSuccess('')
    const problem = passwordCheck(pw)
    if (problem) return setPwError(problem)
    setPwBusy(true)
    try {
      await api.post('/me/password', { currentPassword: pw.currentPassword, newPassword: pw.newPassword })
      setPwSuccess('Đã đổi mật khẩu thành công')
      setPw({ currentPassword: '', newPassword: '', confirmPassword: '' })
    } catch (err) {
      setPwError((err as Error).message || 'Không đổi được mật khẩu')
    } finally {
      setPwBusy(false)
    }
  }

  // --- Second password ---
  const [sp, setSp] = useState({ currentPassword: '', secondPassword: '' })
  const [spError, setSpError] = useState('')
  const [spSuccess, setSpSuccess] = useState('')
  const [spBusy, setSpBusy] = useState(false)
  async function submitSecond(e: React.FormEvent) {
    e.preventDefault()
    setSpError('')
    setSpSuccess('')
    const problem = secondCheck(sp)
    if (problem) return setSpError(problem)
    setSpBusy(true)
    try {
      await api.post('/me/second-password', { currentPassword: sp.currentPassword, secondPassword: sp.secondPassword })
      setSpSuccess('Đã cập nhật mật khẩu lớp hai')
      setSp({ currentPassword: '', secondPassword: '' })
      await fetchMe()
    } catch (err) {
      setSpError((err as Error).message || 'Không cập nhật được mật khẩu lớp hai')
    } finally {
      setSpBusy(false)
    }
  }

  // --- Wipe password ---
  const [wp, setWp] = useState({ currentPassword: '', wipePassword: '' })
  const [wpError, setWpError] = useState('')
  const [wpSuccess, setWpSuccess] = useState('')
  const [wpBusy, setWpBusy] = useState(false)
  async function submitWipe(e: React.FormEvent) {
    e.preventDefault()
    setWpError('')
    setWpSuccess('')
    const problem = wipeCheck(wp)
    if (problem) return setWpError(problem)
    const verb = wipeVerb(user)
    if (!(await showConfirm({
      title: `Xác nhận ${verb} mật khẩu`,
      message: `Xác nhận ${verb} mật khẩu xoá dữ liệu? Nếu bạn đăng nhập bằng mật khẩu này, hệ thống sẽ hỏi xác nhận xoá toàn bộ dữ liệu.`,
      confirmText: 'Xác nhận',
    }))) return
    setWpBusy(true)
    try {
      await api.post('/me/wipe-password', { currentPassword: wp.currentPassword, wipePassword: wp.wipePassword })
      setWpSuccess(`Đã ${verb} mật khẩu xoá dữ liệu`)
      setWp({ currentPassword: '', wipePassword: '' })
      await fetchMe()
    } catch (err) {
      setWpError((err as Error).message || 'Không cập nhật được mật khẩu xoá dữ liệu')
    } finally {
      setWpBusy(false)
    }
  }

  // --- Customer codes ---
  const [codes, setCodes] = useState<any[]>([])
  const [codesLoading, setCodesLoading] = useState(true)
  const [codesError, setCodesError] = useState('')
  const [generating, setGenerating] = useState(false)
  // Admin's per-account cap on Mã ID (settings.max_virtual_ids) and the form for picking your own digits and a label.
  const [maxCodes, setMaxCodes] = useState(5)
  const [newCode, setNewCode] = useState('')
  const [newLabel, setNewLabel] = useState('')
  const [editingLabelId, setEditingLabelId] = useState<string | null>(null)
  const [labelDraft, setLabelDraft] = useState('')
  const limit = atCodeLimit(codes, maxCodes)

  async function loadCodes() {
    setCodesLoading(true)
    setCodesError('')
    try {
      const res = await api.get('/me/customer-codes')
      setCodes(res.codes)
      if (res.maxCodes) setMaxCodes(res.maxCodes)
    } catch (err) {
      setCodesError((err as Error).message || 'Không tải được danh sách mã ID')
    } finally {
      setCodesLoading(false)
    }
  }
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadCodes()
  }, [])

  async function generateCode(e: React.FormEvent) {
    e.preventDefault()
    setGenerating(true)
    setCodesError('')
    try {
      const code = await api.post('/me/customer-codes', newCodePayload(newCode, newLabel))
      setCodes((c) => [code, ...c])
      setNewCode('')
      setNewLabel('')
    } catch (err) {
      setCodesError((err as Error).message || 'Không tạo được mã ID')
    } finally {
      setGenerating(false)
    }
  }
  async function deleteCode(code: any) {
    if (!(await showConfirm({
      title: 'Xoá mã ID',
      message: `Xoá mã ID "${code.code}"? Người khác sẽ không thể dùng mã này để kết bạn với bạn nữa.`,
      confirmText: 'Xoá',
      danger: true,
    }))) return
    try {
      await api.del(`/me/customer-codes/${code.id}`)
      setCodes((c) => c.filter((x) => x.id !== code.id))
    } catch (err) {
      alert((err as Error).message || 'Không xoá được mã ID')
    }
  }
  function editLabel(code: any) {
    setEditingLabelId(code.id)
    setLabelDraft(code.label || '')
  }
  async function saveLabel(e: React.FormEvent, code: any) {
    e.preventDefault()
    try {
      const res = await api.patch(`/me/customer-codes/${code.id}`, { label: labelDraft })
      setCodes((c) => c.map((x) => (x.id === code.id ? { ...x, label: res.label } : x)))
      setEditingLabelId(null)
    } catch (err) {
      setCodesError((err as Error).message || 'Không đổi được nhãn')
    }
  }
  async function copyCode(code: string) {
    try {
      await navigator.clipboard.writeText(code)
    } catch {
      /* clipboard unavailable - user can still select the text manually */
    }
  }

  const close = () => setSecDialog('')
  return (
    <>
      <div className="acct-top">
        <div className="card">
          <div className="acct-card-head">
            <h3 className="acct-h3">Thông tin cá nhân</h3>
            {!editing && <AppButton variant="secondary" size="sm" onClick={startEdit}>Sửa</AppButton>}
          </div>
          <Ok text={profileSuccess} />
          {editing ? (
            <form className="acct-profile-form" onSubmit={saveProfile}>
              <Err text={profileError} />
              <div className="field">
                <label htmlFor="profile-name">Tên</label>
                <div className="input-wrap"><input id="profile-name" value={pf.name} onChange={(e) => setPf({ ...pf, name: e.target.value })} type="text" autoComplete="name" /></div>
              </div>
              <div className="field">
                <label htmlFor="profile-username">Tên đăng nhập</label>
                <div className="input-wrap"><input id="profile-username" value={pf.username} onChange={(e) => setPf({ ...pf, username: e.target.value })} type="text" autoComplete="username" /></div>
              </div>
              {usernameChanged(pf, user) && (
                <div className="field">
                  <label htmlFor="profile-current-password">Mật khẩu hiện tại</label>
                  <div className="input-wrap">
                    <input id="profile-current-password" value={pf.currentPassword} onChange={(e) => setPf({ ...pf, currentPassword: e.target.value })} type="password" autoComplete="current-password" />
                  </div>
                </div>
              )}
              <div className="acct-profile-actions">
                <AppButton variant="primary" size="sm" type="submit" disabled={profileSaving}>{profileSaving ? 'Đang lưu...' : 'Lưu'}</AppButton>
                <AppButton variant="ghost" size="sm" disabled={profileSaving} onClick={cancelEdit}>Huỷ</AppButton>
              </div>
            </form>
          ) : (
            <>
              <div className="acct-row"><span>Tên</span><strong>{user?.name}</strong></div>
              <div className="acct-row"><span>Tên đăng nhập</span><strong>{user?.username}</strong></div>
            </>
          )}
          {!isAdmin && user?.package && (
            <>
              <div className="acct-row">
                <span>Gói dịch vụ</span>
                <span className="acct-pkg-value">
                  <strong>{user.package.label}</strong>
                  <span className={`chip ${user.package.isActive ? 'chip-accent' : 'chip-danger'}`}>{user.package.isActive ? 'Đang hoạt động' : 'Hết hạn'}</span>
                </span>
              </div>
              <div className="acct-row">
                <span>Hạn mức nhập</span>
                {user.stats?.total >= 999999999 ? (
                  <strong>Không giới hạn số lượng nhập</strong>
                ) : user.stats ? (
                  <strong>Đã dùng {user.stats.used} / {user.stats.total}</strong>
                ) : null}
              </div>
              <div className="acct-row">
                <span>Hết hạn</span>
                <strong>{user.package.expiresAt ? new Date(user.package.expiresAt).toLocaleDateString('vi-VN') : '-'}</strong>
              </div>
            </>
          )}
          <div className="acct-row">
            <span>Mật khẩu lớp hai</span>
            <span className={`chip${user?.hasSecondPassword ? ' chip-accent' : ''}`}>{user?.hasSecondPassword ? 'Đã bật' : 'Chưa đặt'}</span>
          </div>
          <div className="acct-row">
            <span>Mật khẩu xoá dữ liệu</span>
            <span className={`chip${user?.hasWipePassword ? ' chip-accent' : ''}`}>{user?.hasWipePassword ? 'Đã bật' : 'Chưa đặt'}</span>
          </div>
          <div className="acct-actions" role="group" aria-label="Mật khẩu">
            <AppButton variant="secondary" size="sm" onClick={() => setSecDialog('password')}>Đổi mật khẩu</AppButton>
            <AppButton variant="secondary" size="sm" onClick={() => setSecDialog('second')}>{user?.hasSecondPassword ? 'Đổi mật khẩu lớp hai' : 'Đặt mật khẩu lớp hai'}</AppButton>
            <AppButton variant="secondary" size="sm" onClick={() => setSecDialog('wipe')}>{user?.hasWipePassword ? 'Đổi mật khẩu xoá dữ liệu' : 'Đặt mật khẩu xoá dữ liệu'}</AppButton>
          </div>
          <button type="button" className="btn btn-secondary acct-logout" onClick={onLogout}>
            <AppIcon name="log-out" /> Đăng xuất
          </button>
        </div>

        {/* Customer codes */}
        <div className="card">
          <h3 className="acct-h3">Mã ID kết bạn</h3>
          <p className="page-subtitle acct-sub">
            Tạo mã và gửi cho người khác để họ kết bạn với bạn. Bạn có thể tự chọn dãy số (6-12 chữ số, không trùng,
            không quá dễ đoán như 123456) hoặc để trống để hệ thống tạo ngẫu nhiên. Tối đa {maxCodes} mã
            ({codes.length}/{maxCodes} đã dùng).
          </p>
          <Err text={codesError} />
          <form className="acct-code-form" onSubmit={generateCode}>
            <input value={newCode} onChange={(e) => setNewCode(e.target.value)} type="text" inputMode="numeric" maxLength={12} placeholder="Dãy số (tuỳ chọn)" aria-label="Dãy số mong muốn" />
            <input value={newLabel} onChange={(e) => setNewLabel(e.target.value)} type="text" maxLength={40} placeholder="Nhãn (tuỳ chọn)" aria-label="Nhãn" />
            <AppButton variant="secondary" type="submit" disabled={generating || limit}>{generating ? 'Đang tạo...' : '+ Tạo mã mới'}</AppButton>
          </form>
          {limit && <div className="page-subtitle" style={{ margin: '8px 0 0' }}>Đã đạt giới hạn, hãy xoá bớt một mã để tạo mã mới.</div>}
          {codesLoading ? (
            <div style={{ marginTop: 12 }}>Đang tải...</div>
          ) : codes.length === 0 ? (
            <div className="page-subtitle" style={{ marginTop: 12, marginBottom: 0 }}>Chưa có mã nào.</div>
          ) : (
            <div className="acct-code-list">
              {codes.map((c) => (
                <div key={c.id} className="acct-code-item">
                  <div className="acct-code-main">
                    <code className="acct-code-value">{c.code}</code>
                    {c.label && <span className="acct-code-label">{c.label}</span>}
                  </div>
                  <div className="acct-code-actions">
                    <AppButton variant="ghost" size="sm" onClick={() => editLabel(c)}>Nhãn</AppButton>
                    <AppButton variant="ghost" size="sm" onClick={() => copyCode(c.code)}>Sao chép</AppButton>
                    <AppButton variant="ghost" size="sm" onClick={() => deleteCode(c)}>Xoá</AppButton>
                  </div>
                  {editingLabelId === c.id && (
                    <form className="acct-label-edit" onSubmit={(e) => saveLabel(e, c)} onKeyDown={(e) => e.key === 'Escape' && setEditingLabelId(null)}>
                      <input value={labelDraft} onChange={(e) => setLabelDraft(e.target.value)} autoFocus type="text" maxLength={40} placeholder="Nhãn (để trống để xoá)" aria-label="Nhãn cho mã ID này" />
                      <AppButton variant="primary" size="sm" type="submit">Lưu</AppButton>
                      <AppButton variant="ghost" size="sm" onClick={() => setEditingLabelId(null)}>Huỷ</AppButton>
                    </form>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      <ModalDialog open={secDialog === 'password'} title="Đổi mật khẩu đăng nhập" onClose={close}>
        <form className="acct-sec-form" onSubmit={submitPassword}>
          <Err text={pwError} />
          <Ok text={pwSuccess} />
          <div className="field">
            <label>Mật khẩu hiện tại</label>
            <div className="input-wrap"><input value={pw.currentPassword} onChange={(e) => setPw({ ...pw, currentPassword: e.target.value })} type="password" /></div>
          </div>
          <div className="field">
            <label>Mật khẩu mới</label>
            <div className="input-wrap"><input value={pw.newPassword} onChange={(e) => setPw({ ...pw, newPassword: e.target.value })} type="password" /></div>
          </div>
          <div className="field">
            <label>Nhập lại mật khẩu mới</label>
            <div className="input-wrap"><input value={pw.confirmPassword} onChange={(e) => setPw({ ...pw, confirmPassword: e.target.value })} type="password" /></div>
          </div>
          <button type="submit" className="btn btn-primary acct-sec-submit" disabled={pwBusy}>{pwBusy ? 'Đang lưu...' : 'Đổi mật khẩu'}</button>
        </form>
      </ModalDialog>
      <ModalDialog open={secDialog === 'second'} title="Mật khẩu lớp hai" onClose={close}>
        <form className="acct-sec-form" onSubmit={submitSecond}>
          <p className="page-subtitle acct-sub">Lớp bảo mật thứ hai khi đăng nhập. {user?.hasSecondPassword ? 'Chỉ có thể đổi, không thể tắt.' : ''}</p>
          <Err text={spError} />
          <Ok text={spSuccess} />
          <div className="field">
            <label>Mật khẩu hiện tại</label>
            <div className="input-wrap"><input value={sp.currentPassword} onChange={(e) => setSp({ ...sp, currentPassword: e.target.value })} type="password" /></div>
          </div>
          <div className="field">
            <label>Mật khẩu lớp hai mới</label>
            <div className="input-wrap"><input value={sp.secondPassword} onChange={(e) => setSp({ ...sp, secondPassword: e.target.value })} type="password" /></div>
          </div>
          <button type="submit" className="btn btn-secondary acct-sec-submit" disabled={spBusy}>
            {spBusy ? 'Đang lưu...' : user?.hasSecondPassword ? 'Đổi mật khẩu lớp hai' : 'Đặt mật khẩu lớp hai'}
          </button>
        </form>
      </ModalDialog>
      <ModalDialog open={secDialog === 'wipe'} title="Mật khẩu xoá dữ liệu" onClose={close}>
        <form className="acct-sec-form" onSubmit={submitWipe}>
          <p className="page-subtitle acct-sub">
            Nếu bạn đăng nhập bằng mật khẩu này thay vì mật khẩu chính, hệ thống sẽ hỏi xác nhận xoá dữ liệu (số liệu, khách hàng, mẫu cú pháp, lịch xoá, nhật ký cuộc gọi, tin nhắn phản hồi Admin, lịch sử giao dịch; giữ lại tài khoản, bạn bè và tin nhắn bạn bè) thay vì đăng nhập bình thường. Mật khẩu này phải khác mật khẩu lớp hai. {user?.hasWipePassword ? 'Chỉ có thể đổi, không thể tắt.' : 'Tuỳ chọn, bỏ trống nếu không cần.'}
          </p>
          <Err text={wpError} />
          <Ok text={wpSuccess} />
          <div className="field">
            <label>Mật khẩu hiện tại</label>
            <div className="input-wrap"><input value={wp.currentPassword} onChange={(e) => setWp({ ...wp, currentPassword: e.target.value })} type="password" /></div>
          </div>
          <div className="field">
            <label>Mật khẩu xoá dữ liệu</label>
            <div className="input-wrap"><input value={wp.wipePassword} onChange={(e) => setWp({ ...wp, wipePassword: e.target.value })} type="password" /></div>
          </div>
          <button type="submit" className="btn btn-secondary acct-sec-submit" disabled={wpBusy}>
            {wpBusy ? 'Đang lưu...' : user?.hasWipePassword ? 'Đổi mật khẩu xoá dữ liệu' : 'Đặt mật khẩu xoá dữ liệu'}
          </button>
        </form>
      </ModalDialog>
    </>
  )
}
