'use client'
import './Packages.css'
import { useCallback, useEffect, useRef, useState } from 'react'
import AppButton from '@/components/AppButton'
import { api } from '@/lib/api'
import { useAuthStore } from '@/lib/authStore'
import { showConfirm } from '@/lib/confirm'
import { useNotifyStore } from '@/lib/notifyStore'
import { formatDate, formatDateTime, formatVnd, pendingOf, planLabel, qrUrlOf, statusChipClass, statusLabel } from './accountLogic'

// Combined Gói dịch vụ + Thanh toán: current package status, purchasable plan catalog, bank transfer info and the user's
// own payment-request history in one page. Purchasing only creates a *pending* payment request - an admin must approve
// it via bank transfer confirmation before the package/quota is granted. Shown as a tab of Tài khoản (`embedded` hides
// the page title there); /packages and /payments redirect to /account?tab=packages.
// API: GET /me (current package), GET /me/packages (catalog), GET /me/payment-info (bank transfer details),
//      GET /me/payment-requests (history + pending check), POST /me/packages/purchase, POST /me/payment-requests/:id/cancel
/* eslint-disable @typescript-eslint/no-explicit-any */
export default function PackagesPanel({ embedded = true }: { embedded?: boolean }) {
  const user = useAuthStore((s) => s.user) as any
  const fetchMe = useAuthStore((s) => s.fetchMe)
  const paymentTick = useNotifyStore((s) => s.paymentTick)

  const [plans, setPlans] = useState<any[]>([])
  const [bankInfo, setBankInfo] = useState<any>(null)
  const [requests, setRequests] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [loadError, setLoadError] = useState('')
  const [purchasing, setPurchasing] = useState<string | null>(null)
  const [purchaseError, setPurchaseError] = useState('')
  const [purchaseSuccess, setPurchaseSuccess] = useState('')
  const [cancelling, setCancelling] = useState(false)
  const [copied, setCopied] = useState(false)
  const copyTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  const pkg = user?.package
  const pending = pendingOf(requests)
  const qrUrl = qrUrlOf(bankInfo, pending, user)

  const loadAll = useCallback(async () => {
    setLoading(true)
    setLoadError('')
    try {
      const [, catalog, info, reqs] = await Promise.all([fetchMe(), api.get('/me/packages'), api.get('/me/payment-info'), api.get('/me/payment-requests')])
      setPlans(catalog.packages)
      setBankInfo(info)
      setRequests(reqs.requests)
    } catch (err) {
      setLoadError((err as Error).message || 'Không tải được thông tin gói')
    } finally {
      setLoading(false)
    }
  }, [fetchMe])

  // first load, and again whenever Admin decides while this page is open (push)
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    loadAll()
  }, [paymentTick, loadAll])
  useEffect(() => () => void (copyTimer.current && clearTimeout(copyTimer.current)), [])

  async function copyReference(code: string) {
    try {
      await navigator.clipboard.writeText(code)
      setCopied(true)
      if (copyTimer.current) clearTimeout(copyTimer.current)
      copyTimer.current = setTimeout(() => setCopied(false), 2000)
    } catch {
      /* clipboard blocked - the code is selectable on screen anyway */
    }
  }

  async function cancelPending() {
    const r = pending
    if (!r) return
    if (!(await showConfirm({
      title: 'Huỷ yêu cầu',
      message: `Huỷ yêu cầu gói "${planLabel(plans, r.packageType)}" (${r.referenceCode})? Nếu bạn đã chuyển khoản, hãy liên hệ admin trước khi huỷ.`,
      confirmText: 'Huỷ yêu cầu',
      danger: true,
    }))) return
    setCancelling(true)
    setPurchaseError('')
    try {
      await api.post(`/me/payment-requests/${r.id}/cancel`)
      setPurchaseSuccess('Đã huỷ yêu cầu.')
      await loadAll()
    } catch (err) {
      setPurchaseError((err as Error).message || 'Không huỷ được yêu cầu')
      await loadAll()
    } finally {
      setCancelling(false)
    }
  }

  async function purchase(plan: any) {
    setPurchaseError('')
    setPurchaseSuccess('')
    if (pending) return
    if (!(await showConfirm({
      title: 'Đăng ký gói',
      message: `Xác nhận đăng ký gói "${plan.label}" (${formatVnd(plan.priceVnd)})? Bạn sẽ cần chuyển khoản và chờ admin duyệt.`,
      confirmText: 'Đăng ký',
    }))) return
    setPurchasing(plan.type)
    try {
      await api.post('/me/packages/purchase', { packageType: plan.type })
      setPurchaseSuccess('Đã tạo yêu cầu. Vui lòng chuyển khoản theo thông tin bên dưới và chờ admin xác nhận.')
      await loadAll()
    } catch (err) {
      setPurchaseError((err as Error).message || 'Không tạo được yêu cầu mua gói')
    } finally {
      setPurchasing(null)
    }
  }

  return (
    <div className={embedded ? 'pk-embedded' : 'page pk-page'}>
      {!embedded && (
        <>
          <h1 className="page-title">Gói dịch vụ & Thanh toán</h1>
          <p className="page-subtitle">Xem gói hiện tại, đăng ký gói mới và theo dõi thanh toán, tất cả ở một nơi.</p>
        </>
      )}

      {loading ? (
        <div className="card">Đang tải...</div>
      ) : loadError ? (
        <div className="alert alert-error">{loadError}</div>
      ) : (
        <>
          <div className="card pk-current">
            <h3>Gói hiện tại</h3>
            <div className="pk-current-row">
              <span className={`chip ${pkg?.isActive ? 'chip-accent' : 'chip-danger'}`}>{pkg?.label}</span>
              <span className="pk-current-detail">Hết hạn: {formatDate(pkg?.expiresAt)}</span>
            </div>
            {!pkg?.isActive && (
              <div className="alert alert-warning" style={{ marginTop: 12, marginBottom: 0 }}>
                Gói đã hết hạn. Đăng ký gói mới bên dưới để tiếp tục sử dụng.
              </div>
            )}
          </div>

          {pending && (
            <div className="alert alert-warning pk-pending">
              <div>
                Yêu cầu gói &quot;{planLabel(plans, pending.packageType)}&quot; ({formatVnd(pending.amount)}) đang chờ admin xác nhận.
                Chuyển khoản đúng số tiền và ghi nội dung{' '}
                <strong className="pk-ref">{pending.referenceCode}</strong> để được duyệt nhanh.
              </div>
              <div className="pk-pending-actions">
                <AppButton variant="secondary" size="sm" onClick={() => copyReference(pending.referenceCode)}>{copied ? 'Đã sao chép' : 'Sao chép nội dung'}</AppButton>
                <AppButton variant="ghost" size="sm" disabled={cancelling} onClick={cancelPending}>Huỷ yêu cầu</AppButton>
              </div>
            </div>
          )}
          {purchaseError && <div className="alert alert-error">{purchaseError}</div>}
          {purchaseSuccess && <div className="alert alert-success">{purchaseSuccess}</div>}

          <h3>Các gói có sẵn</h3>
          <div className="pk-plans">
            {plans.map((plan) => (
              <div key={plan.type} className="card pk-plan">
                <div className="pk-plan-label">{plan.label}</div>
                <div className="pk-plan-price">{formatVnd(plan.priceVnd)}</div>
                <div className="pk-plan-detail">{plan.durationDays} ngày</div>
                <AppButton variant="primary" block style={{ marginTop: 12 }} disabled={!!pending || purchasing === plan.type} onClick={() => purchase(plan)}>
                  {purchasing === plan.type ? 'Đang xử lý...' : 'Đăng ký'}
                </AppButton>
              </div>
            ))}
          </div>

          <div className="card pk-bank">
            <h3>Thông tin chuyển khoản</h3>
            {bankInfo?.bankName ? (
              <>
                <div className="pk-row"><span>Ngân hàng</span><strong>{bankInfo.bankName}</strong></div>
                <div className="pk-row"><span>Số tài khoản</span><strong>{bankInfo.bankAccountNumber}</strong></div>
                <div className="pk-row"><span>Chủ tài khoản</span><strong>{bankInfo.bankAccountHolder}</strong></div>
                {pending && (
                  <>
                    <div className="pk-row"><span>Số tiền</span><strong>{formatVnd(pending.amount)}</strong></div>
                    <div className="pk-row"><span>Nội dung</span><strong className="pk-ref">{pending.referenceCode}</strong></div>
                  </>
                )}
                {qrUrl && (
                  <div className="pk-qr">
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={qrUrl} alt="Mã QR chuyển khoản" className="pk-qr-img" />
                    <p className="page-subtitle" style={{ textAlign: 'center', margin: '8px 0 0' }}>
                      Quét mã bằng app ngân hàng để tự động điền số tiền và nội dung chuyển khoản.
                    </p>
                  </div>
                )}
              </>
            ) : (
              <p className="page-subtitle">Chưa cấu hình thông tin thanh toán.</p>
            )}
          </div>

          <h3>Lịch sử thanh toán</h3>
          {requests.length === 0 ? (
            <div className="card pk-empty">Chưa có yêu cầu nào.</div>
          ) : (
            <div className="pk-req-list">
              {requests.map((r) => (
                <div key={r.id} className="card pk-req">
                  <div className="pk-req-top">
                    <strong>{planLabel(plans, r.packageType)}</strong>
                    <span className={`chip ${statusChipClass(r.status)}`}>{statusLabel(r.status)}</span>
                  </div>
                  <div className="pk-req-detail">
                    {formatVnd(r.amount)} · {formatDateTime(r.createdAt)}
                    {r.referenceCode && ` · ${r.referenceCode}`}
                  </div>
                  {r.status === 'rejected' && r.rejectReason && <div className="pk-req-reason">Lý do: {r.rejectReason}</div>}
                </div>
              ))}
            </div>
          )}
        </>
      )}
    </div>
  )
}
