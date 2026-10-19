// Báo cáo kết quả tính toán từ tin nhắn đã giải mã (khung chat > Tính toán > Chọn đài > Kết quả tính toán).
// Hàm thuần, không gọi mạng: nhận các dòng đã đọc (parseMessage), kết quả xổ số của ĐÚNG đài + ngày và cấu hình giá;
// không bao giờ tự bịa số: thiếu kết quả thì trả `missingResult` và không có tiền trúng.
import { effectiveConfig } from './scoringConfig.js'
import { entryDetail, stakeMoney, winMoney } from './scoringSummary.js'
import { regionOf } from './lotteryStations.js'

// 5 nhóm thống kê theo thứ tự trong tài liệu; kiểu đánh không thuộc nhóm nào vẫn được cộng vào tổng và liệt kê riêng.
export const GROUPS = [
  { key: 'lo', label: 'Tổng số điểm lô', kinds: ['lo', 'lo3', 'lo4'] },
  { key: 'dauduoi', label: 'Tổng số điểm đầu đuôi', kinds: ['dau', 'duoi'] },
  { key: 'cang3', label: 'Tổng số 3 càng', kinds: ['cang3'] },
  { key: 'xien2', label: 'Tổng số xiên 2', kinds: ['xien2'] },
  { key: 'xien3', label: 'Tổng số xiên 3', kinds: ['xien3'] },
]
const groupOf = (kind) => GROUPS.find((g) => g.kinds.includes(kind))?.key || 'other'

export const money = (n) => `${Math.round(n).toLocaleString('vi-VN')}đ`
export const points = (n) => `${Number(n.toFixed(2)).toLocaleString('vi-VN')} điểm`

// rows: [{ type, value, score, uncertain }]; result: kết quả đài (hoặc null); station: id đài, vd 'mt-quangnam'.
export function buildReport({ rows, result, station, stationName, date, accountRates, customerRates = null }) {
  const region = regionOf(station).id
  const acc = Object.fromEntries([...GROUPS, { key: 'other' }].map((g) => [g.key, { key: g.key, label: g.label, stake: 0, stakeMoney: 0, winPoints: 0, winMoney: 0, lots: 0, kinds: new Set() }]))
  const used = rows.filter((r) => !r.uncertain)
  const skipped = rows.filter((r) => r.uncertain)
  for (const r of used) {
    const kind = r.type || 'de'
    const cfg = effectiveConfig(accountRates, customerRates, kind, region)
    const entry = { value: r.value, score: r.score, betType: kind, station }
    const d = entryDetail(entry, result, cfg, { region })
    const stake = d.score * d.lots * (d.stakeFactor || 1)
    const g = acc[groupOf(kind)]
    g.kinds.add(kind)
    g.lots += d.lots
    g.stake += stake
    g.stakeMoney += stakeMoney(kind, cfg, stake)
    if (result) {
      const hits = d.totalHits ?? d.perNumber.reduce((a, n) => a + n.hits, 0) // cấu hình cũ (không phải bảng) không có totalHits
      g.winPoints += d.score * hits
      g.winMoney += winMoney(kind, cfg, d.score, hits)
    }
  }
  const groups = GROUPS.map((g) => {
    const a = acc[g.key]
    return { ...a, kinds: [...a.kinds], rest: a.stake - a.winPoints, price: a.stake ? a.stakeMoney / a.stake : 0 }
  })
  const other = { ...acc.other, kinds: [...acc.other.kinds] }
  const all = [...groups, other]
  const totals = {
    stake: all.reduce((s, g) => s + g.stakeMoney, 0),
    won: all.reduce((s, g) => s + g.winMoney, 0),
  }
  totals.profit = result ? totals.stake - totals.won : null // "Chưa đủ dữ liệu" khi chưa có kết quả
  return { date, station, stationName, missingResult: !result, groups, other, totals, skipped, count: used.length }
}

// Mỗi nhóm: "Tổng số điểm lô: 2.500 điểm", "Đánh 2.500 điểm × 12.600 = 31.500.000đ", "Trúng 300 điểm = 3.000.000đ".
export function groupLines(g, missingResult) {
  if (!g.stake) return [`${g.label}: 0 điểm`]
  const out = [`${g.label}: ${points(g.stake)}`, `Đánh ${points(g.stake)} × ${Math.round(g.price).toLocaleString('vi-VN')} = ${money(g.stakeMoney)}`]
  out.push(missingResult ? 'Trúng: chưa đủ dữ liệu' : `Trúng ${points(g.winPoints)} = ${money(g.winMoney)} (còn ${points(g.rest)})`)
  return out
}

// Nội dung để Copy và để gửi cho khách (một nguồn duy nhất, đúng báo cáo đã tính).
export function reportText(rep) {
  const lines = ['BÁO CÁO KẾT QUẢ', `Đài: ${rep.stationName}`, `Ngày: ${rep.date.split('-').reverse().join('/')}`, '']
  for (const g of rep.groups) lines.push(...groupLines(g, rep.missingResult))
  if (rep.other.stake) lines.push(`Kiểu đánh khác: đánh ${money(rep.other.stakeMoney)}${rep.missingResult ? '' : `, trúng ${money(rep.other.winMoney)}`}`)
  lines.push('', `Tổng tiền khách đánh: ${money(rep.totals.stake)}`)
  lines.push(`Tổng tiền khách trúng: ${rep.missingResult ? 'Chưa đủ dữ liệu' : money(rep.totals.won)}`)
  lines.push(`Tổng lợi nhuận: ${rep.totals.profit == null ? 'Chưa đủ dữ liệu' : money(rep.totals.profit)}`)
  return lines.join('\n')
}

// ID ổn định theo nội dung: lưu lại nhiều lần cùng một báo cáo không tạo bản ghi trùng.
export function reportId(rep, lines) {
  const s = JSON.stringify([rep.station, rep.date, lines])
  let h = 5381
  for (let i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) | 0
  return `r${(h >>> 0).toString(36)}`
}
