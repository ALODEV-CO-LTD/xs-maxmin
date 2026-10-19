'use client'
import './NoticesView.css'
import { useCallback, useEffect, useState } from 'react'
import AppButton from '@/components/AppButton'
import AppSelect from '@/components/AppSelect'
import { api } from '@/lib/api'
import { showConfirm } from '@/lib/confirm'
import { useAuthStore } from '@/lib/authStore'
import { errMsg, fmtDateTime } from './common'
import { KINDS, buildTabs, kindLabel, nextTabKey, resolveTab } from './noticesLogic'

interface Announcement {
  id: string
  kind: string
  title: string
  body?: string
  active: boolean
  createdAt: string
}

// /admin/notices - broadcast notices + maintenance mode. API: GET/POST /admin/announcements,
// PATCH/DELETE /admin/announcements/:id, GET/PUT /admin/maintenance
export default function NoticesView() {
  // Two separate rights: each section is shown only to who holds it.
  const canMaintenance = useAuthStore((s) => s.can('maintenance.manage'))
  const canAnnounce = useAuthStore((s) => s.can('announcements.manage'))

  const [tab, setTab] = useState<string | undefined>(undefined)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [maintenanceOn, setMaintenanceOn] = useState(false)
  const [maintenanceMessage, setMaintenanceMessage] = useState('')
  const [maintenanceSaving, setMaintenanceSaving] = useState(false)
  const [maintenanceSaved, setMaintenanceSaved] = useState(false)
  const [list, setList] = useState<Announcement[]>([])
  const [form, setForm] = useState({ kind: 'info', title: '', body: '' })
  const [posting, setPosting] = useState(false)

  const tabs = buildTabs({ canAnnounce, canMaintenance, sentCount: list.length })
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
    document.getElementById(`notice-tab-${key}`)?.focus()
  }

  const load = useCallback(async () => {
    setLoading(true)
    setError('')
    try {
      const [mt, ann] = await Promise.all([
        canMaintenance ? api.get('/admin/maintenance') : Promise.resolve({}),
        canAnnounce ? api.get('/admin/announcements') : Promise.resolve({ announcements: [] }),
      ])
      setMaintenanceOn(mt.enabled === true)
      setMaintenanceMessage(mt.message || '')
      setList(ann.announcements)
    } catch (err) {
      setError(errMsg(err, 'Không tải được dữ liệu'))
    } finally {
      setLoading(false)
    }
  }, [canAnnounce, canMaintenance])
  useEffect(() => {
    load()
  }, [load])

  async function saveMaintenance() {
    setMaintenanceSaving(true)
    setMaintenanceSaved(false)
    setError('')
    try {
      await api.put('/admin/maintenance', { enabled: maintenanceOn, message: maintenanceMessage.trim() })
      setMaintenanceSaved(true)
    } catch (err) {
      setError(errMsg(err, 'Không lưu được'))
    } finally {
      setMaintenanceSaving(false)
    }
  }

  async function post(e: React.FormEvent) {
    e.preventDefault()
    if (!form.title.trim()) return
    if (!(await showConfirm({ title: 'Gửi thông báo', message: `Gửi "${form.title.trim()}" tới tất cả người dùng?`, confirmText: 'Gửi' }))) return
    setPosting(true)
    setError('')
    try {
      const created = await api.post('/admin/announcements', { kind: form.kind, title: form.title.trim(), body: form.body.trim() })
      setList((l) => [created, ...l])
      setForm({ kind: form.kind, title: '', body: '' })
    } catch (err) {
      setError(errMsg(err, 'Không gửi được thông báo'))
    } finally {
      setPosting(false)
    }
  }

  async function toggle(a: Announcement) {
    try {
      const updated = await api.patch(`/admin/announcements/${a.id}`, { active: !a.active })
      setList((l) => l.map((x) => (x.id === a.id ? { ...x, active: updated.active } : x)))
    } catch (err) {
      setError(errMsg(err, 'Không cập nhật được'))
    }
  }

  async function remove(a: Announcement) {
    if (!(await showConfirm({ title: 'Xoá thông báo', message: `Xoá thông báo "${a.title}"?`, confirmText: 'Xoá', danger: true }))) return
    try {
      await api.del(`/admin/announcements/${a.id}`)
      setList((l) => l.filter((x) => x.id !== a.id))
    } catch (err) {
      setError(errMsg(err, 'Không xoá được'))
    }
  }

  return (
    <div className="adm-notices">
      <div className="page">
        <h1 className="page-title">Thông báo & bảo trì</h1>
        <p className="page-subtitle">Thông báo hiển thị dạng banner cho mọi người dùng đang đăng nhập.</p>

        {error && <div className="alert alert-error">{error}</div>}
        {loading ? (
          <div className="card">Đang tải...</div>
        ) : (
          <>
            <div className="notice-tabs" role="tablist" aria-label="Thông báo và bảo trì" onKeyDown={onTabKey}>
              {tabs.map((t) => (
                <button key={t.key} id={`notice-tab-${t.key}`} type="button" role="tab" className={`notice-tab${activeTab === t.key ? ' active' : ''}`} aria-selected={activeTab === t.key} tabIndex={activeTab === t.key ? 0 : -1} onClick={() => selectTab(t.key)}>
                  {t.label}
                </button>
              ))}
            </div>

            {canMaintenance && (
              <section className="card block" hidden={activeTab !== 'maintenance'}>
                <h3 className="block-title">Chế độ bảo trì</h3>
                <label className="check-row">
                  <input checked={maintenanceOn} onChange={(e) => setMaintenanceOn(e.target.checked)} type="checkbox" />
                  <span>Đang bảo trì (hiện banner cảnh báo cho mọi người dùng)</span>
                </label>
                <div className="field">
                  <label htmlFor="mt-msg">Nội dung hiển thị</label>
                  <div className="input-wrap">
                    <textarea id="mt-msg" value={maintenanceMessage} onChange={(e) => setMaintenanceMessage(e.target.value)} rows={2} placeholder="Vd: Hệ thống bảo trì từ 23:00 đến 24:00" />
                  </div>
                </div>
                {maintenanceSaved && <div className="alert alert-success">Đã lưu.</div>}
                <AppButton variant="primary" disabled={maintenanceSaving} onClick={saveMaintenance}>
                  {maintenanceSaving ? 'Đang lưu...' : 'Lưu cấu hình bảo trì'}
                </AppButton>
              </section>
            )}

            {canAnnounce && (
              <section className="card block" hidden={activeTab !== 'compose'}>
                <h3 className="block-title">Gửi thông báo mới</h3>
                <form onSubmit={post}>
                  <div className="field">
                    <label htmlFor="an-kind">Loại</label>
                    <AppSelect id="an-kind" value={form.kind} onChange={(v: string) => setForm({ ...form, kind: v })}>
                      {KINDS.map((k) => (
                        <option key={k.value} value={k.value}>{k.label}</option>
                      ))}
                    </AppSelect>
                  </div>
                  <div className="field">
                    <label htmlFor="an-title">Tiêu đề</label>
                    <div className="input-wrap"><input id="an-title" value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} type="text" maxLength={200} /></div>
                  </div>
                  <div className="field">
                    <label htmlFor="an-body">Nội dung (tuỳ chọn)</label>
                    <div className="input-wrap"><textarea id="an-body" value={form.body} onChange={(e) => setForm({ ...form, body: e.target.value })} rows={3} maxLength={2000} /></div>
                  </div>
                  <AppButton variant="primary" type="submit" disabled={posting || !form.title.trim()}>{posting ? 'Đang gửi...' : 'Gửi thông báo'}</AppButton>
                </form>
              </section>
            )}

            {canAnnounce && (
              <section className="card block" hidden={activeTab !== 'sent'}>
                <h3 className="block-title">Thông báo đã gửi</h3>
                {list.length === 0 ? (
                  <p className="empty">Chưa có thông báo nào.</p>
                ) : (
                  <ul className="ann-list">
                    {list.map((a) => (
                      <li key={a.id} className="ann-item">
                        <div className="ann-main">
                          <div>
                            <span className="chip">{kindLabel(a.kind)}</span>
                            {!a.active && <span className="chip">Đã ẩn</span>}
                            <strong className="ann-title">{a.title}</strong>
                          </div>
                          {a.body && <div className="ann-body">{a.body}</div>}
                          <div className="ann-date">{fmtDateTime(a.createdAt)}</div>
                        </div>
                        <div className="ann-actions">
                          <AppButton variant="secondary" size="sm" onClick={() => toggle(a)}>{a.active ? 'Ẩn' : 'Hiện lại'}</AppButton>
                          <AppButton variant="danger" size="sm" onClick={() => remove(a)}>Xoá</AppButton>
                        </div>
                      </li>
                    ))}
                  </ul>
                )}
              </section>
            )}
          </>
        )}
      </div>
    </div>
  )
}
