// Tài khoản > Thống kê in MONEY, worked out exactly like Tính điểm (same `summarize`, same payout rows, per customer):
// money the customers sent, money they won, and the profit on the days that already have a lottery result. Days without a
// result are kept apart ("chưa tính") and never counted as profit. Shared logic with the app (stats_money.dart).
import { summarize } from './scoringSummary.js'
import { entryStations } from './lotteryStations.js'

const NO_NAME = '(Không tên)'

// Every [date, station] the entries count for (what has to be looked up before the money can be worked out).
export function neededResults(entries) {
  const seen = new Set()
  const out = []
  for (const e of entries) {
    const sts = entryStations(e)
    for (const st of sts.length ? sts : ['mb']) {
      const k = `${e.entryDate}|${st}`
      if (!seen.has(k)) {
        seen.add(k)
        out.push([e.entryDate, st])
      }
    }
  }
  return out
}

// byDate: { 'YYYY-MM-DD': { sent, settled, won, pending, pendingLots } } in đồng.
// getResult(date, station) -> result | null (none / not known).
export function moneyByDate(entries, customers, accountRates, getResult) {
  const byName = new Map((customers || []).map((c) => [c.name, c]))
  const groups = new Map() // customer -> date -> entries
  const names = new Set((customers || []).map((c) => c.name))
  for (const e of entries) {
    const name = e.customerName || NO_NAME
    names.add(name)
    if (!groups.has(name)) groups.set(name, new Map())
    const days = groups.get(name)
    if (!days.has(e.entryDate)) days.set(e.entryDate, [])
    days.get(e.entryDate).push(e)
  }
  const byDate = {}
  for (const [name, days] of groups) {
    const c = byName.get(name)
    for (const [date, list] of days) {
      const s = summarize([{ date, entries: list }], accountRates, c?.scoringRates || null, getResult, { customerRegion: c?.homeRegion || null })
      const d = (byDate[date] ||= { sent: 0, settled: 0, won: 0, pending: 0, pendingLots: 0 })
      d.sent += s.sent.money
      d.settled += s.settled.money
      d.won += s.won.money
      d.pending += s.pending.money
      d.pendingLots += s.pending.lots
    }
  }
  return { byDate, customers: names.size, plays: entries.length }
}

// The same shape as entries so statsSeries.js (unit-tested) buckets them: vào = score, ra = result, lợi nhuận = vào − ra.
export function pseudoEntries(byDate, metric) {
  return Object.entries(byDate).map(([entryDate, m]) => {
    if (metric === 'vao') return { entryDate, score: String(m.sent), result: '0' }
    if (metric === 'ra') return { entryDate, score: '0', result: String(m.won) }
    return { entryDate, score: String(m.settled), result: String(m.won) } // lợi nhuận: only days with a result
  })
}

export function moneyTotals(byDate) {
  let sent = 0
  let settled = 0
  let won = 0
  let pending = 0
  let pendingLots = 0
  for (const m of Object.values(byDate)) {
    sent += m.sent
    settled += m.settled
    won += m.won
    pending += m.pending
    pendingLots += m.pendingLots
  }
  return { sent, won, profit: settled - won, pending, pendingLots }
}
