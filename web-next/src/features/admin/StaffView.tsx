'use client'
import './StaffView.css'
import { useCallback, useEffect, useState } from 'react'
import AppButton from '@/components/AppButton'
import { api } from '@/lib/api'
import { showConfirm } from '@/lib/confirm'
import { useAuthStore } from '@/lib/authStore'
import { errMsg } from './common'
import { PRESETS, canSavePerms, togglePerm } from './staffLogic'

interface StaffRow {
  id: string
  name: string
  username: string
  locked?: boolean
  permissions: string[]
}
interface Edit {
  permissions: string[]
  newPassword: string
}

function PermGrid({ catalog, value, onToggle }: { catalog: Record<string, string>; value: string[]; onToggle: (k: string) => void }) {
  return (
    <div className="perms">
      {Object.entries(catalog).map(([key, label]) => (
        <label key={key} className="perm">
          <input type="checkbox" checked={value.includes(key)} onChange={() => onToggle(key)} />
          <span>{label}</span>
        </label>
      ))}
    </div>
  )
}

// /admin/staff - multi-level Admin, root Admin only. API: GET/POST /admin/staff, PATCH/DELETE /admin/staff/:id
export default function StaffView() {
  const isRoot = useAuthStore((s) => !!s.user?.isRoot)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [catalog, setCatalog] = useState<Record<string, string>>({})
  const [staff, setStaff] = useState<StaffRow[]>([])
  const [form, setForm] = useState({ name: '', username: '', password: '', permissions: [] as string[] })
  const [creating, setCreating] = useState(false)
  const [showForm, setShowForm] = useState(false)
  const [formError, setFormError] = useState('')
  const [edits, setEdits] = useState<Record<string, Edit>>({})
  const [editing, setEditing] = useState('')
  const [busyId, setBusyId] = useState('')

  const load = useCallback(async () => {
    setError('')
    try {
      const res = await api.get('/admin/staff')
      setCatalog(res.permissions)
      setStaff(res.staff)
      setEdits(Object.fromEntries(res.staff.map((s: StaffRow) => [s.id, { permissions: [...s.permissions], newPassword: '' }])))
    } catch (err) {
      setError(errMsg(err, 'Không tải được danh sách tài khoản thứ cấp'))
    } finally {
      setLoading(false)
    }
  }, [])
  useEffect(() => {
    load()
  }, [load])

  const setEdit = (id: string, patch: Partial<Edit>) => setEdits((e) => ({ ...e, [id]: { ...e[id], ...patch } }))

  async function create(e: React.FormEvent) {
    e.preventDefault()
    setFormError('')
    setCreating(true)
    try {
      await api.post('/admin/staff', { ...form, permissions: [...form.permissions] })
      setForm({ name: '', username: '', password: '', permissions: [] })
      setShowForm(false)
      setNotice('Đã tạo tài khoản. Hãy gửi tên đăng nhập và mật khẩu cho nhân viên qua kênh riêng.')
      await load()
    } catch (err) {
      setFormError(errMsg(err, 'Không tạo được tài khoản'))
    } finally {
      setCreating(false)
    }
  }

  async function patch(s: StaffRow, body: object, okText: string) {
    setBusyId(s.id)
    setError('')
    setNotice('')
    try {
      await api.patch(`/admin/staff/${s.id}`, body)
      setNotice(okText)
      setEditing('')
      await load()
    } catch (err) {
      setError(errMsg(err, 'Không lưu được thay đổi'))
    } finally {
      setBusyId('')
    }
  }

  async function remove(s: StaffRow) {
    if (!(await showConfirm({ title: 'Xoá tài khoản thứ cấp', message: `Xoá tài khoản "${s.username}"? Nhân viên sẽ không đăng nhập được nữa.`, confirmText: 'Xoá', danger: true }))) return
    setBusyId(s.id)
    try {
      await api.del(`/admin/staff/${s.id}`)
      setNotice(`Đã xoá ${s.username}`)
      await load()
    } catch (err) {
      setError(errMsg(err, 'Không xoá được'))
    } finally {
      setBusyId('')
    }
  }

  const reset = (s: StaffRow) => setEdit(s.id, { permissions: [...s.permissions], newPassword: '' })

  if (!isRoot) {
    return (
      <div className="adm-staff">
        <div className="page">
          <h1 className="page-title">Phân quyền Admin</h1>
          <div className="alert alert-error">Chỉ Admin gốc được quản lý phân quyền.</div>
        </div>
      </div>
    )
  }

  return (
    <div className="adm-staff">
      <div className="page">
        <h1 className="page-title">Phân quyền Admin</h1>
        <p className="page-subtitle">
          Tạo tài khoản thứ cấp cho nhân viên và tích chọn những quyền của Admin mà họ được dùng. Chỉ Admin gốc quản lý được phần này; quyền thay đổi có hiệu lực ngay ở lần thao tác kế tiếp của nhân viên.
        </p>

        {error && <div className="alert alert-error">{error}</div>}
        {notice && <div className="alert alert-success">{notice}</div>}
        {loading ? (
          <div className="card">Đang tải...</div>
        ) : (
          <>
            <div className="bar">
              <h2 className="bar-title">
                Tài khoản thứ cấp <span className="count">{staff.length}</span>
              </h2>
              <AppButton variant="primary" onClick={() => setShowForm(!showForm)}>
                {showForm ? 'Đóng' : '+ Tạo tài khoản'}
              </AppButton>
            </div>

            {showForm && (
              <form className="card block" onSubmit={create}>
                {formError && <div className="alert alert-error">{formError}</div>}
                <div className="grid">
                  <label>Tên hiển thị<input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} type="text" required /></label>
                  <label>Tên đăng nhập<input value={form.username} onChange={(e) => setForm({ ...form, username: e.target.value })} type="text" autoComplete="off" required /></label>
                  <label>Mật khẩu<input value={form.password} onChange={(e) => setForm({ ...form, password: e.target.value })} type="text" autoComplete="off" required /></label>
                </div>
                <div className="presets">
                  <span>Chọn nhanh:</span>
                  {PRESETS.map((p) => (
                    <button key={p.label} type="button" className="btn btn-secondary btn-sm" onClick={() => setForm({ ...form, permissions: [...p.keys] })}>{p.label}</button>
                  ))}
                  <AppButton variant="ghost" size="sm" onClick={() => setForm({ ...form, permissions: [] })}>Bỏ chọn</AppButton>
                </div>
                <PermGrid catalog={catalog} value={form.permissions} onToggle={(k) => setForm({ ...form, permissions: togglePerm(form.permissions, k) })} />
                <AppButton variant="primary" type="submit" disabled={creating}>{creating ? 'Đang tạo...' : 'Tạo tài khoản'}</AppButton>
              </form>
            )}

            {staff.length === 0 && !showForm && <div className="card">Chưa có tài khoản thứ cấp nào.</div>}

            {staff.map((s) => {
              const ed = edits[s.id] || { permissions: [], newPassword: '' }
              return (
                <div key={s.id} className="card block">
                  <div className="head">
                    <div>
                      <strong>{s.name}</strong> <span className="muted">({s.username})</span>
                      {s.locked && <span className="tag">Đang khoá</span>}
                    </div>
                    <div className="head-actions">
                      {editing !== s.id && <AppButton variant="primary" size="sm" disabled={busyId === s.id} onClick={() => { reset(s); setEditing(s.id) }}>Sửa</AppButton>}
                      <AppButton variant="secondary" size="sm" disabled={busyId === s.id} onClick={() => patch(s, { locked: !s.locked }, s.locked ? `Đã mở khoá ${s.name}` : `Đã khoá ${s.name} và đăng xuất mọi thiết bị`)}>{s.locked ? 'Mở khoá' : 'Khoá'}</AppButton>
                      <button type="button" className="btn btn-ghost btn-sm danger" disabled={busyId === s.id} onClick={() => remove(s)}>Xoá</button>
                    </div>
                  </div>

                  {editing !== s.id ? (
                    s.permissions.length ? (
                      <div className="chips">
                        {s.permissions.map((key) => (
                          <span key={key} className="chip">{catalog[key] || key}</span>
                        ))}
                      </div>
                    ) : (
                      <p className="muted">Chưa có quyền nào.</p>
                    )
                  ) : (
                    <>
                      <div className="presets">
                        <span>Chọn nhanh:</span>
                        {PRESETS.map((p) => (
                          <button key={p.label} type="button" className="btn btn-secondary btn-sm" onClick={() => setEdit(s.id, { permissions: [...p.keys] })}>{p.label}</button>
                        ))}
                      </div>
                      <PermGrid catalog={catalog} value={ed.permissions} onToggle={(k) => setEdit(s.id, { permissions: togglePerm(ed.permissions, k) })} />
                      <div className="row">
                        <AppButton variant="primary" size="sm" disabled={busyId === s.id || !canSavePerms(ed.permissions, s.permissions)} onClick={() => patch(s, { permissions: ed.permissions }, `Đã lưu quyền của ${s.name}`)}>Lưu quyền</AppButton>
                        <AppButton variant="ghost" size="sm" disabled={busyId === s.id} onClick={() => { reset(s); setEditing('') }}>Huỷ</AppButton>
                      </div>
                      <div className="row pw-row">
                        <input value={ed.newPassword} onChange={(e) => setEdit(s.id, { newPassword: e.target.value })} type="text" placeholder="Mật khẩu mới" autoComplete="off" />
                        <AppButton variant="secondary" size="sm" disabled={busyId === s.id || !ed.newPassword} onClick={() => patch(s, { newPassword: ed.newPassword }, `Đã đặt mật khẩu mới cho ${s.name} (đã đăng xuất mọi thiết bị)`)}>Đặt lại mật khẩu</AppButton>
                      </div>
                    </>
                  )}
                </div>
              )
            })}
          </>
        )}
      </div>
    </div>
  )
}
