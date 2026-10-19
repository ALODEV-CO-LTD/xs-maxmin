// Which payout config applies to an entry: the customer's own override for that bet type if
// they have one, else the account-wide setting (Cấu hình mặc định), else the built-in Đề.
//
// "Bảng cấu hình" (customer's doc): one row per kiểu đánh, per region: Kiểu đánh - Ký hiệu - Giá tiền/1 điểm -
// Giá trúng/1 điểm. A row is { kind, price, payout, ... }:
//   price   = đồng the customer pays per điểm      (tiền xác = điểm × price)
//   payout  = đồng the customer wins per điểm hit  (tiền trúng = số lần trúng × điểm × payout)
// `kind` fixes how a number is matched (lo = bao lô, dau, duoi, cang3, cang4, xien2/3/4); kind 'custom' (and the
// older rows without a kind) match by `tiers` + `digits`. Every row also carries the older fields (rate = payout /
// price, unit 'point', pointValue = price) so code that only knows those still gets the same single-lot money.
// Mỗi NHÓM là một kiểu đánh (Lô, Đề, Xiên, Lô trượt, Thần tài); trong nhóm có nhiều CÁCH đánh, mỗi cách một dòng giá riêng,
// theo từng miền (Miền Bắc 27 lô; Miền Nam / Miền Trung 18 lô: số lô, giải nào "lấy số" và giá đều khác nhau, xem `kindSource`).
// Xiên quay và các kiểu khác chưa có công thức.
export const TABLE_GROUPS = [
  { id: 'lo', label: 'Lô' },
  { id: 'de', label: 'Đề' },
  { id: 'xien', label: 'Xiên' },
  { id: 'truot', label: 'Lô trượt' },
  { id: 'thantai', label: 'Thần tài (tài/xỉu, chẵn/lẻ)' },
]
export const TABLE_KINDS = [
  { kind: 'lo', group: 'lo', label: 'Bao lô 2 số', symbols: 'L, l, lo, lô, x, X', editable: true },
  { kind: 'lo3', group: 'lo', label: 'Bao lô 3 số', symbols: 'chọn ở ô Hạng mục khi nhập số' },
  { kind: 'lo4', group: 'lo', label: 'Bao lô 4 số', symbols: 'chọn ở ô Hạng mục khi nhập số' },
  { kind: 'dau', group: 'de', label: 'Đầu', symbols: 'Đ, D, đ, dau, đầu', editable: true },
  { kind: 'duoi', group: 'de', label: 'Đuôi', symbols: 'C, c, cuoi, cuối', editable: true },
  { kind: 'cang3', group: 'de', label: '3 càng', symbols: '3 số + x / lo + điểm, vd 123x10' },
  { kind: 'cang4', group: 'de', label: '4 càng', symbols: '4 số + x / lo + điểm, vd 5000x100' },
  { kind: 'xien2', group: 'xien', label: 'Xiên 2', symbols: 'vd 20.02x10, 20x02lo10' },
  { kind: 'xien3', group: 'xien', label: 'Xiên 3', symbols: 'như xiên 2, 3 cặp số' },
  { kind: 'xien4', group: 'xien', label: 'Xiên 4', symbols: 'như xiên 2, 4 cặp số' },
  { kind: 'truot4', group: 'truot', label: 'Trượt xiên 4', symbols: 'chọn ở ô Hạng mục, 4 cặp số' },
  { kind: 'truot8', group: 'truot', label: 'Trượt xiên 8', symbols: 'chọn ở ô Hạng mục, 8 cặp số' },
  { kind: 'truot10', group: 'truot', label: 'Trượt xiên 10', symbols: 'chọn ở ô Hạng mục, 10 cặp số' },
  { kind: 'tai_xiu', group: 'thantai', label: 'Tài / Xỉu', symbols: 'nhập "tai" hoặc "xiu" (chọn ở ô Hạng mục)' },
  { kind: 'chan_le', group: 'thantai', label: 'Chẵn / Lẻ', symbols: 'nhập "chan" hoặc "le" (chọn ở ô Hạng mục)' },
]
export const TABLE_KIND_KEYS = TABLE_KINDS.map((k) => k.kind)
export const isTableKind = (k) => TABLE_KIND_KEYS.includes(k)
// Ký hiệu of a row as the customer typed them ("L, l, lo"): a list. Only lo / dau / duoi have symbols of their own (the other
// kinds are written with a number pattern); the message parser reads them (messageParser.js, `kindSymbols`).
export const parseSymbols = (text) => [...new Set(String(text || '').split(/[,;\s]+/).map((x) => x.trim()).filter(Boolean))].slice(0, 12)
export const symbolsText = (list) => (list || []).join(', ')
export const defaultSymbols = (kind) => parseSymbols(TABLE_KINDS.find((k) => k.kind === kind)?.symbols)
const ALL_TIERS = ['dacBiet', 'giaiNhat', 'giaiNhi', 'giaiBa', 'giaiTu', 'giaiNam', 'giaiSau', 'giaiBay']

