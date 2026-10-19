// Loads everything Thống kê needs, with the services passed in so tests can fake them (the same order of work as
// AccountStats.vue's onMounted: customers + all entries + own rates + stations in parallel, then the lottery
// results of every needed (date, station) four at a time, then the money per date).
import { neededResults } from '../../lib/statsMoney.js'

export async function loadResult(api, cache, date, station) {
  try {
    const { result } = await api.get(`/lottery-results?date=${date}&station=${encodeURIComponent(station)}`)
    cache.set(`${date}|${station}`, result || null)
  } catch {
    cache.set(`${date}|${station}`, null) // not known: counted as "chưa tính"
  }
}

export async function loadMoney({ api, cachedGet, loadAllEntries, loadStations, DEFAULT_RATES, moneyByDate }) {
  const [{ customers }, list, rates] = await Promise.all([
    cachedGet('/me/customers'),
    loadAllEntries(),
    api.get('/me/scoring-settings').then((r) => (r.rates && Object.keys(r.rates).length ? r.rates : DEFAULT_RATES)).catch(() => DEFAULT_RATES),
    loadStations().catch(() => null),
  ])
  const cache = new Map()
  const queue = neededResults(list.entries)
  await Promise.all(Array.from({ length: 4 }, async () => {
    while (queue.length) {
      const [date, st] = queue.pop()
      await loadResult(api, cache, date, st)
    }
  }))
  return moneyByDate(list.entries, customers, rates, (date, st) => cache.get(`${date}|${st}`) || null)
}
