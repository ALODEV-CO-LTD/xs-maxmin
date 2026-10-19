// Pure aggregation for Tài khoản > Thống kê (shared logic with the app).
// entries: [{ entryDate: 'YYYY-MM-DD…', score, result }]. vào = score, ra = result, lợi nhuận = vào − ra.
// Dates are bucketed in local time; weeks are ISO weeks (Monday first).

export const SPAN = { day: 30, week: 12, month: 12, year: 5 }

export function toNumber(str) {
  if (!str) return 0
  const n = parseFloat(String(str).replace(/[^\d.-]/g, ''))
  return Number.isFinite(n) ? n : 0
}

const pad = (n) => String(n).padStart(2, '0')
const dayKey = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
const parseDay = (s) => new Date(+s.slice(0, 4), +s.slice(5, 7) - 1, +s.slice(8, 10))
const mondayOf = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate() - ((d.getDay() + 6) % 7))

export function isoWeek(d) {
  const t = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 3 - ((d.getDay() + 6) % 7)) // Thursday of this week
  const jan4 = new Date(t.getFullYear(), 0, 4)
  return { year: t.getFullYear(), week: 1 + Math.round(((t - jan4) / 86400000 - 3 + ((jan4.getDay() + 6) % 7)) / 7) }
}

function keyOf(dateStr, unit) {
  const s = String(dateStr || '').slice(0, 10)
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return null
  if (unit === 'day') return s
  if (unit === 'week') return dayKey(mondayOf(parseDay(s)))
  if (unit === 'month') return s.slice(0, 7)
  return s.slice(0, 4)
}

function periodKeys(unit, now, count) {
  const out = []
  for (let i = count - 1; i >= 0; i--) {
    if (unit === 'day') out.push(dayKey(new Date(now.getFullYear(), now.getMonth(), now.getDate() - i)))
    else if (unit === 'week') out.push(dayKey(mondayOf(new Date(now.getFullYear(), now.getMonth(), now.getDate() - 7 * i))))
    else if (unit === 'month') {
      const d = new Date(now.getFullYear(), now.getMonth() - i, 1)
      out.push(`${d.getFullYear()}-${pad(d.getMonth() + 1)}`)
    } else out.push(String(now.getFullYear() - i))
  }
  return out
}

export function labelOf(k, unit) {
  if (unit === 'day' || unit === 'week') return `${k.slice(8, 10)}/${k.slice(5, 7)}`
  if (unit === 'month') return `${k.slice(5, 7)}/${k.slice(2, 4)}`
  return k
}
export function fullLabelOf(k, unit) {
  if (unit === 'day') return `${k.slice(8, 10)}/${k.slice(5, 7)}/${k.slice(0, 4)}`
  if (unit === 'week') {
    const mon = parseDay(k)
    const sun = new Date(mon.getFullYear(), mon.getMonth(), mon.getDate() + 6)
    const f = (d) => `${pad(d.getDate())}/${pad(d.getMonth() + 1)}`
    return `Tuần ${isoWeek(mon).week} (${f(mon)} – ${f(sun)}/${sun.getFullYear()})`
  }
  if (unit === 'month') return `Tháng ${k.slice(5, 7)}/${k.slice(0, 4)}`
  return `Năm ${k}`
}

function collect(entries, unit, now, count) {
  const keys = periodKeys(unit, now, count)
  const acc = new Map(keys.map((k) => [k, { vao: 0, ra: 0 }]))
  for (const e of entries || []) {
    const b = acc.get(keyOf(e.entryDate, unit))
    if (!b) continue
    b.vao += toNumber(e.score)
    b.ra += toNumber(e.result)
  }
  return keys.map((k) => ({ key: k, ...acc.get(k) }))
}

const pick = (b, metric) => (metric === 'profit' ? b.vao - b.ra : b[metric])

export function buildSeries(entries, { unit = 'day', metric = 'profit', now = new Date() } = {}) {
  return collect(entries, unit, now, SPAN[unit]).map((b) => ({
    key: b.key,
    label: labelOf(b.key, unit),
    full: fullLabelOf(b.key, unit),
    value: pick(b, metric),
  }))
}

// Total of the visible range and of the equally long range right before it.
export function rangeTotals(entries, { unit = 'day', metric = 'profit', now = new Date() } = {}) {
  const n = SPAN[unit]
  const all = collect(entries, unit, now, n * 2)
  const sum = (list) => list.reduce((a, b) => a + pick(b, metric), 0)
  const prev = all.slice(0, n)
  const hasPrev = prev.some((b) => b.vao || b.ra)
  return { current: sum(all.slice(n)), previous: hasPrev ? sum(prev) : null }
}

// Show a label every k bars so labels (~minPx wide) never collide.
export function tickEvery(count, width, minPx = 46) {
  const fit = Math.max(1, Math.floor(width / minPx))
  return Math.max(1, Math.ceil(count / fit))
}
// Indices to label: always first and last, the rest spaced by `every`.
export function tickIndices(count, every) {
  if (count <= 0) return []
  const set = new Set([0, count - 1])
  for (let i = every; i < count - 1; i += every) if (count - 1 - i >= every) set.add(i)
  return [...set].sort((a, b) => a - b)
}

// 1500 -> 1,5k · 2 500 000 -> 2,5tr · 3e9 -> 3 tỷ; negatives keep the sign.
export function compactNumber(n) {
  const a = Math.abs(n)
  const f = (v) => String(+v.toFixed(1)).replace('.', ',')
  const sign = n < 0 ? '-' : ''
  if (a >= 1e9) return `${sign}${f(a / 1e9)} tỷ`
  if (a >= 1e6) return `${sign}${f(a / 1e6)}tr`
  if (a >= 1e3) return `${sign}${f(a / 1e3)}k`
  return `${sign}${Math.round(a)}`
}
