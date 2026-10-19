import test from 'node:test'
import assert from 'node:assert/strict'
import { clampReceivedTs, MAX_BACKDATE_MS } from '../src/lib/e2ee/timestamps.js'

test('clampReceivedTs bounds peer timestamps around receive time', () => {
  const now = 1_000_000_000_000
  assert.equal(clampReceivedTs(now - 1000, now), now - 1000)
  assert.equal(clampReceivedTs(now + 99999, now), now)
  assert.equal(clampReceivedTs(now - 30 * 86400000, now), now - MAX_BACKDATE_MS)
  assert.equal(clampReceivedTs(NaN, now), now)
  assert.equal(clampReceivedTs(undefined, now), now)
})
