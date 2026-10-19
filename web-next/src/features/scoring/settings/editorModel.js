// Logic thuần của ScoringConfigEditor (bản Vue: components/ScoringConfigEditor.vue). Không có React ở đây: mọi hàm nhận
// ngữ cảnh `ctx = { isCustomer, base, customerName }` và trạng thái `st = { work, rows, region }` rồi trả về giá trị mới,
// để test được bằng node. `work` = bảng đang sửa (map: `type` mọi miền, `type@mb|mt|mn` riêng miền, `{disabled:true}` = bỏ).
import { betTypeLabel } from '../../../lib/betTypes'
import {
  baseKey, defaultRow, defaultSource, defaultSymbols, describeSource, effectiveSource, kindSource, normalizeSource, sameSource,
  sourceFields, makeRow, parseSymbols, regionKey, sameConfig, symbolsText, TABLE_GROUPS, TABLE_KINDS, TABLE_KIND_KEYS,
  LEGACY_TYPE_ALIAS, toTableRow, typesIn, DEFAULT_RATES,
} from '../../../lib/scoringConfig'

// Cùng giá trị với REGION_IDS của lotteryStations.js (không import để test không cần tải danh mục đài).
export const REGIONS = ['mb', 'mt', 'mn']
export const REGION_NAMES = { mb: 'Miền Bắc', mt: 'Miền Trung', mn: 'Miền Nam' }

const nf = new Intl.NumberFormat('vi-VN')
export const fmt = (v) => nf.format(Number(v) || 0)

const clone = (o) => JSON.parse(JSON.stringify(o))
const byKey = (o) => Object.fromEntries(Object.entries(o).sort(([a], [b]) => a.localeCompare(b)))
export const sorted = (o) => byKey(Object.fromEntries(Object.entries(o).map(([k, v]) => [k, v.disabled ? v : byKey({ ...v, tiers: [...(v.tiers || [])].sort() })])))

/** Bảng đang sửa từ map đã lưu (dòng bỏ chỉ giữ `{ disabled: true }`). */
export function loadWork(map) {
  const work = {}
  for (const [k, v] of Object.entries(map || {})) work[k] = v.disabled ? { disabled: true } : clone(v)
  return work
}
export const initialOf = (work) => JSON.stringify(sorted(work))

export const GROUPS = [...TABLE_GROUPS, { id: 'other', label: 'Kiểu đánh khác' }]
export const GROUP_IDS = GROUPS.map((g) => g.id)
const ALL_PRIZES = ['dacBiet', 'giaiNhat', 'giaiNhi', 'giaiBa', 'giaiTu', 'giaiNam', 'giaiSau', 'giaiBay']
export const tiersOfScope = (scope) => (scope === 'all' ? [...ALL_PRIZES] : ['dacBiet'])

// ---- rows of the active region ---------------------------------------------------------------------------------------
// What a row follows when it has no region-only value of its own.
export function inheritedRow(ctx, work, region, type) {
  if (!ctx.isCustomer) {
    const v = work[type]
    return v && !v.disabled ? toTableRow(type, v) : null
  }
  const own = work[type]
  if (own && !own.disabled) return toTableRow(type, own)
  const b = ctx.base[regionKey(type, region)] ?? ctx.base[type]
  return b ? toTableRow(type, b) : null
}
// The row as shown: the region's own value, else what it inherits, else the built-in default of a standard kind.
export function shownRow(ctx, work, region, type) {
  const regional = work[regionKey(type, region)]
  if (regional && !regional.disabled) return toTableRow(type, regional)
  return inheritedRow(ctx, work, region, type) ?? (TABLE_KIND_KEYS.includes(type) ? defaultRow(type, region) : null)
}
export function extraTypes(ctx, work, region) {
  const keys = new Set(typesIn(work, region))
  if (ctx.isCustomer) for (const k of typesIn(ctx.base, region)) keys.add(k)
  return [...keys].filter((k) => !TABLE_KIND_KEYS.includes(k) && !LEGACY_TYPE_ALIAS[k])
}
// A standard row removed from the table: by the account (default scope), or by the account for every customer.
export const removed = (ctx, work, region, kind) => !!(work[regionKey(kind, region)]?.disabled && !ctx.isCustomer) || !!ctx.base[regionKey(kind, region)]?.disabled

