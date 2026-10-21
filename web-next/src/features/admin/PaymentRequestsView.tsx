'use client'
import './PaymentRequestsView.css'
import { useCallback, useEffect, useRef, useState } from 'react'
import AppButton from '@/components/AppButton'
import AppSelect from '@/components/AppSelect'
import ModalDialog from '@/components/ModalDialog'
import { api } from '@/lib/api'
import { showConfirm } from '@/lib/confirm'
import { loadPackageLabels, packageLabel } from '@/lib/packageLabels'
import PackageName from './PackageName'
import RenewalsView from './RenewalsView'
import { errMsg, fmtDateTime } from './common'
import { PAGE, REASONS, STATUS_TABS, buildQuery, csvFileName, formatMoney, hasFilter, statusLabels, viewFromSearch } from './paymentLogic'

interface Req {
  id: string
  referenceCode: string
  userName: string
  username: string
  packageType: string
  amount: number
  status: string
  rejectReason?: string
  createdAt: string
  decidedAt?: string
}
interface Summary {
  pending: number
  approvedCount: number
  revenueToday: number
  revenue7d: number
  revenue30d: number
  revenueAll: number
}

// /admin/payment-requests - duyệt chuyển khoản + lịch sử gia hạn.
// API: GET /admin/payment-requests?status&q&from&to&limit&offset, GET .../export (CSV), POST .../:id/approve|reject
export default function PaymentRequestsView() {
  const [view, setView] = useState<'requests' | 'renewals'>('requests')
  const [loading, setLoading] = useState(true)
  const [loadingMore, setLoadingMore] = useState(false)
  const [error, setError] = useState('')
  const [requests, setRequests] = useState<Req[]>([])
  const [total, setTotal] = useState(0)
  const [hasMore, setHasMore] = useState(false)
  const [summary, setSummary] = useState<Summary | null>(null)
  const [status, setStatus] = useState('all') // the list opens on Tất cả, not on Chờ duyệt
  const [q, setQ] = useState('')
  const [from, setFrom] = useState('')
  const [to, setTo] = useState('')
  const [actionError, setActionError] = useState('')
  const [actionBusy, setActionBusy] = useState(false)
  const [rejectFor, setRejectFor] = useState<Req | null>(null)
  const [rejectReason, setRejectReason] = useState('')
  const count = useRef(0)
  const filters = { status, q, from, to }

  const load = useCallback(
    async (more = false) => {
      if (more) setLoadingMore(true)
      else setLoading(true)
      setError('')
      try {
        const res = await api.get(`/admin/payment-requests?${buildQuery({ status, q, from, to }, { limit: PAGE, offset: more ? count.current : 0 })}`)
        setRequests((prev) => {
          const next = more ? [...prev, ...res.requests] : res.requests
          count.current = next.length
          return next
        })
        setTotal(res.total)
        setHasMore(res.hasMore)
        setSummary(res.summary)
      } catch (err) {
        setError(errMsg(err, 'Không thể tải danh sách yêu cầu'))
      } finally {
        setLoading(false)
        setLoadingMore(false)
      }
    },
    [status, q, from, to],
  )

  useEffect(() => {
    loadPackageLabels(true)
    setView(viewFromSearch(window.location.search))
  }, [])
  // reload on any filter change (search/date debounced)
  useEffect(() => {
    const t = setTimeout(() => load(), 300)
    return () => clearTimeout(t)
  }, [load])

  const selectView = (v: 'requests' | 'renewals') => {
    setView(v)
    window.history.replaceState(null, '', v === 'renewals' ? `${window.location.pathname}?view=${v}` : window.location.pathname)
  }

  async function act(id: string, action: string, body?: object) {
    setActionBusy(true)
    try {
      await api.post(`/admin/payment-requests/${id}/${action}`, body)
      await load()
    } catch (err) {
      setActionError(errMsg(err, 'Không thể xử lý yêu cầu'))
      await load()
    } finally {
      setActionBusy(false)
    }
  }
  async function approve(r: Req) {
    setActionError('')
    const ok = await showConfirm({
      title: 'Duyệt thanh toán',
      message: `Xác nhận đã nhận ${formatMoney(r.amount)} từ ${r.userName} (${r.referenceCode}) và cấp gói ${packageLabel(r.packageType)}?`,
      confirmText: 'Duyệt',
    })
    if (ok) await act(r.id, 'approve')
  }
  async function confirmReject() {
    if (!rejectFor) return
    await act(rejectFor.id, 'reject', { reason: rejectReason.trim() })
    setRejectFor(null)
  }
  async function exportCsv() {
    setError('')
    try {
      const blob = await api.blob(`/admin/payment-requests/export?${buildQuery(filters)}`)
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = csvFileName()
      a.click()
      setTimeout(() => URL.revokeObjectURL(url), 1000)
    } catch (err) {
      setError(errMsg(err, 'Không xuất được file'))
    }
  }

  const sums = summary && [
    { label: 'Chờ duyệt', value: String(summary.pending), hot: summary.pending > 0 },
    { label: 'Doanh thu hôm nay', value: formatMoney(summary.revenueToday) },
    { label: '7 ngày', value: formatMoney(summary.revenue7d) },
    { label: '30 ngày', value: formatMoney(summary.revenue30d) },
    { label: `Tổng (${summary.approvedCount} giao dịch)`, value: formatMoney(summary.revenueAll) },
  ]

  return (
    <div className="adm-pay">
      <div className="page">
        <div className="head">
          <div>
            <h1 className="page-title">Quản lý thanh toán</h1>
            <p className="page-subtitle" style={{ marginBottom: 0 }}>Duyệt chuyển khoản, theo dõi doanh thu và lịch sử thanh toán gói dịch vụ.</p>
          </div>
          {view === 'requests' && <AppButton variant="secondary" size="sm" disabled={loading} onClick={exportCsv}>Xuất CSV</AppButton>}
        </div>

        <div className="tabs view-tabs" role="tablist" aria-label="Thanh toán">
          <button type="button" role="tab" className={`tab${view === 'requests' ? ' active' : ''}`} aria-selected={view === 'requests'} onClick={() => selectView('requests')}>Duyệt thanh toán</button>
          <button type="button" role="tab" className={`tab${view === 'renewals' ? ' active' : ''}`} aria-selected={view === 'renewals'} onClick={() => selectView('renewals')}>Lịch sử gia hạn</button>
        </div>

        {view === 'renewals' ? (
          <RenewalsView />
        ) : (
          <>
            {sums && (
              <div className="sum-grid">
                {sums.map((s) => (
                  <div key={s.label} className={`card sum-card${s.hot ? ' hot' : ''}`}>
                    <div className="sum-label">{s.label}</div>
                    <div className="sum-value">{s.value}</div>
                  </div>
                ))}
              </div>
            )}

            <div className="filters">
              <div className="f-status">
                <AppSelect value={status} onChange={(v: string) => setStatus(v)} aria-label="Trạng thái">
                  {STATUS_TABS.map((t) => (
                    <option key={t.key} value={t.key}>{t.label}</option>
                  ))}
                </AppSelect>
              </div>
              <input value={q} onChange={(e) => setQ(e.target.value)} type="search" className="f-input f-q" placeholder="Tìm tên, tài khoản hoặc mã tham chiếu..." aria-label="Tìm kiếm" />
              <label className="f-date">Từ <input value={from} onChange={(e) => setFrom(e.target.value)} type="date" className="f-input" /></label>
              <label className="f-date">Đến <input value={to} onChange={(e) => setTo(e.target.value)} type="date" className="f-input" /></label>
              {hasFilter(filters) && <AppButton variant="ghost" size="sm" onClick={() => { setQ(''); setFrom(''); setTo('') }}>Xoá lọc</AppButton>}
            </div>

            {error && <div className="alert alert-error">{error}</div>}
            {actionError && <div className="alert alert-error">{actionError}</div>}

            <div className="card" style={{ padding: 0, overflowX: 'auto' }}>
              <table className="table stack-table">
                <thead>
                  <tr>
                    <th>Mã</th>
                    <th>Khách hàng</th>
                    <th>Gói</th>
                    <th>Số tiền</th>
                    <th>Trạng thái</th>
                    <th>Thời gian</th>
                    <th>Thao tác</th>
                  </tr>
                </thead>
                <tbody>
                  {loading ? (
                    <tr><td colSpan={7}>Đang tải...</td></tr>
                  ) : requests.length === 0 ? (
                    <tr><td colSpan={7}>Không có yêu cầu nào</td></tr>
                  ) : (
                    requests.map((r) => (
                      <tr key={r.id}>
                        <td data-label="Mã"><code className="ref">{r.referenceCode}</code></td>
                        <td data-label="Khách hàng">{r.userName} (@{r.username})</td>
                        <td data-label="Gói"><PackageName code={r.packageType} /></td>
                        <td data-label="Số tiền">{formatMoney(r.amount)}</td>
                        <td data-label="Trạng thái">
                          <span className={`chip${r.status === 'approved' ? ' chip-accent' : r.status === 'rejected' ? ' chip-danger' : r.status === 'pending' ? ' chip-warning' : ''}`}>
                            {statusLabels[r.status as keyof typeof statusLabels] || r.status}
                          </span>
                          {r.rejectReason && r.status === 'rejected' && <div className="reason">{r.rejectReason}</div>}
                        </td>
                        <td data-label="Thời gian">
                          {fmtDateTime(r.createdAt)}
                          {r.decidedAt && <div className="reason">Xử lý: {fmtDateTime(r.decidedAt)}</div>}
                        </td>
                        <td data-label="Thao tác">
                          {r.status === 'pending' ? (
                            <div style={{ display: 'flex', gap: 6 }}>
                              <AppButton variant="primary" size="sm" disabled={actionBusy} onClick={() => approve(r)}>Duyệt</AppButton>
                              <AppButton variant="danger" size="sm" disabled={actionBusy} onClick={() => { setActionError(''); setRejectFor(r); setRejectReason('') }}>Từ chối</AppButton>
                            </div>
                          ) : (
                            <span>-</span>
                          )}
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
            {!loading && requests.length > 0 && (
              <div className="more">
                <span>Hiển thị {requests.length} / {total}</span>
                {hasMore && <AppButton variant="secondary" size="sm" disabled={loadingMore} onClick={() => load(true)}>{loadingMore ? 'Đang tải...' : 'Xem thêm'}</AppButton>}
              </div>
            )}

            <ModalDialog
              open={!!rejectFor}
              title="Từ chối thanh toán"
              description={rejectFor ? `${rejectFor.userName} - ${rejectFor.referenceCode} - ${formatMoney(rejectFor.amount)}` : ''}
              onClose={() => setRejectFor(null)}
              footer={
                <>
                  <AppButton variant="ghost" onClick={() => setRejectFor(null)}>Huỷ</AppButton>
                  <AppButton variant="danger" disabled={actionBusy} onClick={confirmReject}>Từ chối</AppButton>
                </>
              }
            >
              {/* ModalDialog renders in a portal outside .adm-pay, so the scoped rules need their own wrapper */}
              <div className="adm-pay">
                <label className="r-label" htmlFor="reject-reason">Lý do (người dùng sẽ nhìn thấy)</label>
                <div className="r-quick">
                  {REASONS.map((x) => (
                    <button key={x} type="button" className="r-chip" onClick={() => setRejectReason(x)}>{x}</button>
                  ))}
                </div>
                <textarea id="reject-reason" value={rejectReason} onChange={(e) => setRejectReason(e.target.value)} className="f-input r-text" rows={3} maxLength={200} data-autofocus placeholder="Không bắt buộc" />
              </div>
            </ModalDialog>
          </>
        )}
      </div>
    </div>
  )
}
