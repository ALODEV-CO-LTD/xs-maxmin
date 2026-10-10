// "Tổng kết tiền" of one customer over the days on screen (Tính điểm):
//   (1) what the customer sent: how many lô (numbers), how many điểm, converted to đồng;
//   (2) what won: how many lô hit, which ones and the money;
//   (3) the rest = (1) - (2).
// (2) and (3) only cover the days that already have a lottery result; the stakes of days
// without a result are reported separately as "chưa có kết quả" and not counted in (3).
import { effectiveConfig, pointValueOf, toMoney, unitOf } from './scoringConfig.js'

const toNumber = (v) => {
  const n = parseFloat(String(v ?? '').replace(/[^\d.-]/g, ''))
  return Number.isFinite(n) ? n : 0
}
export const normDigits = (str, count) => {
  const d = String(str || '').replace(/\D/g, '')
  return d ? d.slice(-count).padStart(count, '0') : ''
}
const TIER_FIELDS = ['dacBiet', 'giaiNhat', 'giaiNhi', 'giaiBa', 'giaiTu', 'giaiNam', 'giaiSau', 'giaiBay']
export function numbersForTiers(r, tiers) {
  const out = []
  for (const t of tiers) if (TIER_FIELDS.includes(t)) out.push(...[].concat(r[t] ?? []))
  return out
}

// One entry against one day's result: its numbers, hits per number and the points/money out.
export function entryDetail(entry, lr, config) {
  const digits = config.digits || 2
  const bets = String(entry.value || '').split(/[,;\s]+/).map((v) => normDigits(v, digits)).filter(Boolean)
  const trailing = lr ? numbersForTiers(lr, config.tiers).map((n) => String(n).slice(-digits)) : []
  const score = toNumber(entry.score)
  const perNumber = bets.map((number) => ({ number, hits: trailing.filter((x) => x === number).length }))
  const totalHits = perNumber.reduce((a, b) => a + b.hits, 0)
  return { bets, lots: Math.max(1, bets.length), perNumber, score, out: totalHits > 0 ? score * config.rate * totalHits : 0 }
}

// days: [{ date, entries }]; lotteryByDate: { date: result | null | undefined }
export function summarize(days, accountRates, customerRates, lotteryByDate) {
  const byType = new Map()
  const won = []
  const sent = { lots: 0, points: 0, money: 0 }
  const settled = { lots: 0, money: 0 } // sent on days that have a result
  const pending = { lots: 0, money: 0 } // sent on days without a result yet
  let wonMoney = 0
  let wonHits = 0

  for (const day of days) {
    const lr = lotteryByDate[day.date]
    for (const entry of day.entries) {
      const key = entry.betType || 'de'
      const cfg = effectiveConfig(accountRates, customerRates, key)
      const unit = unitOf(key, cfg)
      const d = entryDetail(entry, lr, cfg)
      const stake = d.score * d.lots // each number carries the entry's score
      const stakeMoney = toMoney(key, cfg, stake)

      let t = byType.get(key)
      if (!t) byType.set(key, (t = { key, unit, pointValue: pointValueOf(cfg), lots: 0, amount: 0, money: 0 }))
      t.lots += d.lots
      t.amount += stake
      t.money += stakeMoney
      sent.lots += d.lots
      sent.money += stakeMoney
      if (unit === 'point') sent.points += stake

      if (!lr) {
        pending.lots += d.lots
        pending.money += stakeMoney
        continue
      }
      settled.lots += d.lots
      settled.money += stakeMoney
      for (const n of d.perNumber) {
        if (!n.hits) continue
        const money = toMoney(key, cfg, d.score * cfg.rate * n.hits)
        won.push({ date: day.date, type: key, number: n.number, hits: n.hits, money })
        wonMoney += money
        wonHits += n.hits
      }
    }
  }
  won.sort((a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1 : b.money - a.money))
  return {
    sent,
    byType: [...byType.values()],
    settled,
    pending,
    won: { lots: won.length, hits: wonHits, items: won, money: wonMoney },
    remaining: settled.money - wonMoney,
  }
}