// The "lấy số" of a row as edited: prizes, end of the number (đầu / cuối), digits, and the lô of each prize as text ("1,2").
export const srcState = (src) => ({ srcTiers: [...src.tiers], srcPos: src.position, srcDigits: src.digits, srcPick: (src.pick || []).join(',') })
export const srcOf = (r) => normalizeSource({ tiers: r.srcTiers, position: r.srcPos, digits: r.srcDigits, pick: String(r.srcPick || '').split(/[,;\s]+/).filter(Boolean) })
export const kindOf = (r) => (r.extra ? 'custom' : r.type)
// Different from what the kind reads by default (so only then it is stored).
export const srcChanged = (r, region) => !r.extra && !sameSource(srcOf(r), defaultSource(r.type, region))
export const srcCaption = (r, region) => (!r.extra && !srcChanged(r, region) ? kindSource(r.type, region) : describeSource(srcOf(r), region))
export const fieldsOf = (r) => sourceFields(kindOf(r))
export const resetSrcPatch = (r, region) => srcState(r.extra ? { tiers: ['dacBiet'], position: 'last', digits: 2 } : defaultSource(r.type, region))

export function buildRows(ctx, work, region) {
  const rows = []
  const std = TABLE_KINDS.filter((k) => !removed(ctx, work, region, k.kind)).map((k) => ({ type: k.kind, group: k.group, label: k.label, symbols: k.symbols, editable: !!k.editable, extra: false }))
  const extra = extraTypes(ctx, work, region).map((t) => {
    const cfg = toTableRow(t, work[regionKey(t, region)] ?? work[t] ?? ctx.base[regionKey(t, region)] ?? ctx.base[t])
    return { type: t, label: cfg?.name || betTypeLabel(t), symbols: t, group: GROUP_IDS.includes(cfg?.group) ? cfg.group : 'other', extra: true }
  })
  for (const meta of [...std, ...extra]) {
    const cfg = shownRow(ctx, work, region, meta.type) || defaultRow('lo', region)
    const offHere = ctx.isCustomer && (work[meta.type]?.disabled || work[regionKey(meta.type, region)]?.disabled)
    rows.push({
      ...meta,
      kind: cfg.kind,
      price: String(cfg.price),
      payout: String(cfg.payout),
      tiers: [...(cfg.tiers || ['dacBiet'])],
      digits: cfg.digits || 2,
      name: cfg.name || meta.label,
      ...srcState(effectiveSource(cfg, cfg.kind, region)),
      srcOpen: false,
      symbolsInput: meta.editable ? symbolsText(cfg.symbols?.length ? cfg.symbols : defaultSymbols(meta.type)) : '',
      off: !!offHere,
    })
  }
  return rows
}

// The ký hiệu a row stores: only when the customer changed them from the built-in spellings.
export function ownSymbols(r) {
  if (!r.editable) return undefined
  const list = parseSymbols(r.symbolsInput)
  return list.join(',') === defaultSymbols(r.type).join(',') ? undefined : list
}
export const symbolText = (r) => (r.editable ? symbolsText(parseSymbols(r.symbolsInput).length ? parseSymbols(r.symbolsInput) : defaultSymbols(r.type)) : r.symbols)

/** Rows grouped for the table. While editing every group shows (even empty) so a cách đánh can be added to it. */
export const groupsOf = (rows, editing) => GROUPS.map((g) => ({ ...g, rows: rows.filter((r) => r.group === g.id) })).filter((g) => g.rows.length || editing)

export const cfgOf = (r, region) =>
  makeRow({
    kind: r.extra ? 'custom' : r.type,
    price: Number(r.price),
    payout: Number(r.payout),
    source: r.extra || srcChanged(r, region) ? srcOf(r) : undefined,
    name: r.extra && r.name && r.name !== betTypeLabel(r.type) ? r.name : undefined,
    group: r.extra && r.group !== 'other' ? r.group : undefined,
    symbols: ownSymbols(r),
  })

// Writes the rows of the active region into `target`: a row that differs from what it follows becomes a region-only
// value, one that equals it drops its region-only value. (What a row follows is read from st.work.)
export function commitInto(ctx, st, target) {
  const { rows, region, work } = st
  for (const r of rows) {
    if (r.off) continue
    const key = regionKey(r.type, region)
    const cfg = cfgOf(r, region)
    const baseCfg = inheritedRow(ctx, work, region, r.type)
    if (!baseCfg) target[key] = cfg // type made for this region only / standard kinds with nothing to inherit
    else if (sameConfig(cfg, baseCfg, r.type)) delete target[key]
    else target[key] = cfg
  }
}
/** A copy of st.work with the rows written back. */
export function committed(ctx, st) {
  const w = clone(st.work)
  commitInto(ctx, st, w)
  return w
}

