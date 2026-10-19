import test from 'node:test'
import assert from 'node:assert/strict'
import { shouldKeepForRetry, changesDuringFlight } from '../src/lib/offlineRules.js'

test('transient statuses are kept for retry', () => {
  for (const s of [401, 408, 425, 429, 500, 502, 503]) assert.equal(shouldKeepForRetry(s), true, String(s))
})
test('definitive refusals are not retried', () => {
  for (const s of [400, 403, 404, 422]) assert.equal(shouldKeepForRetry(s), false, String(s))
})
test('edit made during flight is detected', () => {
  assert.deepEqual(changesDuringFlight({ value: 'a', note: 'x' }, { value: 'b', note: 'x' }), { value: 'b' })
  assert.deepEqual(changesDuringFlight({ value: 'a' }, { value: 'a', note: 'n' }), { note: 'n' })
  assert.equal(changesDuringFlight({ value: 'a', tags: [1] }, { value: 'a', tags: [1] }), null)
})