// Kinds that look at every prize of the day (the rest look at the special prize, or the eighth / first / seventh).
const isAllPrizeKind = (kind) => ['lo', 'lo3', 'lo4'].includes(kind) || kind.startsWith('xien') || kind.startsWith('truot')

// A full row from its essentials.
export function makeRow({ kind, price, payout, tiers, digits, name, symbols, group, source }) {
  const p = Number(price)
  const w = Number(payout)
  const row = {
    kind,
    price: p,
    payout: w,
    rate: p > 0 ? w / p : 0,
    tiers: tiers || (isAllPrizeKind(kind) ? [...ALL_TIERS] : ['dacBiet']),
    digits: digits || ({ cang3: 3, lo3: 3, cang4: 4, lo4: 4 }[kind] ?? 2),
    unit: 'point',
    pointValue: p,
  }
  if (name) row.name = name
  if (group) row.group = group
  if (source) {
    // Lấy số set by the customer: giải nào, vị trí (đầu / cuối), bao nhiêu số, lô thứ mấy. tiers / digits mirror it for older code.
    row.source = normalizeSource(source)
    row.tiers = [...row.source.tiers]
    row.digits = row.source.digits
  }
  if (symbols?.length) row.symbols = [...symbols]
  return row
}

// Defaults from the doc: Nam/Trung bao lô 12.600 / 70.000, đầu và đuôi 1.000 / 70.000, 3 càng 12.600 / 500.000; Bắc bao lô
// 21.600. 4 càng is a placeholder and xiên payout 0 = "chưa nhập" (the doc gives none). Keep in step with
// backend/lib/src/scoring_rates.dart (defaultTableRates) and app/lib/core/scoring_config.dart.
export function defaultRow(kind, region = 'mb') {
  const mb = region === 'mb'
  const loPrice = mb ? 21600 : 12600
  // Bao lô 3 / 4 số: the bao lô price follows the number of lô it covers (700đ a lô Nam/Trung, 800đ Bắc: 18 × 700 = 12.600,
  // 27 × 800 = 21.600): 3 số = 17 / 23 lô, 4 số = 16 / 20 lô. Only a starting point, the customer sets the real price.
  const price =
    { lo: loPrice, lo3: mb ? 18400 : 11900, lo4: mb ? 16000 : 11200, dau: 1000, duoi: 1000, cang3: 12600, cang4: 12600 }[kind] ?? loPrice
  const payout = { lo: 70000, dau: 70000, duoi: 70000, cang3: 500000, cang4: 5000000 }[kind] ?? 0
  const tiers = kind === 'dau' ? [mb ? 'giaiNhat' : 'giaiTam'] : undefined
  return makeRow({ kind, price, payout, tiers })
}
// ---- Lấy số: which numbers of the day a kind looks at -------------------------------------------------------------------
// { tiers: [giải...], position: 'last' | 'first', digits: n, pick?: [lô thứ...] }
//   tiers     the prizes (dãy giải) the numbers come from
//   position  the last n digits (đuôi) or the first n digits (đầu) of each number
//   digits    how many digits are compared
//   pick      only the 1st, 2nd... number of each selected prize (empty = every number of the prize)
// The prizes of a region, with how many numbers each has and how long they are (Miền Bắc 27 lô, Miền Nam / Trung 18 lô).
export const PRIZE_INFO = {
  mb: [
    { tier: 'dacBiet', label: 'Giải đặc biệt', count: 1, digits: 5 },
    { tier: 'giaiNhat', label: 'Giải nhất', count: 1, digits: 5 },
    { tier: 'giaiNhi', label: 'Giải nhì', count: 2, digits: 5 },
    { tier: 'giaiBa', label: 'Giải ba', count: 6, digits: 5 },
    { tier: 'giaiTu', label: 'Giải tư', count: 4, digits: 4 },
    { tier: 'giaiNam', label: 'Giải năm', count: 6, digits: 4 },
    { tier: 'giaiSau', label: 'Giải sáu', count: 3, digits: 3 },
    { tier: 'giaiBay', label: 'Giải bảy', count: 4, digits: 2 },
  ],
  south: [
    { tier: 'giaiTam', label: 'Giải tám', count: 1, digits: 2 },
    { tier: 'giaiBay', label: 'Giải bảy', count: 1, digits: 3 },
    { tier: 'giaiSau', label: 'Giải sáu', count: 3, digits: 4 },
    { tier: 'giaiNam', label: 'Giải năm', count: 1, digits: 4 },
    { tier: 'giaiTu', label: 'Giải tư', count: 7, digits: 5 },
    { tier: 'giaiBa', label: 'Giải ba', count: 2, digits: 5 },
    { tier: 'giaiNhi', label: 'Giải nhì', count: 1, digits: 5 },
    { tier: 'giaiNhat', label: 'Giải nhất', count: 1, digits: 5 },
    { tier: 'dacBiet', label: 'Giải đặc biệt', count: 1, digits: 6 },
  ],
}
export const prizeInfo = (region) => (region === 'mb' ? PRIZE_INFO.mb : PRIZE_INFO.south)
const allTiersOf = (region) => (region === 'mb' ? [...ALL_TIERS] : [...ALL_TIERS, 'giaiTam'])

