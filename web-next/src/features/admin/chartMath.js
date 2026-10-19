// Pure maths + labels of StatsChart (port of the script block of components/StatsChart.vue).

// Round the axis maximum up to 1/2/5 x 10^n so ticks read cleanly.
export function niceMax(v) {
  if (v <= 0) return 4
  const p = 10 ** Math.floor(Math.log10(v))
  const n = v / p
  return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10) * p
}

export function axisMax(values, money) {
  const m = niceMax(Math.max(0, ...values))
  return money ? m : Math.max(4, m)
}

/** Axis label under a bucket: day dd/mm, month mm/yy, year yyyy. */
export function shortDate(k) {
  if (k.length === 4) return k
  return k.length === 7 ? `${k.slice(5)}/${k.slice(2, 4)}` : `${k.slice(8)}/${k.slice(5, 7)}`
}

/** Tooltip title. `unit` 'week' means the key is the Monday of the week. */
export function longDate(k, unit = 'day') {
  if (k.length === 4) return `Năm ${k}`
  if (k.length === 7) return `Tháng ${k.slice(5)}/${k.slice(0, 4)}`
  if (unit === 'week') {
    const mon = new Date(+k.slice(0, 4), +k.slice(5, 7) - 1, +k.slice(8, 10))
    const sun = new Date(mon.getFullYear(), mon.getMonth(), mon.getDate() + 6)
    const f = (d) => `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}`
    return `Tuần ${f(mon)} – ${f(sun)}/${sun.getFullYear()}`
  }
  return `${k.slice(8)}/${k.slice(5, 7)}/${k.slice(0, 4)}`
}

/** Axis tick text. */
export function shortValue(v, money) {
  if (!money) return String(+v.toFixed(1))
  if (v >= 1e6) return `${+(v / 1e6).toFixed(1)}tr`
  if (v >= 1e3) return `${+(v / 1e3).toFixed(0)}k`
  return String(v)
}

export const fullValue = (v, money) => (money ? Number(v).toLocaleString('vi-VN') + ' đ' : String(v))

/** Indexes whose x label is drawn: every n-th (so they don't overlap) plus the last. */
export function labelIndexes(count, plotW) {
  const every = Math.ceil(count / Math.max(3, Math.floor(plotW / 70)))
  const out = []
  for (let i = 0; i < count; i++) if (i % every === 0 || i === count - 1) out.push(i)
  return out
}

export const RANGES = [
  { key: 'day', label: 'Ngày', span: '30 ngày gần nhất' },
  { key: 'week', label: 'Tuần', span: '12 tuần gần nhất' },
  { key: 'month', label: 'Tháng', span: '12 tháng gần nhất' },
  { key: 'year', label: 'Năm', span: '5 năm gần nhất' },
]

/** Chart points from GET /admin/stats?range= series. */
export function seriesPoints(series, field) {
  return (series || []).map((d) => ({ date: d.date, value: d[field] || 0 }))
}
