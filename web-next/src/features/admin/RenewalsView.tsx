'use client'
import { useEffect, useState } from 'react'
import { api } from '@/lib/api'
import { loadPackageLabels } from '@/lib/packageLabels'
import PackageName from './PackageName'
import { errMsg, fmtDateTime } from './common'
import { formatMoney, renewalTypeLabels } from './paymentLogic'

interface Renewal {
  id: string
  userName: string
  type: string
  packageType: string
  amount: number
  createdAt: string
}

// Tab "Lịch sử gia hạn" of /admin/payment-requests. API: GET /admin/renewals (latest 200, read-only)
export default function RenewalsView() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [renewals, setRenewals] = useState<Renewal[]>([])

  useEffect(() => {
    loadPackageLabels(true)
    api
      .get('/admin/renewals')
      .then((res) => setRenewals(res.renewals))
      .catch((err) => setError(errMsg(err, 'Không thể tải danh sách gia hạn')))
      .finally(() => setLoading(false))
  }, [])

  return (
    <div>
      <p className="page-subtitle">Lịch sử mua/gia hạn gói dịch vụ toàn hệ thống, gồm các yêu cầu đã được duyệt (tối đa 200 gần nhất)</p>
      {error && <div className="alert alert-error">{error}</div>}
      <div className="card" style={{ padding: 0, overflowX: 'auto' }}>
        <table className="table stack-table">
          <thead>
            <tr>
              <th>Khách hàng</th>
              <th>Loại</th>
              <th>Gói</th>
              <th>Số tiền</th>
              <th>Thời gian</th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={5}>Đang tải...</td></tr>
            ) : renewals.length === 0 ? (
              <tr><td colSpan={5}>Chưa có giao dịch nào</td></tr>
            ) : (
              renewals.map((r) => (
                <tr key={r.id}>
                  <td data-label="Khách hàng">{r.userName}</td>
                  <td data-label="Loại"><span className={`chip${r.type === 'renew' ? ' chip-brand' : ''}`}>{renewalTypeLabels[r.type as keyof typeof renewalTypeLabels] || r.type}</span></td>
                  <td data-label="Gói"><PackageName code={r.packageType} /></td>
                  <td data-label="Số tiền">{formatMoney(r.amount)}</td>
                  <td data-label="Thời gian">{fmtDateTime(r.createdAt)}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  )
}
