import test from 'node:test'
import assert from 'node:assert/strict'
import {
  interpretAddResponse, searchAction, normalizeRequests, removeRequest, upsertFriend, incomingFrom, badgeText,
} from '../src/friendRequests.js'

const friend = { id: 'u1', name: 'Mai', username: 'mai', isAdmin: false, publicKey: 'k' }

test('status friends -> friend added', () => {
  const r = interpretAddResponse({ status: 'friends', friend })
  assert.equal(r.kind, 'friends')
  assert.equal(r.friend, friend)
  assert.equal(r.message, 'Đã là bạn bè')
})
test('legacy bare friend row still counts as friends', () => {
  assert.equal(interpretAddResponse(friend).kind, 'friends')
})
test('pending with request uses server name', () => {
  const r = interpretAddResponse({ status: 'pending', request: { id: 'r1', toId: 'u2', toName: 'Lan' } }, 'X')
  assert.equal(r.kind, 'pending')
  assert.equal(r.message, 'Đã gửi lời mời kết bạn tới Lan. Họ cần chấp nhận.')
})
test('silent pending without request falls back to given name', () => {
  const r = interpretAddResponse({ status: 'pending' }, 'Hoa')
  assert.equal(r.request, null)
  assert.match(r.message, /tới Hoa\./)
})
test('search action by requestState', () => {
  assert.deepEqual(searchAction({ requestState: 'none' }), { label: 'Kết bạn', action: 'add', disabled: false })
  assert.deepEqual(searchAction({}), { label: 'Kết bạn', action: 'add', disabled: false })
  assert.deepEqual(searchAction({ requestState: 'outgoing' }), { label: 'Đã gửi lời mời', action: 'none', disabled: true })
  assert.deepEqual(searchAction({ requestState: 'incoming' }), { label: 'Chấp nhận', action: 'accept', disabled: false })
})
test('normalizeRequests tolerates missing fields', () => {
  assert.deepEqual(normalizeRequests(null), { incoming: [], outgoing: [] })
  assert.deepEqual(normalizeRequests({ incoming: [{ id: 1 }] }), { incoming: [{ id: 1 }], outgoing: [] })
})
test('removeRequest / incomingFrom', () => {
  const l = [{ id: 'a', fromId: 'x' }, { id: 'b', fromId: 'y' }]
  assert.deepEqual(removeRequest(l, 'a'), [l[1]])
  assert.equal(incomingFrom(l, 'y').id, 'b')
  assert.equal(incomingFrom(l, 'z'), null)
})
test('upsertFriend does not duplicate', () => {
  assert.equal(upsertFriend([friend], friend).length, 1)
  assert.equal(upsertFriend([], friend)[0], friend)
})
test('badgeText', () => {
  assert.equal(badgeText(0), '')
  assert.equal(badgeText(3), '3')
  assert.equal(badgeText(150), '99+')
})

test('the requests block is reachable on the web (no bottom bar) and stays on Danh bạ when there is a bar', async () => {
  const { showRequestsBlock } = await import('../src/friendRequests.js')
  assert.equal(showRequestsBlock('chats', false, true), true) // web: the chats list is the only list
  assert.equal(showRequestsBlock('contacts', false, true), true)
  assert.equal(showRequestsBlock('chats', true, true), false) // with the bottom bar it belongs to Danh bạ
  assert.equal(showRequestsBlock('contacts', true, true), true)
  assert.equal(showRequestsBlock('chats', false, false), false) // nothing to show
})
