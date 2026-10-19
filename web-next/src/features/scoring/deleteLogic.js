// Logic thuần của hộp "Xóa số liệu" (DeleteDataDialog.vue).
export const keepOf = (keepDays) => Math.max(0, Math.trunc(Number(keepDays) || 0))

/** Có giới hạn nào không (khách, ngày, giữ lại N ngày). Không có = xoá toàn bộ, cần ô xác nhận. */
export const hasLimit = ({ scope, from, to, keepDays }) => scope === 'customer' || !!from || !!to || keepOf(keepDays) > 0

/** Thân yêu cầu POST /me/entries/bulk-delete. */
export function deleteBody({ scope, customerName, from, to, keepDays }, extra = {}) {
  return {
    customerName: scope === 'customer' ? customerName : null,
    dateFrom: from || null,
    dateTo: to || null,
    keepDays: keepOf(keepDays),
    ...(hasLimit({ scope, from, to, keepDays }) ? {} : { allDataConfirmed: true }),
    ...extra,
  }
}

export const vn = (d) => (d ? d.split('-').reverse().join('/') : '...')

export function scopeText({ scope, customerName, from, to, keepDays }) {
  const keep = keepOf(keepDays)
  const who = scope === 'customer' ? `khách "${customerName}"` : 'TẤT CẢ khách'
  const range = from || to ? (from && from === to ? `ngày ${vn(from)}` : `ngày ${vn(from)} đến ${vn(to)}`) : 'mọi ngày'
  return `${who}, ${range}${keep ? `, giữ lại ${keep} ngày gần nhất` : ''}`
}

/** Lỗi nhập trước khi gửi, hoặc '' nếu hợp lệ. */
export function deleteProblem({ scope, from, to, keepDays }, allConfirmed, password) {
  if (!hasLimit({ scope, from, to, keepDays }) && !allConfirmed) return 'Hãy tích ô xác nhận xoá toàn bộ số liệu'
  if (!password) return 'Nhập mật khẩu đăng nhập để xác nhận'
  return ''
}
