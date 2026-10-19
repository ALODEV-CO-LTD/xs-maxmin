'use client'
import './AppVersionPanel.css'
import { useEffect, useState } from 'react'
import AppButton from '@/components/AppButton'
import { api, ApiError } from '@/lib/api'
import { versionForm, versionProblem } from './accountLogic'

// Cài đặt > Phiên bản ứng dụng (A17): the newest version, the oldest version still allowed and the download link of the
// Android app. The app reads them from the public GET /api/app-version at start-up: below the newest it offers an
// update, below the minimum it blocks until updated. Shown read-only; "Sửa" unlocks the form (Huỷ / Lưu).
// API: GET/PUT /admin/app-version  { latestVersion, minVersion, downloadUrl, notes }
export default function AppVersionPanel() {
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [editing, setEditing] = useState(false)
  const [error, setError] = useState('')
  const [saved, setSaved] = useState(false)
  const [form, setForm] = useState(versionForm(null))
  const [stored, setStored] = useState(versionForm(null))
  const set = (patch: Partial<typeof form>) => setForm((f) => ({ ...f, ...patch }))
  const dirty = JSON.stringify(form) !== JSON.stringify(stored)

  function fill(res: unknown) {
    const v = versionForm(res as Record<string, string>)
    setStored(v)
    setForm(v)
  }

  useEffect(() => {
    let alive = true
    api.get('/admin/app-version')
      .then((res) => alive && fill(res))
      .catch((err) => alive && setError(err instanceof ApiError ? err.message : 'Không tải được cấu hình phiên bản'))
      .finally(() => alive && setLoading(false))
    return () => {
      alive = false
    }
  }, [])

  function cancel() {
    setForm(stored)
    setError('')
    setEditing(false)
  }

  async function save(e: React.FormEvent) {
    e.preventDefault()
    const problem = versionProblem(form)
    if (problem) return setError(problem)
    setSaving(true)
    setError('')
    setSaved(false)
    try {
      fill(await api.put('/admin/app-version', { ...form }))
      setSaved(true)
      setEditing(false)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Không lưu được')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div>
      <h2 style={{ marginTop: 0 }}>Phiên bản ứng dụng</h2>
      <p className="page-subtitle">
        App Android hỏi thông tin này mỗi lần mở. Thấp hơn phiên bản mới nhất: app nhắc cập nhật. Thấp hơn phiên bản tối thiểu:
        app bị chặn cho tới khi cập nhật. Để trống ô nào thì không áp dụng.
      </p>
      {error && <div className="alert alert-error">{error}</div>}
      {saved && <div className="alert alert-success">Đã lưu phiên bản ứng dụng</div>}
      {loading ? (
        <div className="card">Đang tải...</div>
      ) : (
        <form className="card" onSubmit={save}>
          <fieldset className="avp-ro" disabled={!editing}>
            <div className="field">
              <label>Phiên bản mới nhất</label>
              <input value={form.latestVersion} onChange={(e) => set({ latestVersion: e.target.value })} type="text" inputMode="decimal" placeholder="Ví dụ 1.2.1" />
            </div>
            <div className="field">
              <label>Phiên bản tối thiểu còn được dùng</label>
              <input value={form.minVersion} onChange={(e) => set({ minVersion: e.target.value })} type="text" inputMode="decimal" placeholder="Ví dụ 1.1.0 (để trống nếu không chặn)" />
            </div>
            <div className="field">
              <label>Đường dẫn tải ứng dụng (https)</label>
              <input value={form.downloadUrl} onChange={(e) => set({ downloadUrl: e.target.value })} type="url" placeholder="https://..." />
            </div>
            <div className="field avp-field">
              <label>Có gì mới (tối đa 500 ký tự)</label>
              <textarea value={form.notes} onChange={(e) => set({ notes: e.target.value })} rows={3} maxLength={500} placeholder="Hiện trong hộp nhắc cập nhật"></textarea>
            </div>
          </fieldset>
          <div className="avp-actions">
            {!editing ? (
              <AppButton variant="secondary" onClick={() => setEditing(true)}>Sửa</AppButton>
            ) : (
              <>
                <AppButton variant="ghost" disabled={saving} onClick={cancel}>Huỷ</AppButton>
                <AppButton variant="primary" type="submit" disabled={saving || !dirty}>{saving ? 'Đang lưu...' : 'Lưu'}</AppButton>
              </>
            )}
          </div>
        </form>
      )}
    </div>
  )
}
