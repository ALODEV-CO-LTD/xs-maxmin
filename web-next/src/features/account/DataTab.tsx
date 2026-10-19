'use client'
import { useState } from 'react'
import AppButton from '@/components/AppButton'
import { api } from '@/lib/api'
import { showConfirm } from '@/lib/confirm'
import { WIPE_DELETES, WIPE_KEEPS, deleteAllMessage } from './accountLogic'
import DeletionSchedules from './DeletionSchedules'

// Tài khoản > Dữ liệu: scheduled deletion (K35/K36/S05) and "Xoá toàn bộ dữ liệu". API: POST /me/delete-data { password }
export default function DataTab() {
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')
  const [deleting, setDeleting] = useState(false)

  async function deleteAll() {
    if (!(await showConfirm({ title: 'Xoá toàn bộ dữ liệu', message: deleteAllMessage(), confirmText: 'Xoá dữ liệu', danger: true }))) return
    const password = prompt('Nhập mật khẩu đăng nhập để xác nhận xoá dữ liệu:')
    if (!password) return
    setError('')
    setSuccess('')
    setDeleting(true)
    try {
      await api.post('/me/delete-data', { password })
      setSuccess('Đã xoá toàn bộ dữ liệu của bạn.')
    } catch (err) {
      setError((err as Error).message || 'Không xoá được dữ liệu')
    } finally {
      setDeleting(false)
    }
  }

  return (
    <>
      <DeletionSchedules />
      <div className="card acct-danger">
        <h3 className="acct-h3" style={{ color: 'var(--danger-text)' }}>Xoá toàn bộ dữ liệu</h3>
        <p className="page-subtitle acct-sub">Xoá: {WIPE_DELETES}. {WIPE_KEEPS} Không thể hoàn tác.</p>
        {error && <div className="alert alert-error">{error}</div>}
        {success && <div className="alert alert-success">{success}</div>}
        <AppButton variant="danger" onClick={deleteAll} disabled={deleting}>{deleting ? 'Đang xoá...' : 'Xoá toàn bộ dữ liệu'}</AppButton>
      </div>
    </>
  )
}
