'use client'
import './RestoreCustomer.css'
import { useEffect, useState } from 'react'
import AppButton from '@/components/AppButton'
import ModalDialog from '@/components/ModalDialog'
import { api } from '@/lib/api'
import { errMsg, fmtDateTime } from './common'
import { formatSize } from './settingsLogic'
import { backupSourceLabel, canRestoreCustomer, countsSummary, customerTitle, filterBackupCustomers, restoreResultText } from './trashLogic'

export interface BackupSource {
  id: string
  source: string
  name: string
  size: number
  createdAt?: string
}
interface BackupCustomer {
  id: string
  username: string
  name?: string
  inBackup: Record<string, number>
  now: Record<string, number> | null // null: the account no longer exists
}

// "Khôi phục dữ liệu một khách" (Cài đặt > Sao lưu): for a customer who deleted numbers by mistake. Pick a backup, then
// the customer, then how. API: GET /admin/backups (sources), GET /admin/backups/users?backup=, POST /admin/backups/restore-user
export default function RestoreCustomer({ sources }: { sources: BackupSource[] }) {
  const [picked, setPicked] = useState<BackupSource | null>(null)
  return (
    <div className="adm-restore">
      <h2>Khôi phục dữ liệu một khách</h2>
      <p className="sub">Khi khách lỡ xoá số liệu và nhờ bạn: chọn một bản sao lưu, rồi chọn khách. Chỉ dữ liệu của khách đó được đụng tới (số liệu, khách hàng, kết quả, mẫu cú pháp, lịch xoá); người khác giữ nguyên. Chỉ lấy lại được những gì đã có trong bản sao lưu.</p>
      {sources.length === 0 ? (
        <p className="sub">Chưa có bản sao lưu nào.</p>
      ) : (
        sources.map((b) => (
          <div key={b.id} className="card row" data-testid={`restore-${b.id}`}>
            <div>
              <div className="name">{b.name}</div>
              <div className="info">{backupSourceLabel(b.source)} · {fmtDateTime(b.createdAt)} · {formatSize(b.size)}</div>
            </div>
            <AppButton variant="secondary" size="sm" onClick={() => setPicked(b)}>Khôi phục</AppButton>
          </div>
        ))
      )}
      {picked && <RestoreDialog backup={picked} onClose={() => setPicked(null)} />}
    </div>
  )
}

function RestoreDialog({ backup, onClose }: { backup: BackupSource; onClose: () => void }) {
  const [loading, setLoading] = useState(true)
  const [working, setWorking] = useState(false)
  const [error, setError] = useState('')
  const [result, setResult] = useState('')
  const [customers, setCustomers] = useState<BackupCustomer[]>([])
  const [picked, setPicked] = useState<BackupCustomer | null>(null)
  const [replace, setReplace] = useState(false)
  const [search, setSearch] = useState('')
  const [confirmText, setConfirmText] = useState('')

  const url = `/admin/backups/users?backup=${encodeURIComponent(backup.id)}`
  // Reload after a restore (the first load is in the effect: state is only set from promise callbacks).
  async function reload() {
    try {
      setCustomers((await api.get(url)).users || [])
    } catch (err) {
      setError(errMsg(err, 'Không đọc được bản sao lưu này'))
    }
  }
  useEffect(() => {
    api
      .get(url)
      .then((res) => setCustomers(res.users || []))
      .catch((err) => setError(errMsg(err, 'Không đọc được bản sao lưu này')))
      .finally(() => setLoading(false))
  }, [url])

  async function restore() {
    if (!picked) return
    setWorking(true)
    setError('')
    setResult('')
    try {
      const res = await api.post('/admin/backups/restore-user', { backup: backup.id, userId: picked.id, mode: replace ? 'replace' : 'merge' })
      setResult(restoreResultText(picked, res.written || {}, res.safetyBackup))
      await reload()
    } catch (err) {
      setError(errMsg(err, 'Không khôi phục được'))
    } finally {
      setWorking(false)
    }
  }

  const shown = filterBackupCustomers(customers, search)
  const ok = canRestoreCustomer({ customer: picked, replace, confirmText, working })
  return (
    <ModalDialog open wide title="Khôi phục dữ liệu một khách" description={`${backupSourceLabel(backup.source)} · ${fmtDateTime(backup.createdAt)}`} onClose={onClose}
      footer={picked ? (
        <>
          <AppButton variant="secondary" disabled={working} onClick={() => { setPicked(null); setResult(''); setError('') }}>Chọn khách khác</AppButton>
          <AppButton variant={replace ? 'danger' : 'primary'} disabled={!ok} onClick={restore}>{working ? 'Đang khôi phục...' : replace ? 'Thay thế dữ liệu' : 'Khôi phục'}</AppButton>
        </>
      ) : undefined}>
      <div className="adm-restore">
        {error && <div className="alert alert-error">{error}</div>}
        {result && <div className="alert alert-success">{result}</div>}
        {loading ? (
          <p className="sub">Đang tải...</p>
        ) : !picked ? (
          <>
            <div className="field">
              <label htmlFor="restore-search">Tìm khách (tên đăng nhập hoặc tên)</label>
              <input id="restore-search" value={search} onChange={(e) => setSearch(e.target.value)} type="search" autoComplete="off" />
            </div>
            {shown.length === 0 && <p className="sub">Không có khách nào khớp trong bản sao lưu này.</p>}
            <div className="list">
              {shown.map((c: BackupCustomer) => (
                <button key={c.id} type="button" className="cust" data-testid={`customer-${c.id}`} onClick={() => { setPicked(c); setResult(''); setError(''); setReplace(false); setConfirmText('') }}>
                  <div className="t">{customerTitle(c)}</div>
                  <div className="d">{c.now == null ? 'Tài khoản đã bị xoá (dùng Thùng rác)' : `Lúc đó: ${countsSummary(c.inBackup) || 'chưa có dữ liệu'}`}</div>
                </button>
              ))}
            </div>
          </>
        ) : (
          <>
            <h3>{customerTitle(picked)}</h3>
            <div className="kv"><span className="k">Trong bản sao lưu</span><span>{countsSummary(picked.inBackup) || 'chưa có dữ liệu'}</span></div>
            <div className="kv"><span className="k">Hiện tại</span><span>{picked.now == null ? 'Tài khoản không còn' : countsSummary(picked.now) || 'chưa có dữ liệu'}</span></div>
            <label className="mode">
              <input type="radio" name="restore-mode" checked={!replace} onChange={() => setReplace(false)} />
              <span>Thêm lại phần còn thiếu (khuyên dùng)<span className="d">Không ghi đè, không nhân đôi; dữ liệu khách nhập sau bản sao lưu được giữ.</span></span>
            </label>
            <label className="mode">
              <input type="radio" name="restore-mode" checked={replace} onChange={() => setReplace(true)} />
              <span>Thay toàn bộ bằng bản sao lưu<span className="d">Xoá dữ liệu hiện tại của khách này rồi ghi lại như bản sao lưu: những gì khách nhập sau đó sẽ mất.</span></span>
            </label>
            {replace && (
              <div className="field">
                <label htmlFor="restore-confirm">Gõ &quot;{picked.username}&quot; để xác nhận</label>
                <input id="restore-confirm" value={confirmText} onChange={(e) => setConfirmText(e.target.value)} autoComplete="off" />
              </div>
            )}
            <p className="note">Trước khi khôi phục, hệ thống tự tạo một bản sao lưu mới nên việc này cũng quay lại được.</p>
          </>
        )}
      </div>
    </ModalDialog>
  )
}
