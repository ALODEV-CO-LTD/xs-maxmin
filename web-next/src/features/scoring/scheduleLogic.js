// Logic thuần của "Lịch xoá dữ liệu" (DeletionSchedules.vue).
export const TTL_TEXT = { 3600: '1 giờ', 86400: '1 ngày', 604800: '7 ngày', 2592000: '30 ngày' }
export const UNIT_TEXT = { day: 'ngày', week: 'tuần', month: 'tháng' }

export const fmt = (iso) => (iso ? new Date(iso).toLocaleString('vi-VN') : '')
export const repeatText = (r) => (r ? `${r.every} ${UNIT_TEXT[r.unit] || r.unit}` : '')

/** Lựa chọn lặp thành { every, unit } của API (null = một lần). */
export function repeatValue(form) {
  switch (form.repeat) {
    case '1w':
      return { every: 1, unit: 'week' }
    case '10d':
      return { every: 10, unit: 'day' }
    case '1m':
      return { every: 1, unit: 'month' }
    case 'custom':
      return { every: Math.trunc(Number(form.customN)) || 0, unit: form.customUnit }
    default:
      return null
  }
}

export function addCycle(date, r) {
  const d = new Date(date)
  if (!r) d.setDate(d.getDate() + 1)
  else if (r.unit === 'day') d.setDate(d.getDate() + r.every)
  else if (r.unit === 'week') d.setDate(d.getDate() + 7 * r.every)
  else d.setMonth(d.getMonth() + r.every)
  return d
}

export function toLocalInput(d) {
  const p = (n) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`
}

/** Lần chạy đầu mặc định = bây giờ + một chu kỳ, cho tới khi người dùng tự nhập. */
export function defaultRunAt(form, now = new Date()) {
  const r = repeatValue(form)
  return toLocalInput(addCycle(now, r && r.every > 0 ? r : null))
}

export function describe(s) {
  if (s.kind === 'chat') {
    const what = s.chatScope === 'images' ? 'Ảnh' : 'Tin nhắn & tệp'
    return `${what} cũ hơn ${TTL_TEXT[s.ttlSeconds] || s.ttlSeconds + ' giây'} trong cuộc trò chuyện với ${s.friendName || '?'}`
  }
  const who = s.customerName ? `khách "${s.customerName}"` : 'mọi khách'
  const range = s.dateFrom || s.dateTo ? `, ngày ${s.dateFrom || '...'} đến ${s.dateTo || '...'}` : ', mọi ngày'
  const keep = s.keepDays > 0 ? `, giữ lại ${s.keepDays} ngày gần nhất` : ''
  return `Số liệu đã nhập của ${who}${range}${keep}`
}

export function statusText(s) {
  if (s.status === 'done') return `Đã xoá ${s.deletedCount} mục lúc ${fmt(s.executedAt)}`
  if (s.kind === 'chat') return `Đang áp dụng từ ${fmt(s.runAt)}${s.deletedCount ? ` (đã xoá ${s.deletedCount} mục)` : ''}`
  return `Sẽ xoá lúc ${fmt(s.runAt)}`
}

/** Kiểm tra form trước khi gửi: { error } hoặc { body, repeat, keep }. */
export function buildScheduleBody(form) {
  if (!form.runAt) return { error: 'Vui lòng chọn thời điểm xoá' }
  const repeat = repeatValue(form)
  if (form.repeat === 'custom' && (!repeat.every || repeat.every < 1 || repeat.every > 365)) return { error: 'Chu kỳ lặp phải từ 1 đến 365' }
  const keep = Math.trunc(Number(form.keepDays) || 0)
  if (keep < 0 || keep > 3650) return { error: 'Số ngày giữ lại phải từ 0 đến 3650' }
  if (!form.password) return { error: 'Nhập mật khẩu đăng nhập để xác nhận' }
  const body = { kind: 'data', customerName: form.customerName || undefined, runAt: new Date(form.runAt).toISOString() }
  if (repeat) body.repeat = repeat
  else {
    body.dateFrom = form.dateFrom || undefined
    body.dateTo = form.dateTo || undefined
  }
  if (keep > 0) body.keepDays = keep
  return { body, repeat, keep }
}

/** Nội dung hộp xác nhận từ bản xem trước của máy chủ (scopeText đã đủ thì không thêm dòng). */
export function confirmMessage(preview, body, repeat) {
  const scope = preview.scopeText || ''
  const lines = [`CẢNH BÁO: ${scope}`]
  if (repeat && !/lặp/i.test(scope)) lines.push(`Lặp lại mỗi ${repeatText(repeat)}.`)
  if (!/lần đầu|lúc \d/i.test(scope)) lines.push(`Thời điểm xoá${repeat ? ' lần đầu' : ''}: ${fmt(preview.runAt || body.runAt)}.`)
  if (typeof preview.willDeleteNow === 'number' && !/xoá ngay|xóa ngay|chạy ngay/i.test(scope)) lines.push(`Nếu chạy ngay bây giờ sẽ xoá ${preview.willDeleteNow} số liệu.`)
  lines.push('Bạn có thể huỷ lịch trước thời điểm này.')
  return lines.join('\n\n')
}
