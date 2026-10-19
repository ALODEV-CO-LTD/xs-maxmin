// Nhập kết quả - pure rules (no React, no network): prize forms, saving plans, OCR guess for Miền Bắc, and the
// automatic "Điểm ra" of every entry of the day. Port of the script part of views/ResultsView.vue.
import { effectiveConfig } from '../../lib/scoringConfig'
import { entryDetail } from '../../lib/scoringSummary'
import { entryStations, regionOf } from '../../lib/lotteryStations'

export const MB_COL = 'mb'
export const SINGLE_TIERS = ['dacBiet', 'giaiNhat'] // stored as one string, every other group is a list
export const isIsoDate = (s) => /^\d{4}-\d{2}-\d{2}$/.test(s || '')
export const viDay = (iso) => String(iso || '').split('-').reverse().join('/')

/** The day before / after `iso` (‹ ›). */
export function shiftDay(iso, delta) {
  const [y, m, d] = iso.split('-').map(Number)
  return new Date(Date.UTC(y, m - 1, d + delta)).toISOString().slice(0, 10)
}

export function blankForm(structure) {
  const f = {}
  for (const p of structure) f[p.tier] = SINGLE_TIERS.includes(p.tier) ? '' : Array(p.count).fill('')
  return f
}
/** A form for the region's structure, filled from `values` where they fit (a group may hold extra boxes: kept). */
export function shapeForm(structure, values) {
  const out = {}
  const blank = blankForm(structure)
  for (const p of structure) {
    const v = values?.[p.tier]
    out[p.tier] = SINGLE_TIERS.includes(p.tier) ? v || '' : Array.isArray(v) && v.length >= p.count ? [...v] : blank[p.tier]
  }
  return out
}
export const totalBoxes = (structure) => structure.reduce((n, p) => n + p.count, 0)
export const flatValues = (structure, form) => structure.flatMap((p) => [].concat(form?.[p.tier] ?? ''))
export const filledCount = (structure, form) => flatValues(structure, form).filter((v) => (v || '').trim()).length

/** The region's usual count of every group must be filled; boxes added beyond it are optional. */
export const requiredFilled = (structure, form) =>
  structure.every((p) => {
    const v = form?.[p.tier]
    return Array.isArray(v) ? v.slice(0, p.count).every((x) => (x || '').trim()) && v.length >= p.count : !!(v || '').trim()
  })
/** Empty extra boxes are dropped on save. */
export const valuesOf = (p, v) => (Array.isArray(v) ? v.map((x) => (x || '').trim()).filter((x, i) => i < p.count || x) : (v || '').trim())
/** Only digits, never more than the prize has. */
export const cleanDigits = (v, p) => String(v ?? '').replace(/\D/g, '').slice(0, p.digits)
/** A cell of the wrong length (an empty one only counts after a photo was read). */
export const cellBad = (p, v, flagEmpty) => {
  const t = (v || '').trim()
  return t ? t.length !== p.digits : !!flagEmpty
}

/** New form with one box changed (`index` null for the single boxes). */
export function setCell(form, p, index, value) {
  const v = cleanDigits(value, p)
  if (index === null || index === undefined) return { ...form, [p.tier]: v }
  const list = [...form[p.tier]]
  list[index] = v
  return { ...form, [p.tier]: list }
}
export const addCell = (form, p) => (Array.isArray(form[p.tier]) ? { ...form, [p.tier]: [...form[p.tier], ''] } : form)
export const removeCell = (form, p) => (Array.isArray(form[p.tier]) && form[p.tier].length > p.count ? { ...form, [p.tier]: form[p.tier].slice(0, -1) } : form)

/** Miền Bắc photo: words that are ALL digits are bucketed by length into the prize groups, filling only empty boxes. */
export function guessFromText(form, text) {
  const tokens = (String(text || '').match(/\S+/g) || []).filter((w) => /^\d+$/.test(w))
  const by = { 5: [], 4: [], 3: [], 2: [] }
  for (const t of tokens) if (by[t.length]) by[t.length].push(t)
  const f = { ...form, giaiNhi: [...form.giaiNhi], giaiBa: [...form.giaiBa], giaiTu: [...form.giaiTu], giaiNam: [...form.giaiNam], giaiSau: [...form.giaiSau], giaiBay: [...form.giaiBay] }
  const empty = (v) => !v?.trim()
  const five = by[5]
  let i = 0
  if (empty(f.dacBiet) && five[i]) f.dacBiet = five[i++]
  if (empty(f.giaiNhat) && five[i]) f.giaiNhat = five[i++]
  for (let k = 0; k < 2; k++) if (empty(f.giaiNhi[k]) && five[i]) f.giaiNhi[k] = five[i++]
  for (let k = 0; k < 6; k++) if (empty(f.giaiBa[k]) && five[i]) f.giaiBa[k] = five[i++]
  const four = by[4]
  let j = 0
  for (let k = 0; k < 4; k++) if (empty(f.giaiTu[k]) && four[j]) f.giaiTu[k] = four[j++]
  for (let k = 0; k < 6; k++) if (empty(f.giaiNam[k]) && four[j]) f.giaiNam[k] = four[j++]
  for (let k = 0; k < 3; k++) if (empty(f.giaiSau[k]) && by[3][k]) f.giaiSau[k] = by[3][k]
  for (let k = 0; k < 4; k++) if (empty(f.giaiBay[k]) && by[2][k]) f.giaiBay[k] = by[2][k]
  return f
}

