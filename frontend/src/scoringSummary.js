// "Tổng kết tiền" of one customer over the days on screen (Tính điểm):
//   (1) what the customer sent: how many lô (numbers), how many điểm, converted to đồng;
//   (2) what won: how many lô hit, which ones and the money;
//   (3) the rest = (1) - (2).
// (2) and (3) only cover the days that already have a lottery result; the stakes of days
// without a result are reported separately as "chưa có kết quả" and not counted in (3).
import { effectiveConfig, pointValueOf, toMoney, unitOf } from './scoringConfig.js'
import { entryStations, regionOf } from './lotteryStations.js'

const toNumber = (v) => {
  const n = parseFloat(String(v ?? '').replace(/[^\d.-]/g, ''))
  return Number.isFinite(n) ? n : 0
}
export const normDigits = (str, count) => {
  const d = String(str || '').replace(/\D/g, '')
  return d ? d.slice(-count).padStart(count, '0') : ''
}
const BASE_TIERS = ['dacBiet', 'giaiNhat', 'giaiNhi', 'giaiBa', 'giaiTu', 'giaiNam', 'giaiSau', 'giaiBay']
const TIER_FIELDS = [...BASE_TIERS, 'giaiTam']
// The numbers of the prize groups a bet type checks. A config that ticks all eight classic groups means "every prize",
// so on a Miền Nam / Miền Trung result it includes the eighth prize (giaiTam) too.
export function numbersForTiers(r, tiers) {
  const out = []
  const all = BASE_TIERS.every((t) => tiers.includes(t))
  for (const t of tiers) if (TIER_FIELDS.includes(t)) out.push(...[].concat(r[t] ?? []))
  if (all && !tiers.includes('giaiTam')) out.push(...[].concat(r.giaiTam ?? []))
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

// days: [{ date, entries }]; getResult(date, station) -> result | null | undefined (not known yet = pending).
// An entry on a region ('mn' / 'mt') counts once for EVERY station of that region drawing that day (stake and
// prizes are per station).
export function summarize(days, accountRates, customerRates, getResult) {
  const byType = new Map()
  const won = []
  const sent = { lots: 0, points: 0, money: 0 }
  const settled = { lots: 0, money: 0 } // sent on days that have a result
  const pending = { lots: 0, money: 0 } // sent on days without a result yet
  let wonMoney = 0
  let wonHits = 0

  for (const day of days) {
    for (const entry of day.entries) {
      const key = entry.betType || 'de'
      const stations = entryStations({ ...entry, entryDate: entry.entryDate || day.date })
      for (const station of stations.length ? stations : ['mb']) {
        // Rates can differ by region (Miền Bắc has 27 numbers a day, Miền Nam / Miền Trung 18).
        const cfg = effectiveConfig(accountRates, customerRates, key, regionOf(station).id)
        const unit = unitOf(key, cfg)
        const lr = getResult(day.date, station)
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
          won.push({ date: day.date, type: key, station, number: n.number, hits: n.hits, money })
          wonMoney += money
          wonHits += n.hits
        }
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
