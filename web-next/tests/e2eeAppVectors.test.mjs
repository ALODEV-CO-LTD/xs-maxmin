// Tương thích giao thức với app Flutter: cùng các vector đã dùng trong app/test/friends_crypto_test.dart (tạo bởi
// crypto.js của bản Vue, Dart tạo lại byte-theo-byte). Nếu một vector đổi, app và web không còn đọc được tin của nhau.
import test from 'node:test'
import assert from 'node:assert/strict'
import { b64encode, decryptBytes, deriveSessionKey, encryptBytes, fingerprint, packMessage, unpackMessage } from '../src/lib/e2ee/crypto.js'

const idA = 'user-aaaa-1111', idB = 'user-bbbb-2222', msgId = 'AbCdEfGhIjKlMnOpQrStUv'
const aPrivate = { kty: 'EC', crv: 'P-256', x: 'JDYgQ2CE4BGUyuBSlF4UxKA-ebWshu0uPknfe5CN9Xg', y: '3tT6t2xBvNeXuHLx9-TE6Cx-wF4wcjnWGxccJjcXtao', d: 'nriZigdJm3VJk3rLkv416IYOc5ySVs8dZta86WyLDfo' }
const bPrivate = { kty: 'EC', crv: 'P-256', x: '_4EBvvPt0HyMogmvaFjlb21eJIrivmoJ8ObhoD35fzE', y: 'Cc7JGeKlfzR8ISbIRuEg7nobNK7Wpb2DME6dWlRx5rI', d: 'CbzYqn6qMIYfHFwglZqNiyS71pglVD0w2UAnFTAyBIw' }
const pub = (j) => ({ kty: j.kty, crv: j.crv, x: j.x, y: j.y })
const priv = (j) => crypto.subtle.importKey('jwk', j, { name: 'ECDH', namedCurve: 'P-256' }, false, ['deriveBits'])
const nodePlainB64 = 'AAAAeHsidiI6MSwidCI6IlhpbiBjaMOgbywgxJHDonkgbMOgIHRpbiB0aOG7rSDinJMiLCJ0cyI6MTc2MDAwMDAwMDAwMCwiYSI6eyJuYW1lIjoiYW5oLTEucG5nIiwidHlwZSI6ImltYWdlL3BuZyIsInNpemUiOjV9fQECAwQF'
const nodeIv = 'O4n+2mcPmFzEXR8k'
const nodeCt = 'xnIYQGMv+GgKeGl+8lfGd19IDuPX/nQwpgXC1XaNxvJPbD4mZWJPuOoBhzmCiZIb8LVUSxQnswKj67t4d8HFegD2AmXidb5ajuTcmSNKymv1EBuQv4qeZeWZ5oSpIVoqtOWUdHPVkBQpJq3B3+j94x2RtmvNuZZo78YeWnjP8UxZWhQtpjaRxYMkjgNymdNejw=='
const dartIv = 'AQIDBAUGBwgJCgsM'
const dartCt = 'COq2hOKvEMtd8vXSNrqS2n2z2P7dtUp6uEQ9ASwnYScZrEX++LHE3s95P7+MTESC+sKaefyR896ZpqLnAtRsyDPQUjpIdoaqnOKMSPFdo1uJZhBdVpIVm3HxjA=='

test('fingerprints equal the ones the app computes', async () => {
  assert.equal(await fingerprint(pub(aPrivate)), '1DEFA-E7662-4B147-83C46')
  assert.equal(await fingerprint(pub(bPrivate)), '9AF2F-C6BE3-D5586-4EE1E')
})

test('the web decrypts what the app/Vue vector holds (B -> reads A->B frame) and the AAD binds ids', async () => {
  const key = await deriveSessionKey(await priv(bPrivate), pub(aPrivate), idB, idA)
  const plain = await decryptBytes(key, { iv: nodeIv, ct: nodeCt }, { from: idA, to: idB, id: msgId })
  assert.equal(b64encode(plain), nodePlainB64)
  const m = unpackMessage(plain)
  assert.equal(m.text, 'Xin chào, đây là tin thử ✓')
  assert.equal(m.ts, 1760000000000)
  assert.deepEqual(m.att, { name: 'anh-1.png', type: 'image/png', size: 5 })
  assert.deepEqual([...m.file], [1, 2, 3, 4, 5])
  await assert.rejects(decryptBytes(key, { iv: nodeIv, ct: nodeCt }, { from: idB, to: idA, id: msgId }))
  await assert.rejects(decryptBytes(key, { iv: nodeIv, ct: nodeCt }, { from: idA, to: idB, id: 'other-id-000000' }))
})

test('the web decrypts a frame the Dart app produced (B -> A)', async () => {
  const key = await deriveSessionKey(await priv(aPrivate), pub(bPrivate), idA, idB)
  const plain = await decryptBytes(key, { iv: dartIv, ct: dartCt }, { from: idB, to: idA, id: 'DartMsgId0123456789abcd' })
  const m = unpackMessage(plain)
  assert.equal(m.text, 'Dart gửi: chào Node ✓')
  assert.equal(m.ts, 1760000001234)
  assert.deepEqual([...m.file], [9, 8, 7])
})

test('packMessage is byte-identical to the frame the app packs', () => {
  const packed = packMessage({ text: 'Xin chào, đây là tin thử ✓', ts: 1760000000000, att: { name: 'anh-1.png', type: 'image/png', size: 5 } }, new Uint8Array([1, 2, 3, 4, 5]))
  assert.equal(b64encode(packed), nodePlainB64)
})

test('the web encrypts to the exact ciphertext the app computes for the same IV', async () => {
  // encryptBytes draws a random IV: pin it so the output can be compared with the Dart vector
  const real = crypto.getRandomValues.bind(crypto)
  crypto.getRandomValues = (a) => { if (a instanceof Uint8Array && a.length === 12) { a.set([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]); return a } return real(a) }
  try {
    const key = await deriveSessionKey(await priv(aPrivate), pub(bPrivate), idA, idB)
    const env = await encryptBytes(key, packMessage({ text: 'Dart gửi: chào Node ✓', ts: 1760000001234 }, new Uint8Array([9, 8, 7])), { from: idB, to: idA, id: 'DartMsgId0123456789abcd' })
    assert.equal(env.iv, dartIv)
    assert.equal(env.ct, dartCt)
  } finally { crypto.getRandomValues = real }
})
