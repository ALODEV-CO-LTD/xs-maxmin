// Pure helpers of Quản lý thanh toán (/admin/payment-requests).

export const PAGE = 30
export const statusLabels = { pending: 'Chờ duyệt', approved: 'Đã duyệt', rejected: 'Đã từ chối', cancelled: 'Người dùng huỷ' }
export const STATUS_TABS = [
  { key: 'all', label: 'Tất cả' },
  { key: 'cancelled', label: 'Đã huỷ' },
  { key: 'rejected', label: 'Đã từ chối' },
  { key: 'approved', label: 'Đã duyệt' },
  { key: 'pending', label: 'Chờ duyệt' },
]
export const REASONS = ['Chưa nhận được tiền', 'Số tiền không khớp', 'Sai nội dung chuyển khoản', 'Yêu cầu trùng']
export const renewalTypeLabels = { purchase: 'Mua mới', renew: 'Gia hạn' }

export const formatMoney = (v) => Number(v).toLocaleString('vi-VN') + ' đ'

/** Query string of the list / CSV export: status, optional search + date range, plus paging extras. */
export function buildQuery({ status, q = '', from = '', to = '' }, extra = {}) {
  const p = new URLSearchParams({ status })
  if (q.trim()) p.set('q', q.trim())
  if (from) p.set('from', from)
  if (to) p.set('to', to)
  for (const [k, v] of Object.entries(extra)) p.set(k, String(v))
  return p.toString()
}

export const hasFilter = ({ q, from, to }) => !!(q || from || to)

/** Only the Monday-view switch is kept in the URL: ?view=renewals. */
export const viewFromSearch = (search) => (new URLSearchParams(search).get('view') === 'renewals' ? 'renewals' : 'requests')

export const csvFileName = (now = new Date()) => `thanh-toan-${now.toISOString().slice(0, 10)}.csv`
