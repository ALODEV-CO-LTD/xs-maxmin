// Which payout config applies to an entry: the customer's own override for that bet type if
// they have one, else the account-wide setting (Cấu hình mặc định), else the built-in Đề.
export const DEFAULT_RATES = {
  de: { rate: 70, tiers: ['dacBiet'], digits: 2 },
  lo: {
    rate: 20,
    tiers: ['dacBiet', 'giaiNhat', 'giaiNhi', 'giaiBa', 'giaiTu', 'giaiNam', 'giaiSau', 'giaiBay'],
    digits: 2,
  },
}

// A rates map holds `type` (applies to every region) and `type@mb|mt|mn` (that region only, wins over `type`).
export const regionKey = (type, region) => `${type}@${region}`
export const isRegionalKey = (key) => key.includes('@')
export const baseKey = (key) => key.split('@')[0]

// The bet types of a rates map (keys without a region suffix).
export const typesOf = (rates) => Object.keys(rates || {}).filter((k) => !isRegionalKey(k))

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
  return accountRates?.[regionKey(key, region)] ?? accountRates?.[key] ?? accountRates?.de ?? DEFAULT_RATES.de
}

// Bet types this customer can use in `region`: the account's types minus the ones switched off for them (in every
// region or just this one), plus the types only they have.
export function customerBetTypes(accountRates, customerRates, region = 'mb') {
  const off = (k) => customerRates?.[k]?.disabled || customerRates?.[regionKey(k, region)]?.disabled
  const out = typesOf(accountRates).filter((k) => !off(k))
  for (const k of typesOf(customerRates)) if (!off(k) && !out.includes(k)) out.push(k)
  return out
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
