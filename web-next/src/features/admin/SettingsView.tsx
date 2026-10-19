'use client'
import './SettingsView.css'
import { useCallback, useEffect, useState } from 'react'
import AppButton from '@/components/AppButton'
import AppSelect from '@/components/AppSelect'
import { api } from '@/lib/api'
import { showConfirm } from '@/lib/confirm'
import { useAuthStore } from '@/lib/authStore'
import AppVersionPanel from '@/features/account/AppVersionPanel'
import BackupsView from './BackupsView'
import SecurityPolicyView from './SecurityPolicyView'
import { errMsg, fmtDateTime } from './common'
import { nextTabKey, resolveTab } from './noticesLogic'
import { BANKS, EVENT_LABELS, bankFields, bankFormOf, bankPayload, formatDuration, formatVnd, maxIdsPayload, otherKeysOf, packageBody, packageInUse, settingsTabs } from './settingsLogic'

interface Pkg {
  type: string
  label: string
  durationDays: number
  priceVnd: number
  active: boolean
  usage: { users: number; requests: number; transactions: number }
}
interface SecEvent {
  id: string
  createdAt: string
  type: string
  username?: string
  ip?: string
  detail?: string
}
type PkgForm = { label: string; durationDays: string; priceVnd: string }
const EMPTY_PKG: PkgForm = { label: '', durationDays: '', priceVnd: '' }

function PkgFields({ f, set, placeholder }: { f: PkgForm; set: (f: PkgForm) => void; placeholder?: boolean }) {
  return (
    <div className="pkg-fields">
      <label>Tên gói<input value={f.label} onChange={(e) => set({ ...f, label: e.target.value })} type="text" maxLength={60} placeholder={placeholder ? 'Vd: 2 tháng' : undefined} required /></label>
      <label>Thời hạn (ngày)<input value={f.durationDays} onChange={(e) => set({ ...f, durationDays: e.target.value })} type="number" min={1} max={3650} required /></label>
      <label>Giá (đ)<input value={f.priceVnd} onChange={(e) => set({ ...f, priceVnd: e.target.value })} type="number" min={0} required /></label>
    </div>
  )
}