export const differs = (ctx, st, r) => {
  const baseCfg = inheritedRow(ctx, st.work, st.region, r.type)
  return !!baseCfg && !sameConfig(cfgOf(r, st.region), baseCfg, r.type)
}
export const hasOwn = (ctx, st, r) => !r.off && (!!st.work[regionKey(r.type, st.region)] || differs(ctx, st, r))
export const tagOf = (ctx, st, r) => {
  if (r.off) return 'Không dùng'
  if (ctx.isCustomer) return hasOwn(ctx, st, r) ? 'Riêng' : 'Mặc định'
  return ''
}
// A row whose giá trúng is still 0 was not given by the doc (xiên, trượt, bao lô 3-4 số, tài/xỉu...): shown in red until filled.
export const notSet = (r) => !r.off && !r.extra && !(Number(r.payout) > 0)

// ---- validation -------------------------------------------------------------------------------------------------------
export function validate(st) {
  const { rows, region } = st
  for (const r of rows) {
    if (r.off) continue
    const price = Number(r.price)
    const payout = Number(r.payout)
    if (!Number.isFinite(price) || price <= 0) return `Giá tiền/1 điểm của "${r.label}" không hợp lệ`
    if (!Number.isFinite(payout) || payout < 0) return `Giá trúng/1 điểm của "${r.label}" không hợp lệ`
  }
  for (const r of rows) {
    if (r.off) continue
    if (r.extra || srcChanged(r, region)) {
      if (!r.srcTiers.length) return `"${r.label}": chọn ít nhất một giải để lấy số`
      if (!(Number(r.srcDigits) >= 1 && Number(r.srcDigits) <= 6)) return `"${r.label}": số chữ số từ 1 đến 6`
    }
  }
  const seen = new Map()
  for (const r of rows) {
    if (!r.editable || r.off) continue
    const list = parseSymbols(r.symbolsInput)
    for (const sym of list) {
      if (!/^[\p{L}×]{1,12}$/u.test(sym)) return `Ký hiệu "${sym}" của "${r.label}" chỉ được gồm chữ cái (tối đa 12 ký tự)`
      const k = sym.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/gi, 'd').toLowerCase()
      if (seen.has(k) && seen.get(k) !== r.type) return `Ký hiệu "${sym}" đang dùng cho cả "${rows.find((x) => x.type === seen.get(k))?.label}" và "${r.label}"`
      seen.set(k, r.type)
    }
  }
  return ''
}

// Default scope: every standard kind of every region gets a value (a legacy account only had Đề / Lô), so an entry of
// any kind is always scored with a real row.
export function fillMissing(target) {
  for (const r of REGIONS) for (const kind of TABLE_KIND_KEYS) if (!target[regionKey(kind, r)] && !target[kind]) target[regionKey(kind, r)] = defaultRow(kind, r)
}

export function isDirty(ctx, st, initial) {
  const copy = clone(st.work)
  commitInto(ctx, st, copy)
  return JSON.stringify(sorted(copy)) !== initial
}

// ---- transitions: each returns the new `st` (and, where it can fail, `{ error }`) --------------------------------------
export function newState(ctx, work, region) {
  return { work, region, rows: buildRows(ctx, work, region) }
}
export function switchRegion(ctx, st, id) {
  const problem = validate(st)
  if (problem) return { error: problem, st }
  const work = committed(ctx, st)
  return { error: '', st: newState(ctx, work, id) }
}
export function resetRow(ctx, st, r) {
  const work = clone(st.work)
  delete work[regionKey(r.type, st.region)]
  return newState(ctx, work, st.region)
}
export function toggleOff(ctx, st, r) {
  const work = committed(ctx, st)
  if (r.off) {
    if (work[r.type]?.disabled) delete work[r.type]
    delete work[regionKey(r.type, st.region)]
  } else {
    work[regionKey(r.type, st.region)] = { disabled: true }
  }
  return newState(ctx, work, st.region)
}
export const removeMessage = (ctx, region, r) =>
  `Xoá "${r.label}" khỏi bảng ${REGION_NAMES[region]}${ctx.isCustomer ? ` của ${ctx.customerName}` : ''}? Số liệu đã nhập với cách này vẫn được giữ và tính theo cấu hình mặc định. Bạn có thể thêm lại bằng "+ Thêm". Bấm Lưu để áp dụng.`
