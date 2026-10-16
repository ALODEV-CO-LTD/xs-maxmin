import test from 'node:test'
import assert from 'node:assert/strict'
import { composeTelex } from '../src/vietnameseInput.js'

const type = (s) => [...s].reduce((t, c) => composeTelex(t, c), '')

test('dấu thanh và chữ có mũ', () => {
  assert.equal(type('tieengs'), 'tiếng')
  assert.equal(type('Vieetj'), 'Việt')
  assert.equal(type('xin chaof'), 'xin chào')
  assert.equal(type('hoas'), 'hoá')
  assert.equal(type('thuys'), 'thuý')
  assert.equal(type('nguwowif'), 'người')
  assert.equal(type('ddi'), 'đi')
  assert.equal(type('Ddi'), 'Đi')
  assert.equal(type('banj'), 'bạn')
  assert.equal(type('nhaan'), 'nhân')
})

test('w đứng một mình và aw/ow/uw', () => {
  assert.equal(type('awn'), 'ăn')
  assert.equal(type('mow'), 'mơ')
  assert.equal(type('tuw'), 'tư')
  assert.equal(type('w'), 'ư')
})

test('đổi và bỏ dấu, các chữ không phải từ giữ nguyên', () => {
  assert.equal(type('bans'), 'bán')
  assert.equal(type('bansf'), 'bàn')
  assert.equal(type('bansz'), 'ban')
  assert.equal(type('bass'), 'bas')
  assert.equal(type('20lo100 s'), '20lo100 s')
  assert.equal(type('12 a'), '12 a')
})
