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

export function effectiveConfig(accountRates, customerRates, betType) {
  const key = betType || 'de'
  const own = customerRates?.[key]
  // `{disabled: true}` = the customer does not use this type: entries already saved with it are
  // still scored with the account-wide config.
  if (own && !own.disabled) return own
  return accountRates?.[key] ?? accountRates?.de ?? DEFAULT_RATES.de
}

// Bet types this customer can use: the account's types minus the ones switched off for them,
// plus the types only they have.
export function customerBetTypes(accountRates, customerRates) {
  const out = Object.keys(accountRates || {}).filter((k) => !customerRates?.[k]?.disabled)
  for (const [k, v] of Object.entries(customerRates || {})) if (!v?.disabled && !out.includes(k)) out.push(k)
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
