// Nhập số - pure rules (no React, no network), so they can be tested on their own. Behaviour follows the NEW Vue/app
// screen: only "Điểm vào" is typed here, the day is always today, no search / filter / copy / row-delete selection.
import { betTypeLabel } from '../../lib/betTypes'
import { customerBetTypes, typesOf } from '../../lib/scoringConfig'
import { createEntry as createEntryOnline } from '../../lib/offline'

let seq = 0
export const nextUid = () => ++seq

/** A number-like text gets a plain "." decimal point (see app/lib/core/number_text.dart); anything else is unchanged. */
export function normalizeNumberText(s) {
  if (!s.includes(',')) return s
  const t = s.trim()
  if (!/^-?[\d.,\s]+$/.test(t)) return s
  const last = t.lastIndexOf(',')
  const tail = t.slice(last + 1)
  const head = t.slice(0, last)
  if (t.lastIndexOf('.') > last) return t.replaceAll(',', '') // "1,234.5": comma = thousands
  const headDigits = head.replace(/[^\d]/g, '')
  const zeroHead = headDigits.replace(/^0+/, '') === ''
  const decimal = /^\d{1,2}$/.test(tail) || (/^\d+$/.test(tail) && zeroHead)
  if (decimal) return `${head.trimStart().startsWith('-') ? '-' : ''}${headDigits || '0'}.${tail}`
  return t.replaceAll(',', '')
}

/** Lenient number: strips everything but digits / minus / dot; unreadable counts as 0. */
export function toNumber(str) {
  if (!str) return 0
  const n = parseFloat(String(str).replace(/[^\d.-]/g, ''))
  return Number.isFinite(n) ? n : 0
}

/** Points are free text; plain numbers get thousands separators (vi-VN), anything else is shown as typed. */
export function fmtPoints(v) {
  const t = String(v ?? '').trim()
  if (!t) return '-'
  return /^-?\d+(\.\d+)?$/.test(t) ? Number(t).toLocaleString('vi-VN') : t
}
export const formatNumber = (n) => new Intl.NumberFormat('vi-VN').format(n)

export function totalsOf(entries) {
  let vao = 0
  let ra = 0
  for (const e of entries) {
    vao += toNumber(e.score)
    ra += toNumber(e.result)
  }
  return { vao, ra, chenhLech: vao - ra }
}

// ---- rows of the manual list -------------------------------------------------------------------------------------
export const blankRow = (type = 'de') => ({ uid: nextUid(), type, value: '', score: '' })
export const rowBlank = (r) => !r.value.trim() && !String(r.score ?? '').trim()
export const rowComplete = (r) => !!(r.type && r.value.trim() && String(r.score ?? '').trim())

/** Keeps every row on a hạng mục the customer / đài still offers. Returns the same array when nothing changes. */
export function fixRowTypes(rows, types) {
  if (!types.length || rows.every((r) => types.includes(r.type))) return rows
  return rows.map((r) => (types.includes(r.type) ? r : { ...r, type: types[0] }))
}

/** The hạng mục offered: the account's, minus those switched off for the customer, plus the customer's own. */
export function betTypesFor(accountRates, customerRates, regionId) {
  const list = customerBetTypes(accountRates, customerRates, regionId)
  return list.length ? list : typesOf(accountRates)
}

/** Rows read from a message / photo go under the manual rows (replacing them while those are all blank). */
export function mergeRows(rows, fresh) {
  return rows.every(rowBlank) ? fresh : [...rows, ...fresh]
}

/** OCR found no "loại số x điểm" pattern: every 2-4 digit group becomes a row (no score) to be checked by hand. */
export function ocrGuessRows(text, type) {
  return (String(text || '').match(/\d{2,4}/g) || []).map((n) => ({ ...blankRow(type), value: n }))
}

// ---- saving ------------------------------------------------------------------------------------------------------
export function entryPayload({ customerName, type, value, score, station, note, date }) {
  const s = String(score ?? '').trim()
  const n = String(note ?? '').trim()
  const out = { customerName: customerName.trim(), value: value.trim(), entryDate: date, betType: type, station }
  if (s) out.score = normalizeNumberText(s)
  if (n) out.note = n
  return out
}

/** Validates the manual rows: returns { error } or { started } (the rows to save). */
export function checkRows(customerName, rows) {
  const started = rows.filter((r) => !rowBlank(r))
  if (!customerName.trim() || !started.length) return { error: 'Nhập ít nhất một số' }
  if (!started.every(rowComplete)) return { error: 'Nhập đủ Hạng mục, Số và Điểm vào' }
  return { started }
}

/** Saves items one by one (a failure of one never loses the others). `create` = offline.createEntry by default.
 *  Resolves { saved: [{ item, entry, queued }], failed: ['Đề "12": message'] }. */
export async function saveItems(items, makePayload, create = createEntryOnline) {
  const saved = []
  const failed = []
  for (const item of items) {
    try {
      const res = await create(makePayload(item))
      saved.push({ item, entry: res.entry, queued: !!res.queued })
    } catch (err) {
      failed.push(`${betTypeLabel(item.type)} "${item.value}": ${err?.message || 'lỗi không rõ'}`)
    }
  }
  return { saved, failed }
}

export const queuedNotice = (n) => `Đang offline: ${n} số liệu đã lưu trên máy, sẽ tự đồng bộ khi có mạng.`
export const addedText = (n, customer, queued) => `Đã thêm ${n} số liệu cho ${customer.trim()}${queued ? ' (đang offline, sẽ tự đồng bộ)' : ''}.`

// ---- the list ----------------------------------------------------------------------------------------------------
/** The chosen customer's entries of today on the chosen đài (an entry with no đài belongs to Miền Bắc). */
export function listFor(entries, { customerName, date, station }) {
  if (!customerName) return []
  return entries.filter((e) => e.customerName === customerName && e.entryDate === date && (!station || (e.station || 'mb') === station))
}
export const customerEntries = (entries, customerName) => (customerName ? entries.filter((e) => e.customerName === customerName) : [])
export const entryCount = (entries, name) => entries.filter((e) => e.customerName === name).length

/** dd/MM/yyyy of a yyyy-MM-dd date. */
export function viDate(iso) {
  const p = String(iso || '').split('-')
  return p.length === 3 ? `${p[2]}/${p[1]}/${p[0]}` : String(iso || '')
}

export function emptyListText({ customerName, entries, date }) {
  return customerEntries(entries, customerName).length ? `Chưa có số liệu ngày ${viDate(date)} (đài này).` : 'Khách hàng này chưa có số liệu nào.'
}

/** Changes sent when an entry is edited: số, điểm vào, ghi chú only (customer / hạng mục / ngày stay as they were). */
export function editChanges(entry, { value, score, note }) {
  return {
    customerName: (entry.customerName || '').trim(),
    value: value.trim(),
    entryDate: entry.entryDate,
    score: normalizeNumberText(score.trim()),
    betType: entry.betType || 'de',
    note: note.trim(),
  }
}
export function editError({ value }) {
  return value.trim() ? '' : 'Vui lòng nhập số liệu'
}

/** Bulk edit of the ticked rows: only the filled fields (hạng mục / điểm vào) change. Returns null when nothing to apply. */
export function bulkPatch(type, score) {
  const patch = {}
  if (type) patch.type = type
  if (String(score ?? '').trim() !== '') patch.score = String(score).trim()
  return Object.keys(patch).length ? patch : null
}