// /admin/settings - payment account, package catalog, ID cap, app version, security log / policy, backups.
// API: GET/PUT/DELETE /admin/settings, GET/POST/PATCH/DELETE /admin/packages, GET /admin/security-events
export default function SettingsView() {
  // A staff account may hold only some of these rights (A07).
  const canSettings = useAuthStore((s) => s.can('settings.manage'))
  const canSecurity = useAuthStore((s) => s.can('security.view'))
  const canPolicy = useAuthStore((s) => s.can('security.policy'))
  const canBackups = useAuthStore((s) => s.can('backups.manage'))

  const [loading, setLoading] = useState(canSettings)
  const [error, setError] = useState('')
  const [raw, setRaw] = useState<Record<string, string>>({})
  const [bank, setBank] = useState({ bank_bin: '', bank_account_number: '', bank_account_holder: '' })
  const [editBank, setEditBank] = useState(false)
  const [editMax, setEditMax] = useState(false)
  const [bankSaving, setBankSaving] = useState(false)
  const [bankSaved, setBankSaved] = useState(false)
  const [bankError, setBankError] = useState('')
  const [maxIds, setMaxIds] = useState('')
  const [maxIdsSaving, setMaxIdsSaving] = useState(false)
  const [maxIdsSaved, setMaxIdsSaved] = useState(false)
  const [maxIdsError, setMaxIdsError] = useState('')
  const [packages, setPackages] = useState<Pkg[]>([])
  const [pkgError, setPkgError] = useState('')
  const [pkgNotice, setPkgNotice] = useState('')
  const [pkgBusy, setPkgBusy] = useState('')
  const [pkgEditing, setPkgEditing] = useState('') // code being edited, or 'new'
  const [pkgForm, setPkgForm] = useState<PkgForm>(EMPTY_PKG)
  const [events, setEvents] = useState<SecEvent[]>([])
  const [eventsError, setEventsError] = useState('')
  const [tab, setTab] = useState<string | undefined>(undefined)

  const otherKeys = otherKeysOf(raw)
  const tabs = settingsTabs({ canSettings, canSecurity, canPolicy, canBackups, hasOther: otherKeys.length > 0 })
  const activeTab = resolveTab(tabs, tab)

  useEffect(() => {
    setTab(new URLSearchParams(window.location.search).get('tab') ?? undefined)
  }, [])
  const selectTab = (key: string) => {
    setTab(key)
    const q = new URLSearchParams(window.location.search)
    q.set('tab', key)
    window.history.replaceState(null, '', `${window.location.pathname}?${q}`)
  }
  const onTabKey = (e: React.KeyboardEvent) => {
    const key = nextTabKey(tabs, activeTab ?? '', e.key)
    if (!key) return
    e.preventDefault()
    selectTab(key)
    document.getElementById(`set-tab-${key}`)?.focus()
  }

  const applySettings = (r: Record<string, string>) => {
    setRaw(r)
    setMaxIds(r.max_virtual_ids ?? '')
    setBank(bankFormOf(r))
  }
  const loadPackages = useCallback(async () => {
    setPkgError('')
    try {
      setPackages((await api.get('/admin/packages')).packages)
    } catch (err) {
      setPkgError(errMsg(err, 'Không tải được danh sách gói'))
    }
  }, [])

  useEffect(() => {
    if (!canSettings) return
    api
      .get('/admin/settings')
      .then(applySettings)
      .catch((err) => setError(errMsg(err, 'Không thể tải cài đặt')))
      .finally(() => setLoading(false))
    loadPackages()
  }, [canSettings, loadPackages])
  useEffect(() => {
    if (!canSecurity) return
    api
      .get('/admin/security-events?limit=50')
      .then((res) => setEvents(res.events || []))
      .catch((err) => setEventsError(errMsg(err, 'Không thể tải nhật ký bảo mật')))
  }, [canSecurity])

  async function saveBank(e: React.FormEvent) {
    e.preventDefault()
    setBankSaved(false)
    setBankError('')
    const p = bankPayload(bank)
    if (p.error) return setBankError(p.error)
    setBankSaving(true)
    try {
      applySettings(await api.put('/admin/settings', p.body))
      setBankSaved(true)
      setEditBank(false)
    } catch (err) {
      setBankError(errMsg(err, 'Không thể lưu cấu hình thanh toán'))
    } finally {
      setBankSaving(false)
    }
  }
  const cancelBank = () => {
    setBank(bankFormOf(raw))
    setBankError('')
    setEditBank(false)
  }

  async function saveMaxIds(e: React.FormEvent) {
    e.preventDefault()
    setMaxIdsSaving(true)
    setMaxIdsSaved(false)
    setMaxIdsError('')
    try {
      applySettings(await api.put('/admin/settings', maxIdsPayload(maxIds)))
      setMaxIdsSaved(true)
      setEditMax(false)
    } catch (err) {
      setMaxIdsError(errMsg(err, 'Không thể lưu giới hạn ID ảo'))
    } finally {
      setMaxIdsSaving(false)
    }
  }
  const cancelMax = () => {
    setMaxIds(raw.max_virtual_ids ?? '')
    setMaxIdsError('')
    setEditMax(false)
  }

  async function savePackage(e: React.FormEvent) {
    e.preventDefault()
    const editing = pkgEditing
    setPkgBusy(editing)
    setPkgError('')
    try {
      if (editing === 'new') await api.post('/admin/packages', packageBody(pkgForm))
      else await api.patch(`/admin/packages/${editing}`, packageBody(pkgForm))
      setPkgNotice(editing === 'new' ? 'Đã thêm gói' : 'Đã lưu gói (giá mới chỉ áp dụng cho yêu cầu mua sau này)')
      setPkgEditing('')
      await loadPackages()
    } catch (err) {
      setPkgError(errMsg(err, 'Không lưu được gói'))
    } finally {
      setPkgBusy('')
    }
  }
  async function togglePackage(p: Pkg) {
    setPkgBusy(p.type)
    setPkgError('')
    try {
      await api.patch(`/admin/packages/${p.type}`, { active: !p.active })
      setPkgNotice(p.active ? `Đã ẩn gói ${p.label} (người dùng không còn thấy để mua)` : `Đã hiện lại gói ${p.label}`)
      await loadPackages()
    } catch (err) {
      setPkgError(errMsg(err, 'Không cập nhật được gói'))
    } finally {
      setPkgBusy('')
    }
  }
  async function removePackage(p: Pkg) {
    if (packageInUse(p)) {
      setPkgError(`Gói "${p.label}" đã có tài khoản hoặc giao dịch sử dụng nên không xoá được. Hãy ẩn gói để ngừng bán.`)
      return
    }
    if (!(await showConfirm({ title: 'Xoá gói', message: `Xoá gói "${p.label}"?`, confirmText: 'Xoá', danger: true }))) return
    setPkgBusy(p.type)
    setPkgError('')
    try {
      await api.del(`/admin/packages/${p.type}`)
      setPkgNotice(`Đã xoá gói ${p.label}`)
      await loadPackages()
    } catch (err) {
      setPkgError(errMsg(err, 'Không xoá được gói'))
    } finally {
      setPkgBusy('')
    }
  }

  return (
    <div className="adm-settings">
      <div className="page">
        <h1 className="page-title">Cài đặt hệ thống</h1>
        <p className="page-subtitle">Thanh toán, giá gói, giới hạn tài khoản, nhật ký và chính sách bảo mật, sao lưu</p>

        {error && <div className="alert alert-error">{error}</div>}
        {loading && <div>Đang tải...</div>}

        {!loading && tabs.length > 0 && (
          <div className="set-tabs" role="tablist" aria-label="Mục cài đặt" onKeyDown={onTabKey}>
            {tabs.map((t) => (
              <button key={t.key} id={`set-tab-${t.key}`} type="button" role="tab" className={`set-tab${activeTab === t.key ? ' active' : ''}`} aria-selected={activeTab === t.key} tabIndex={activeTab === t.key ? 0 : -1} onClick={() => selectTab(t.key)}>
                {t.label}
              </button>
            ))}
          </div>
        )}

        {!loading && canSettings && (
          <>
            <div hidden={activeTab !== 'payment'} role="tabpanel">
              <h2 style={{ marginTop: 0 }}>Tài khoản nhận thanh toán</h2>
              <p className="page-subtitle">Khách hàng sẽ thấy thông tin này (và mã QR chuyển khoản nhanh) ở trang Gói dịch vụ khi mua gói.</p>
              <form className="card" onSubmit={saveBank}>
                {bankError && <div className="alert alert-error">{bankError}</div>}
                {bankSaved && <div className="alert alert-success">Đã lưu cấu hình thanh toán</div>}
                <fieldset className="ro" disabled={!editBank}>
                  <div className="field">
                    <label>Ngân hàng</label>
                    <AppSelect value={bank.bank_bin} onChange={(v: string) => setBank({ ...bank, bank_bin: v })}>
                      <option value="" disabled>-- Chưa chọn ngân hàng --</option>
                      {BANKS.map((b) => (
                        <option key={b.bin} value={b.bin}>{b.name}</option>
                      ))}
                    </AppSelect>
                  </div>
                  {bankFields.map((f) => (
                    <div key={f.key} className="field">
                      <label>{f.label}</label>
                      <input value={bank[f.key as 'bank_account_number' | 'bank_account_holder']} onChange={(e) => setBank({ ...bank, [f.key]: e.target.value })} type="text" placeholder={f.label} />
                    </div>
                  ))}
                </fieldset>
                <div className="edit-actions">
                  {!editBank ? (
                    <AppButton variant="secondary" onClick={() => setEditBank(true)}>Sửa</AppButton>
                  ) : (
                    <>
                      <AppButton variant="ghost" disabled={bankSaving} onClick={cancelBank}>Huỷ</AppButton>
                      <AppButton variant="primary" type="submit" disabled={bankSaving}>{bankSaving ? 'Đang lưu...' : 'Lưu cấu hình thanh toán'}</AppButton>
                    </>
                  )}
                </div>
              </form>
            </div>

            <div hidden={activeTab !== 'limits'} role="tabpanel">
              <h2 style={{ marginTop: 0 }}>Giới hạn ID ảo</h2>
              <p className="page-subtitle">Số Mã ID (ID ảo) tối đa mỗi tài khoản khách hàng được tạo. Mặc định 5.</p>
              <form className="card" onSubmit={saveMaxIds}>
                {maxIdsError && <div className="alert alert-error">{maxIdsError}</div>}
                {maxIdsSaved && <div className="alert alert-success">Đã lưu giới hạn ID ảo</div>}
                <fieldset className="ro" disabled={!editMax}>
                  <div className="field">
                    <label>Số ID tối đa mỗi tài khoản (1-100)</label>
                    <input value={maxIds} onChange={(e) => setMaxIds(e.target.value)} type="number" min={1} max={100} placeholder="5" />
                  </div>
                </fieldset>
                <div className="edit-actions">
                  {!editMax ? (
                    <AppButton variant="secondary" onClick={() => setEditMax(true)}>Sửa</AppButton>
                  ) : (
                    <>
                      <AppButton variant="ghost" disabled={maxIdsSaving} onClick={cancelMax}>Huỷ</AppButton>
                      <AppButton variant="primary" type="submit" disabled={maxIdsSaving}>{maxIdsSaving ? 'Đang lưu...' : 'Lưu giới hạn'}</AppButton>
                    </>
                  )}
                </div>
              </form>
            </div>

            <div hidden={activeTab !== 'prices'} role="tabpanel">
              <h2 style={{ marginTop: 0 }}>Gói dịch vụ</h2>
              <p className="page-subtitle">Thêm, sửa, ẩn hoặc xoá các gói khách hàng có thể mua. Đổi giá chỉ áp dụng cho yêu cầu mua sau này.</p>
              {pkgError && <div className="alert alert-error">{pkgError}</div>}
              {pkgNotice && <div className="alert alert-success">{pkgNotice}</div>}

              <div className="pkg-bar">
                {pkgEditing !== 'new' && <AppButton variant="primary" size="sm" onClick={() => { setPkgForm(EMPTY_PKG); setPkgEditing('new'); setPkgNotice('') }}>+ Thêm gói</AppButton>}
              </div>

              {pkgEditing === 'new' && (
                <form className="card pkg-form" onSubmit={savePackage}>
                  <PkgFields f={pkgForm} set={setPkgForm} placeholder />
                  <div className="pkg-actions">
                    <AppButton variant="primary" size="sm" type="submit" disabled={pkgBusy === 'new'}>Thêm gói</AppButton>
                    <AppButton variant="ghost" size="sm" onClick={() => setPkgEditing('')}>Huỷ</AppButton>
                  </div>
                </form>
              )}

              {packages.length === 0 && pkgEditing !== 'new' && <div className="card">Chưa có gói nào.</div>}
              {packages.map((p) => (
                <div key={p.type} className="card pkg-card">
                  {pkgEditing !== p.type ? (
                    <div className="pkg-head">
                      <div>
                        <strong>{p.label}</strong>
                        {!p.active && <span className="chip">Đang ẩn</span>}
                        <div className="pkg-meta">{formatDuration(p.durationDays)} · {formatVnd(p.priceVnd)} · {p.usage.users} tài khoản đang dùng</div>
                      </div>
                      <div className="pkg-actions">
                        <AppButton variant="primary" size="sm" disabled={pkgBusy === p.type} onClick={() => { setPkgForm({ label: p.label, durationDays: String(p.durationDays), priceVnd: String(p.priceVnd) }); setPkgEditing(p.type); setPkgNotice('') }}>Sửa</AppButton>
                        <AppButton variant="secondary" size="sm" disabled={pkgBusy === p.type} onClick={() => togglePackage(p)}>{p.active ? 'Ẩn' : 'Hiện lại'}</AppButton>
                        <button type="button" className="btn btn-ghost btn-sm pkg-danger" disabled={pkgBusy === p.type} onClick={() => removePackage(p)}>Xoá</button>
                      </div>
                    </div>
                  ) : (
                    <form onSubmit={savePackage}>
                      <PkgFields f={pkgForm} set={setPkgForm} />
                      <div className="pkg-actions">
                        <AppButton variant="primary" size="sm" type="submit" disabled={pkgBusy === p.type}>Lưu</AppButton>
                        <AppButton variant="ghost" size="sm" onClick={() => setPkgEditing('')}>Huỷ</AppButton>
                      </div>
                    </form>
                  )}
                </div>
              ))}
            </div>
          </>
        )}

        {canSettings && activeTab === 'appversion' && (
          <div role="tabpanel">
            <AppVersionPanel />
          </div>
        )}
        {canPolicy && activeTab === 'policy' && (
          <div role="tabpanel">
            <SecurityPolicyView embedded />
          </div>
        )}
        {canBackups && activeTab === 'backups' && (
          <div role="tabpanel">
            <BackupsView embedded />
          </div>
        )}

        {canSecurity && activeTab === 'security' && (
          <>
            <h2 style={{ marginTop: 0 }}>Nhật ký bảo mật gần đây</h2>
            <p className="page-subtitle">Không ghi mật khẩu hay token.</p>
            {eventsError && <div className="alert alert-error">{eventsError}</div>}
            <div className="card" style={{ padding: 0 }}>
              {events.length === 0 ? (
                <div style={{ padding: 16 }}>Chưa có sự kiện nào.</div>
              ) : (
                <table className="table">
                  <thead>
                    <tr><th>Thời gian</th><th>Sự kiện</th><th>Tài khoản</th><th>IP</th><th>Chi tiết</th></tr>
                  </thead>
                  <tbody>
                    {events.map((e) => (
                      <tr key={e.id}>
                        <td>{fmtDateTime(e.createdAt)}</td>
                        <td>{EVENT_LABELS[e.type as keyof typeof EVENT_LABELS] || e.type}</td>
                        <td>{e.username || '-'}</td>
                        <td>{e.ip || '-'}</td>
                        <td>{e.detail || ''}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </div>
          </>
        )}

        {canSettings && !loading && otherKeys.length > 0 && activeTab === 'other' && (
          <>
            <h2 style={{ marginTop: 0 }}>Các khoá cài đặt khác</h2>
            <div className="card" style={{ padding: 0 }}>
              <table className="table">
                <thead>
                  <tr><th>Khoá</th><th>Giá trị</th></tr>
                </thead>
                <tbody>
                  {otherKeys.map((k) => (
                    <tr key={k}><td>{k}</td><td>{raw[k]}</td></tr>
                  ))}
                </tbody>
              </table>
            </div>
          </>
        )}
      </div>
    </div>
  )
}
