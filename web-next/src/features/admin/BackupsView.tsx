'use client'
import './BackupsView.css'
import { useEffect, useState } from 'react'
import AppButton from '@/components/AppButton'
import { api } from '@/lib/api'
import { errMsg, fmtDateTime } from './common'
import RestoreCustomer, { type BackupSource } from './RestoreCustomer'
import { formatSize } from './settingsLogic'

interface Backup {
  name: string
  createdAt: string
  size: number
}

// Sao lưu dữ liệu, embedded in Cài đặt. API: GET/POST /admin/backups, GET /admin/backups/:name (Blob download)
export default function BackupsView({ embedded = false }: { embedded?: boolean }) {
  const [backups, setBackups] = useState<Backup[]>([])
  const [sources, setSources] = useState<BackupSource[]>([])
  const [loading, setLoading] = useState(true)
  const [creating, setCreating] = useState(false)
  const [downloading, setDownloading] = useState('')
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')

  useEffect(() => {
    api
      .get('/admin/backups')
      .then((res) => {
        setBackups(res.backups)
        setSources(res.sources || [])
      })
      .catch((err) => setError(errMsg(err, 'Không tải được danh sách')))
      .finally(() => setLoading(false))
  }, [])

  async function create() {
    setCreating(true)
    setError('')
    setMessage('')
    try {
      const b = await api.post('/admin/backups')
      setBackups((l) => [b, ...l])
      api.get('/admin/backups').then((res) => setSources(res.sources || [])).catch(() => {})
      setMessage(`Đã tạo bản sao lưu ${b.name}`)
    } catch (err) {
      setError(errMsg(err, 'Không tạo được bản sao lưu'))
    } finally {
      setCreating(false)
    }
  }

  async function download(b: Backup) {
    setDownloading(b.name)
    setError('')
    try {
      const blob = await api.blob(`/admin/backups/${encodeURIComponent(b.name)}`)
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = b.name
      document.body.appendChild(a)
      a.click()
      a.remove()
      setTimeout(() => URL.revokeObjectURL(url), 1000)
    } catch (err) {
      setError(errMsg(err, 'Không tải được tệp'))
    } finally {
      setDownloading('')
    }
  }

  return (
    <div className="adm-backups">
      <div className={embedded ? 'embedded' : 'page'}>
        {!embedded && <h1 className="page-title">Sao lưu dữ liệu</h1>}
        <p className="page-subtitle">Tạo bản sao lưu cơ sở dữ liệu (lưu trên máy chủ) và tải về máy của bạn. Bản sao lưu chứa dữ liệu của mọi người dùng, hãy cất giữ cẩn thận.</p>

        {error && <div className="alert alert-error">{error}</div>}
        {message && <div className="alert alert-success">{message}</div>}

        <div className="card">
          <AppButton variant="primary" disabled={creating} onClick={create}>{creating ? 'Đang tạo...' : 'Tạo bản sao lưu mới'}</AppButton>

          {loading ? (
            <div className="gap">Đang tải...</div>
          ) : backups.length === 0 ? (
            <p className="gap muted">Chưa có bản sao lưu nào.</p>
          ) : (
            <table className="table stack-table gap">
              <thead>
                <tr><th>Tên tệp</th><th>Thời gian</th><th>Dung lượng</th><th></th></tr>
              </thead>
              <tbody>
                {backups.map((b) => (
                  <tr key={b.name}>
                    <td data-label="Tên tệp">{b.name}</td>
                    <td data-label="Thời gian">{fmtDateTime(b.createdAt)}</td>
                    <td data-label="Dung lượng">{formatSize(b.size)}</td>
                    <td>
                      <AppButton variant="secondary" size="sm" disabled={downloading === b.name} onClick={() => download(b)}>{downloading === b.name ? 'Đang tải...' : 'Tải về'}</AppButton>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>

        <RestoreCustomer sources={sources} />
      </div>
    </div>
  )
}
