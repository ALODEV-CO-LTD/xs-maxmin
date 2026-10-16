// Test-only module loader: scoringSummary.js imports lotteryStations.js, which needs Vue + the API client. The tests
// swap it for a tiny stand-in (region of a station id, the stations of an entry).
import { register } from 'node:module'

register('data:text/javascript,' + encodeURIComponent(`
export async function resolve(specifier, context, next) {
  if (specifier.endsWith('lotteryStations.js')) return { url: 'data:text/javascript,' + encodeURIComponent(
    "export const regionOf = (s) => ({ id: !s || s === 'mb' ? 'mb' : String(s).startsWith('mt') ? 'mt' : 'mn' }); export const entryStations = (e) => [e.station || 'mb'];"
  ), shortCircuit: true }
  return next(specifier, context)
}`))
