// React hook over lotteryStations.js: re-renders when the station catalog finishes loading (the Vue code read a
// `reactive` state). Returns `{ regions, loaded }`.
import { useSyncExternalStore } from 'react'
import { state, subscribeStations, stationsVersion } from './lotteryStations'

export function useStations() {
  const regions = useSyncExternalStore(subscribeStations, stationsVersion, () => null)
  return { regions: regions || state.regions, loaded: regions !== null }
}
