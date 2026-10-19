// Lottery regions and stations (đài), loaded once from GET /lottery-stations (backend/lib/src/lottery_stations.dart
// is the single source of truth: Miền Bắc has one draw a day, Miền Nam / Miền Trung 2-4 provinces that rotate by
// weekday, each region has its own prize structure).
//
// An entry's `station` is 'mb' (or empty = all older entries), a region code ('mt' / 'mn' = every station of that
// region drawing that day) or one station id ('mn-tphcm').
import { api } from './api'

// Plain module state (no framework): React reads it with useStations() (src/lib/useStations.ts), which re-renders when it loads.
export const state = { regions: [], loaded: false }
const listeners = new Set()
export const subscribeStations = (fn) => (listeners.add(fn), () => listeners.delete(fn))
export const stationsVersion = () => (state.loaded ? state.regions : null)
let loading = null

export function loadStations() {
  if (state.loaded) return Promise.resolve()
  if (!loading) {
    loading = api
      .get('/lottery-stations')
      .then((res) => {
        state.regions = res.regions
        state.loaded = true
        listeners.forEach((fn) => fn())
      })
      .catch(() => {
        // Offline / failed: Miền Bắc keeps working with the built-in structure below.
      })
      .finally(() => {
        loading = null
      })
  }
  return loading
}

// Built-in Miền Bắc so everything still works before (or without) the catalog.
const MB_FALLBACK = {
  id: 'mb',
  name: 'Miền Bắc',
  stations: { mb: 'Miền Bắc' },
  schedule: { 1: ['mb'], 2: ['mb'], 3: ['mb'], 4: ['mb'], 5: ['mb'], 6: ['mb'], 7: ['mb'] },
  structure: [
    { tier: 'dacBiet', label: 'Đặc biệt', count: 1, digits: 5 },
    { tier: 'giaiNhat', label: 'Giải nhất', count: 1, digits: 5 },
    { tier: 'giaiNhi', label: 'Giải nhì', count: 2, digits: 5 },
    { tier: 'giaiBa', label: 'Giải ba', count: 6, digits: 5 },
    { tier: 'giaiTu', label: 'Giải tư', count: 4, digits: 4 },
    { tier: 'giaiNam', label: 'Giải năm', count: 6, digits: 4 },
    { tier: 'giaiSau', label: 'Giải sáu', count: 3, digits: 3 },
    { tier: 'giaiBay', label: 'Giải bảy', count: 4, digits: 2 },
  ],
}

export const regionList = () => (state.regions.length ? state.regions : [MB_FALLBACK])
export const REGION_IDS = ['mb', 'mt', 'mn']

// Region object for a region code or a station id; Miền Bắc when empty/unknown.
export function regionOf(code) {
  const list = regionList()
  if (!code) return list.find((r) => r.id === 'mb') || MB_FALLBACK
  return list.find((r) => r.id === code || (r.stations && code in r.stations)) || list.find((r) => r.id === 'mb') || MB_FALLBACK
}

export const isRegionCode = (code) => REGION_IDS.includes(code)

// ISO date (YYYY-MM-DD) -> weekday 1 (Monday) .. 7 (Sunday), computed in UTC so the time zone never shifts the day.
export function weekdayOf(iso) {
  const [y, m, d] = String(iso).split('-').map(Number)
  const wd = new Date(Date.UTC(y, m - 1, d)).getUTCDay() // 0 = Sunday
  return wd === 0 ? 7 : wd
}

// Stations of `regionId` drawing on `iso`.
export function stationsOn(regionId, iso) {
  const r = regionOf(regionId)
  return r.schedule?.[weekdayOf(iso)] || (r.id === 'mb' ? ['mb'] : [])
}

// The concrete stations an entry counts for on its date: a station id -> itself; a region code -> every station of
// the region drawing that day; empty -> Miền Bắc.
export function entryStations(entry) {
  const code = entry.station
  if (!code || code === 'mb') return ['mb']
  if (isRegionCode(code)) return stationsOn(code, entry.entryDate)
  return [code]
}

export function stationName(id) {
  for (const r of regionList()) if (r.stations && id in r.stations) return r.stations[id]
  return id
}

export function stationLabel(code) {
  if (!code || code === 'mb') return 'Miền Bắc'
  if (isRegionCode(code)) return `${regionOf(code).name} (tất cả đài trong ngày)`
  return `${stationName(code)} (${regionOf(code).name})`
}

// Options for an "Đài" picker on `iso`: Miền Bắc, each region as "all stations drawing that day", and that day's stations.
export function stationOptions(iso) {
  const out = [{ value: 'mb', label: 'Miền Bắc' }]
  for (const r of regionList()) {
    if (r.id === 'mb') continue
    const today = stationsOn(r.id, iso)
    out.push({ value: r.id, label: `${r.name}${today.length ? ` (${today.length} đài: ${today.map(stationName).join(', ')})` : ''}` })
    for (const s of today) out.push({ value: s, label: `   ${stationName(s)} (${r.name})` })
  }
  return out
}

// Every station, for choosing a customer's default (not tied to a day): each region as "all its stations", then its stations.
export function allStationOptions() {
  const out = [{ value: 'mb', label: 'Miền Bắc' }]
  for (const r of regionList()) {
    if (r.id === 'mb') continue
    out.push({ value: r.id, label: `${r.name} (tất cả đài trong ngày)` })
    for (const [id, name] of Object.entries(r.stations || {})) out.push({ value: id, label: `   ${name} (${r.name})` })
  }
  return out
}