// ---- columns (Miền Bắc = one column 'mb'; Miền Trung / Miền Nam = one column per station) -------------------------
/** Stations offered for a region/day: the ones drawing that day, the ones added by hand. */
export function stationChoices(scheduled, extra) {
  return [...scheduled, ...extra.filter((id) => !scheduled.includes(id))]
}
export const columnsOf = (region, choices) => (region === 'mb' ? [MB_COL] : choices)
/** Saved results of the day ({station: result}) -> state of every column. Extras = saved stations off the schedule. */
export function buildBoard({ structure, cols, results }) {
  const by = Object.fromEntries((results || []).map((r) => [r.station, r]))
  const forms = {}
  const saved = {}
  for (const c of cols) {
    forms[c] = shapeForm(structure, by[c])
    saved[c] = !!by[c]
  }
  return { by, forms, saved }
}
export function extraStationsOf(results, region, scheduled, regionIdOf) {
  return (results || []).map((r) => r.station).filter((id) => id !== MB_COL && regionIdOf(id) === region && !scheduled.includes(id))
}

/** What "Lưu kết quả" sends: { error } or { bodies: [{ col, body }], message(nameOf) }. */
export function planSave({ region, cols, forms, structure, date, nameOf }) {
  const total = totalBoxes(structure)
  const bodyOf = (col) => {
    const body = { drawDate: date, station: col }
    for (const p of structure) body[p.tier] = valuesOf(p, forms[col][p.tier])
    return body
  }
  if (region === 'mb') {
    if (!requiredFilled(structure, forms[MB_COL])) return { error: `Vui lòng nhập đủ ${total} số trước khi lưu.` }
    return { bodies: [{ col: MB_COL, body: bodyOf(MB_COL) }], message: `Đã lưu kết quả xổ số ${regionOf('mb').name} ngày ${date}.` }
  }
  const todo = cols.filter((c) => filledCount(structure, forms[c]) > 0)
  if (!todo.length) return { error: 'Chưa có số nào để lưu.' }
  const partial = todo.filter((c) => !requiredFilled(structure, forms[c]))
  if (partial.length) return { error: `${partial.map(nameOf).join(', ')}: chưa nhập đủ ${total} số. Điền đủ hoặc xoá hết cột đó rồi lưu lại.` }
  return { bodies: todo.map((col) => ({ col, body: bodyOf(col) })), message: `Đã lưu kết quả ${todo.map(nameOf).join(', ')} ngày ${viDay(date)}.` }
}

// ---- Điểm ra ----------------------------------------------------------------------------------------------------
export function toNumber(str) {
  if (!str) return 0
  const n = parseFloat(String(str).replace(/[^\d.-]/g, ''))
  return Number.isFinite(n) ? n : 0
}
/** Points out of one entry over the results of the stations it counts for (sum); null when none of them has a result yet. */
export function scoreFromResults(entry, byStation, { customers, rates }) {
  const cust = customers.find((c) => c.name === entry.customerName)
  const done = entryStations(entry).filter((st) => byStation[st])
  if (!done.length) return null
  return done.reduce((sum, st) => {
    const region = regionOf(st).id
    return sum + entryDetail(entry, byStation[st], effectiveConfig(rates, cust?.scoringRates, entry.betType, region), { region, customerRegion: cust?.homeRegion || null }).out
  }, 0)
}
/** Entries of `date` whose stored "Điểm ra" differs from the calculated one: [{ e, value, prev }] and the ones that overwrite a different number. */
export function planScoreSync(entries, date, byStation, ctx) {
  const changes = []
  for (const e of entries) {
    if (e.entryDate !== date) continue
    const v = scoreFromResults(e, byStation, ctx)
    if (v === null || String(v) === (e.result || '')) continue
    changes.push({ e, value: String(v), prev: e.result || '' })
  }
  const overwrites = changes.filter((c) => c.prev !== '' && toNumber(c.prev) !== toNumber(c.value))
  return { changes, overwrites }
}