export function normalizeSource(src) {
  const tiers = [...new Set((src?.tiers || []).filter((t) => [...ALL_TIERS, 'giaiTam'].includes(t)))]
  const digits = Math.min(6, Math.max(1, Math.round(Number(src?.digits)) || 2))
  const pick = [...new Set((src?.pick || []).map((x) => Math.round(Number(x))).filter((x) => x >= 1 && x <= 30))].sort((a, b) => a - b)
  const out = { tiers, position: src?.position === 'first' ? 'first' : 'last', digits }
  if (pick.length) out.pick = pick
  return out
}
// What each kind reads when the customer has not changed it.
export function defaultSource(kind, region = 'mb', cfg = null) {
  const mb = region === 'mb'
  const digits = { lo3: 3, lo4: 4, cang3: 3, cang4: 4, chan_le: 1 }[kind] ?? 2
  let tiers
  if (kind === 'dau') tiers = [mb ? 'giaiNhat' : 'giaiTam']
  else if (['duoi', 'cang3', 'cang4', 'tai_xiu', 'chan_le'].includes(kind)) tiers = ['dacBiet']
  else if (kind === 'custom') tiers = cfg?.tiers?.length ? cfg.tiers : ['dacBiet']
  else tiers = allTiersOf(region)
  return { tiers, position: 'last', digits: kind === 'custom' ? cfg?.digits || 2 : digits }
}
export const effectiveSource = (cfg, kind, region = 'mb') => (cfg?.source ? normalizeSource(cfg.source) : defaultSource(kind, region, cfg))
export const sameSource = (a, b) => JSON.stringify(normalizeSource(a)) === JSON.stringify(normalizeSource(b))
// Which of the four settings make sense for a kind: thần tài only chooses the prize; xiên / trượt compare 2 digits and
// choose the prizes; single-number kinds (bao lô, đề, 3-4 càng, kiểu khác) choose everything.
export function sourceFields(kind) {
  if (kind === 'tai_xiu' || kind === 'chan_le') return { tiers: true, position: false, digits: false, pick: true }
  if (kind?.startsWith('xien') || kind?.startsWith('truot')) return { tiers: true, position: false, digits: false, pick: false }
  return { tiers: true, position: true, digits: true, pick: true }
}
// "2 số cuối của giải đặc biệt, giải nhất" - for the row's caption.
export function describeSource(src, region = 'mb') {
  const info = prizeInfo(region)
  const names = src.tiers.map((t) => info.find((p) => p.tier === t)?.label?.toLowerCase() || t)
  const all = allTiersOf(region)
  const every = all.every((t) => src.tiers.includes(t))
  const where = src.position === 'first' ? 'đầu' : 'cuối'
  const which = src.pick?.length ? ` (lô thứ ${src.pick.join(', ')})` : ''
  return `${src.digits} số ${where} của ${every ? `cả ${region === 'mb' ? 27 : 18} lô` : names.join(', ')}${which}`
}

