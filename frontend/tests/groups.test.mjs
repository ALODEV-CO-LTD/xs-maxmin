import test from 'node:test'
import assert from 'node:assert/strict'
import { groupFromHeader, groupHeader, isGroupId } from '../src/e2ee/groups.js'

const g = { id: 'g-abcDEF123456789_-xyz', name: 'Nhóm lô', creatorId: 'A', updatedAt: 1000, members: [{ id: 'A', name: 'An' }, { id: 'B', name: 'Bình' }, { id: 'C', name: 'Cường' }] }

test('a group header round-trips', () => {
  assert.deepEqual(groupFromHeader(groupHeader(g)), g)
  assert.ok(isGroupId(g.id))
  assert.ok(!isGroupId('abc'))
})

test('a malformed or oversized group header is refused', () => {
  const h = groupHeader(g)
  assert.equal(groupFromHeader(null), null)
  assert.equal(groupFromHeader({ ...h, i: 'not-a-group-id' }), null)
  assert.equal(groupFromHeader({ ...h, n: 5 }), null)
  assert.equal(groupFromHeader({ ...h, m: [['A', 'An']] }), null) // fewer than 2 members
  assert.equal(groupFromHeader({ ...h, m: Array.from({ length: 51 }, (_, i) => [`u${i}`, 'x']) }), null)
  assert.equal(groupFromHeader({ ...h, m: [['A', 'An'], 'junk', ['B', 'Bình']] })?.members.length, 2) // junk entries are skipped
})

test('names are cut to a sane length', () => {
  const long = groupFromHeader(groupHeader({ ...g, name: 'x'.repeat(200), members: [{ id: 'A', name: 'y'.repeat(200) }, { id: 'B', name: 'B' }] }))
  assert.equal(long.name.length, 60)
  assert.equal(long.members[0].name.length, 80)
})
