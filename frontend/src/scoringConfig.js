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
  return customerRates?.[key] ?? accountRates?.[key] ?? accountRates?.de ?? DEFAULT_RATES.de
}

// Same config? (rate, digits and the SET of prize groups)
export function sameConfig(a, b) {
  if (!a || !b) return false
  const ta = [...(a.tiers || [])].sort().join(',')
  const tb = [...(b.tiers || [])].sort().join(',')
  return Number(a.rate) === Number(b.rate) && Number(a.digits || 2) === Number(b.digits || 2) && ta === tb
}