// Where a kind takes its numbers from, in each region (shown under the row so the customer can check it).
export function kindSource(kind, region = 'mb') {
  const mb = region === 'mb'
  const n = mb ? 27 : 18
  const x = kind.startsWith('xien') ? kind.slice(4) : kind.startsWith('truot') ? kind.slice(5) : ''
  switch (kind) {
    case 'lo': return `2 số cuối của cả ${n} lô`
    case 'lo3': return `3 số cuối của ${mb ? 23 : 17} lô có từ 3 chữ số`
    case 'lo4': return `4 số cuối của ${mb ? 20 : 16} lô có từ 4 chữ số`
    case 'dau': return mb ? 'Khách Bắc: 2 số cuối giải nhất. Khách Nam/Trung: 4 giải bảy, tiền xác ×4' : 'Giải tám (2 số)'
    case 'duoi': return '2 số cuối giải đặc biệt'
    case 'cang3': return '3 số cuối giải đặc biệt'
    case 'cang4': return '4 số cuối giải đặc biệt'
    case 'tai_xiu': return 'Đuôi giải đặc biệt: 00-49 Xỉu, 50-99 Tài'
    case 'chan_le': return 'Số cuối giải đặc biệt: chẵn hoặc lẻ'
    default:
      if (kind.startsWith('xien')) return `Cả ${x} cặp số cùng về trong ${n} lô (2 số cuối), tiền xác × ${x}`
      if (kind.startsWith('truot')) return `Cả ${x} cặp số đều không về trong ${n} lô, tiền xác × ${x}`
      return ''
  }
}
const buildDefaults = () => {
  const out = {}
  for (const region of ['mb', 'mt', 'mn']) for (const kind of TABLE_KIND_KEYS) out[`${kind}@${region}`] = defaultRow(kind, region)
  return out
}
export const DEFAULT_RATES = buildDefaults()
// The last resort for an entry whose type has no config at all (older data typed as "de").
export const FALLBACK_DE = { rate: 70, tiers: ['dacBiet'], digits: 2 }

// How a stored config reads in the table: price / payout in đồng per điểm. Older rows (no `kind`) are converted: a
// point-unit row has price = pointValue and payout = rate × pointValue; a money-unit row (the stake is already đồng)
// has price 1 and payout = rate.
export function toTableRow(key, cfg) {
  if (!cfg) return null
  if (cfg.kind) return cfg
  const point = unitOf(key, cfg) === 'point'
  const price = point ? pointValueOf(cfg) : 1
  return { ...cfg, kind: key === 'lo' ? 'lo' : 'custom', price, payout: Number(cfg.rate) * price }
}
export const hasMoneyModel = (cfg) => cfg?.price != null && cfg?.payout != null

// A rates map holds `type` (applies to every region) and `type@mb|mt|mn` (that region only, wins over `type`).
export const regionKey = (type, region) => `${type}@${region}`
export const isRegionalKey = (key) => key.includes('@')
export const baseKey = (key) => key.split('@')[0]

// The bet types of a rates map (keys without a region suffix).
export const typesOf = (rates) => Object.keys(rates || {}).filter((k) => !isRegionalKey(k) && !rates[k]?.disabled)

// Bet types of a rates map as seen in one region: the shared ones plus the ones made only for that region (`type@region`
// with no shared `type`).
export function typesIn(rates, region) {
  const keys = Object.keys(rates || {})
  const off = (type) => {
    const regional = rates[regionKey(type, region)]
    return regional ? !!regional.disabled : !!rates[type]?.disabled // a row removed from the table ({ disabled: true })
  }
  const shared = keys.filter((k) => !isRegionalKey(k) && !off(k))
  const own = keys.filter((k) => k.endsWith(`@${region}`) && !rates[k]?.disabled).map(baseKey).filter((t) => !shared.includes(t) && !rates[t]?.disabled)
  return [...shared, ...own]
}

