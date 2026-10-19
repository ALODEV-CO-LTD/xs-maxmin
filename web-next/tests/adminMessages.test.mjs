import test from 'node:test'
import assert from 'node:assert/strict'
import { noAccents, filterConversations, awaitingCountOf, shortTime, threadSubtitle, withDayDividers, dayLabel, unreadBadge, avatarLetter } from '../src/features/admin/messagesLogic.js'

const C = [
  { userId: '1', userName: 'Nguyễn Đức', username: 'duc01', awaitingReply: true },
  { userId: '2', userName: 'Lê Hoa', username: 'hoa', awaitingReply: false },
]
test('tìm không dấu theo tên hoặc tài khoản, lọc chưa trả lời', () => {
  assert.equal(noAccents('Đức Ấ'), 'duc a')
  assert.deepEqual(filterConversations(C, 'duc', false).map((c) => c.userId), ['1'])
  assert.deepEqual(filterConversations(C, 'HOA', false).map((c) => c.userId), ['2'])
  assert.deepEqual(filterConversations(C, '', true).map((c) => c.userId), ['1'])
  assert.equal(filterConversations(C, 'zzz', false).length, 0)
  assert.equal(awaitingCountOf(C), 1)
})
test('nhãn thời gian: hôm nay giờ, hôm qua, ngày/tháng', () => {
  const now = new Date(2026, 9, 19, 15, 0)
  assert.match(shortTime(new Date(2026, 9, 19, 9, 5).toISOString(), now), /09:05|9:05/)
  assert.equal(shortTime(new Date(2026, 9, 18, 23, 0).toISOString(), now), 'Hôm qua')
  assert.match(shortTime(new Date(2026, 9, 10, 8, 0).toISOString(), now), /10\/10/)
  assert.equal(shortTime('', now), '')
})
test('phụ đề và huy hiệu', () => {
  assert.equal(threadSubtitle({ username: 'a', packageType: 'm1' }, (x) => '1 tháng'), '@a · 1 tháng')
  assert.equal(threadSubtitle(null), '')
  assert.equal(unreadBadge(12), '9+')
  assert.equal(unreadBadge(3), '3')
  assert.equal(avatarLetter('đức'), 'Đ')
  assert.equal(avatarLetter(''), '?')
})
test('thread chia theo ngày có vạch ngày', () => {
  const now = new Date(2026, 9, 19, 12)
  const m = (d, h, id) => ({ id, createdAt: new Date(2026, 9, d, h).toISOString() })
  const items = withDayDividers([m(18, 9, 'a'), m(18, 10, 'b'), m(19, 8, 'c')], now)
  assert.deepEqual(items.map((i) => (i.divider ? i.label : i.id)), ['Hôm qua', 'a', 'b', 'Hôm nay', 'c'])
  assert.equal(dayLabel('bad', now), '')
})