// (the confirmation is asked by the caller)
export function removeRow(ctx, st, r) {
  const work = committed(ctx, st)
  if (!r.extra) {
    // A standard row is not deleted but marked removed ({ disabled: true }) so it does not come back as a default.
    work[regionKey(r.type, st.region)] = { disabled: true }
  } else {
    for (const k of Object.keys(work)) if (baseKey(k) === r.type && (k === r.type || k === regionKey(r.type, st.region))) delete work[k]
  }
  return newState(ctx, work, st.region)
}

// ---- "Kiểu đánh khác": a name, a symbol, what it is compared with ----------------------------------------------------
export const emptyAddForm = () => ({ open: false, group: 'other', pick: 'new', name: '', symbol: '', tiers: 'special', digits: 2, price: '12600', payout: '70000', error: '' })
// Standard rows of a group that were removed and can be put back.
export const restorable = (ctx, st, group) => TABLE_KINDS.filter((k) => k.group === group && removed(ctx, st.work, st.region, k.kind) && !(ctx.isCustomer && ctx.base[regionKey(k.kind, st.region)]?.disabled))
export function openAddForm(ctx, st, group) {
  const back = restorable(ctx, st, group)
  return { ...emptyAddForm(), open: true, group, pick: back.length ? back[0].kind : 'new' }
}
/** Returns `{ error, st }` or, when added / restored, `{ error: '', st, closed: true }`. */
export function addRow(ctx, st, form) {
  const work = committed(ctx, st)
  const stc = { ...st, work } // work with the rows written back, rows untouched (as the Vue code did before validating)
  if (form.pick !== 'new') {
    delete work[regionKey(form.pick, st.region)] // back to what it follows / the built-in default
    return { error: '', st: newState(ctx, work, st.region), closed: true }
  }
  const symbol = form.symbol.trim().toLowerCase()
  if (!/^[a-z0-9]{1,12}$/.test(symbol)) return { error: 'Ký hiệu chỉ gồm chữ không dấu hoặc số (tối đa 12 ký tự)', st: stc }
  if (TABLE_KIND_KEYS.includes(symbol) || st.rows.some((r) => r.type === symbol)) return { error: 'Ký hiệu này đã có', st: stc }
  if (!(Number(form.price) > 0) || !(Number(form.payout) >= 0)) return { error: 'Giá tiền phải lớn hơn 0, giá trúng không âm', st: stc }
  work[regionKey(symbol, st.region)] = makeRow({
    kind: 'custom',
    price: Number(form.price),
    payout: Number(form.payout),
    source: { tiers: tiersOfScope(form.tiers), position: 'last', digits: Number(form.digits) || 2 },
    name: form.name.trim() || undefined,
    group: form.group,
  })
  return { error: '', st: newState(ctx, work, st.region), closed: true }
}

// ---- save ------------------------------------------------------------------------------------------------------------
/** `{ error }` or `{ st, map }`: rows committed (and, for the default scope, every standard kind filled in). */
export function prepareSave(ctx, st) {
  const problem = validate(st)
  if (problem) return { error: problem }
  const work = committed(ctx, st)
  if (!ctx.isCustomer) fillMissing(work)
  const map = clone(work)
  if (!ctx.isCustomer && !Object.keys(map).length) return { error: 'Cần ít nhất một kiểu đánh' }
  return { error: '', work, map }
}
export const resetAllWork = (ctx) => (ctx.isCustomer ? loadWork({}) : loadWork(DEFAULT_RATES))
export const overrideCount = (work) => Object.keys(work).filter((k) => work[k]?.disabled || k.includes('@')).length
export const regionHasOverride = (ctx, work, id) => ctx.isCustomer && Object.keys(work).some((k) => k.endsWith(`@${id}`))
export const savedNotice = (ctx, rates) => (ctx.isCustomer ? (rates ? `Đã lưu cấu hình riêng cho ${ctx.customerName}` : `${ctx.customerName} đang dùng cấu hình mặc định`) : 'Đã lưu cấu hình mặc định')
export const rowsOfGroup = (rows, id) => rows.filter((r) => r.group === id)
export const noteOf = (ctx, work) => (!ctx.isCustomer ? '' : overrideCount(work) ? `${overrideCount(work)} mục riêng` : 'Đang dùng cấu hình mặc định')
