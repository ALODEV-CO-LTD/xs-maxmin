import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { northNumbers, digitsOf } from '../src/lib/northTable.js'

// Words (with positions) read by the engine from two real photos: xskt.com.vn (label column, đầu / đuôi table, "Mã ĐB" footer)
// and a table whose rows are labelled "Giải ba / 6 ô · 5 số" with giải ba and giải năm on one row of 6.
const photos = JSON.parse(readFileSync(new URL('./fixtures/northPhotos.json', import.meta.url)))

test('ảnh xskt.com.vn: nhãn ĐB/G1.., bảng đầu đuôi và mã ĐB không chiếm ô giải', () => {
  const r = northNumbers(photos.xskt)
  assert.deepEqual(r.numbers.slice(0, 20), '19640 50576 71187 68099 40352 53320 45756 74599 97405 47672 4336 4243 5099 3698 6988 6117 9223 2181 7486 3164'.split(' '))
  assert.deepEqual(r.numbers.slice(-4), ['48', '94', '22', '74']) // not "08" / "62" from the labels
})

test('ảnh có nhãn "1 ô · 5 số": giải ba và giải năm một hàng 6 số', () => {
  const r = northNumbers(photos.labels)
  assert.deepEqual(r.numbers.slice(0, 20), '19640 50576 71187 68099 40352 53320 45756 74599 97405 47672 4336 4243 5099 3698 6988 6117 9223 2181 7486 3164'.split(' '))
  assert.deepEqual(r.numbers.slice(20, 23), ['241', '365', '669'])
})

test('chữ giống số trong số in đậm được sửa, từ khác thì không', () => {
  assert.equal(digitsOf('I9640'), '19640')
  assert.equal(digitsOf('5O576'), '50576')
  assert.equal(digitsOf('Giai'), null)
  assert.equal(digitsOf('9%'), null)
})