// Config of one bet type for one region, looking at: the customer's own region value, the customer's own value for
// every region, the account's region value, the account's value, then the account's Đề.
// `{disabled: true}` on the customer = the customer does not use that type (entries already saved with it are still
// scored with the account-wide config).
export function effectiveConfig(accountRates, customerRates, betType, region = 'mb') {
  const key = betType || 'de'
  for (const k of [regionKey(key, region), key]) {
    const own = customerRates?.[k]
    if (own && !own.disabled) return own
    if (own?.disabled) break
  }
  const acc = accountRates?.[regionKey(key, region)] ?? accountRates?.[key]
  // A row the account removed from its table still scores the entries already saved with it, with the built-in default.
  if (acc?.disabled) return isTableKind(key) ? defaultRow(key, region) : FALLBACK_DE
  return acc ?? accountRates?.de ?? FALLBACK_DE
}

// Old account-made types that mean the same as a standard kind ("Đề" = 2 số cuối giải đặc biệt = Đuôi, "3-càng" = 3 càng).
// Shown once, as the standard row; the old key stays in the data so entries already saved with it are scored as before.
export const LEGACY_TYPE_ALIAS = { de: 'duoi', '3-càng': 'cang3' }
export const withoutLegacyDuplicates = (types) => types.filter((t) => !(LEGACY_TYPE_ALIAS[t] && types.includes(LEGACY_TYPE_ALIAS[t])))

// Bet types this customer can use in `region`: the account's types minus the ones switched off for them (in every
// region or just this one), plus the types only they have.
export function customerBetTypes(accountRates, customerRates, region = 'mb') {
  const off = (k) => customerRates?.[k]?.disabled || customerRates?.[regionKey(k, region)]?.disabled
  const out = typesIn(accountRates, region).filter((k) => !off(k))
  for (const k of typesIn(customerRates, region)) if (!off(k) && !out.includes(k)) out.push(k)
  return withoutLegacyDuplicates(out)
}

// Same config? (rate, digits and the SET of prize groups)
export function sameConfig(a, b, key = '') {
  if (!a || !b) return false
  const ta = [...(a.tiers || [])].sort().join(',')
  const tb = [...(b.tiers || [])].sort().join(',')
  const ua = unitOf(key, a)
  const ub = unitOf(key, b)
  const moneyA = ua === 'point' ? pointValueOf(a) : 0
  const moneyB = ub === 'point' ? pointValueOf(b) : 0
  if (a.kind || b.kind) return a.kind === b.kind && Number(a.price) === Number(b.price) && Number(a.payout) === Number(b.payout) && symbolsText(a.symbols) === symbolsText(b.symbols) && (a.name || '') === (b.name || '') && (a.group || '') === (b.group || '') && JSON.stringify(a.source ? normalizeSource(a.source) : null) === JSON.stringify(b.source ? normalizeSource(b.source) : null) && (a.kind !== 'custom' || (Number(a.digits || 2) === Number(b.digits || 2) && ta === tb))
  return Number(a.rate) === Number(b.rate) && Number(a.digits || 2) === Number(b.digits || 2) && ta === tb && ua === ub && moneyA === moneyB
}

// ---- Money view (Tính điểm summary) ------------------------------------------------------
// A bet type is written either in điểm (default for "lô": the stake is points, 1 điểm = pointValue
// đồng) or in money (every other type by default: the stake is already đồng).
export const DEFAULT_POINT_VALUE = 23000
export const unitOf = (key, cfg) => cfg?.unit || (key === 'lo' ? 'point' : 'money')
export const pointValueOf = (cfg) => (cfg?.pointValue != null && Number(cfg.pointValue) >= 0 ? Number(cfg.pointValue) : DEFAULT_POINT_VALUE)
// `amount` is in the type's own unit (điểm or đồng); returns đồng.
export const toMoney = (key, cfg, amount) => (unitOf(key, cfg) === 'point' ? amount * pointValueOf(cfg) : amount)

// The ký hiệu the customer set for lo / dau / duoi, for the message parser: { lo: [...], dau: [...], duoi: [...] } (only the
// ones that differ from nothing: a kind without its own list keeps the built-in spellings).
export function kindSymbolsFor(accountRates, customerRates, region = 'mb') {
  const out = {}
  for (const kind of ['lo', 'dau', 'duoi']) {
    const list = effectiveConfig(accountRates, customerRates, kind, region)?.symbols
    if (Array.isArray(list) && list.length) out[kind] = list
  }
  return out
}
