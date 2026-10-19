// Unit test of the E2EE primitives (run: node tools/e2e/e2ee.mjs). No server needed.
import { decryptBytes, deriveSessionKey, encryptBytes, fingerprint, generateIdentity, newMessageId, packMessage, samePublicKey, unpackMessage } from '../../web-next/src/lib/e2ee/crypto.js'
let pass = 0, fail = 0
const ok = (c, n) => { c ? pass++ : fail++; console.log((c ? 'PASS ' : 'FAIL ') + n) }

const a = await generateIdentity(), b = await generateIdentity(), c = await generateIdentity()
ok(!('d' in a.publicJwk), 'public JWK has no private part')
let exportable = true
try { await crypto.subtle.exportKey('jwk', a.privateKey) } catch { exportable = false }
ok(!exportable, 'private key is not extractable')

const kA = await deriveSessionKey(a.privateKey, b.publicJwk, 'A', 'B')
const kB = await deriveSessionKey(b.privateKey, a.publicJwk, 'B', 'A')
const id = newMessageId()
const file = crypto.getRandomValues(new Uint8Array(1000))
const env = await encryptBytes(kA, packMessage({ text: 'xin chào', att: { name: 'a.png', type: 'image/png', size: 1000 } }, file), { from: 'A', to: 'B', id })
const got = unpackMessage(await decryptBytes(kB, env, { from: 'A', to: 'B', id }))
ok(got.text === 'xin chào' && got.att.name === 'a.png' && got.file.length === 1000 && got.file.every((v, i) => v === file[i]), 'round trip text + file')
ok(!JSON.stringify(env).includes('xin'), 'ciphertext does not contain plaintext')

const bad = async (f) => { try { await f(); return false } catch { return true } }
ok(await bad(() => decryptBytes(kB, env, { from: 'A', to: 'B', id: newMessageId() })), 'wrong message id rejected (AAD)')
ok(await bad(() => decryptBytes(kB, env, { from: 'C', to: 'B', id })), 'wrong sender rejected (AAD)')
const kC = await deriveSessionKey(c.privateKey, a.publicJwk, 'C', 'A')
ok(await bad(() => decryptBytes(kC, env, { from: 'A', to: 'B', id })), 'a third party cannot decrypt')
const tampered = { ...env, ct: env.ct.slice(0, -4) + (env.ct.endsWith('AAAA') ? 'BBBB' : 'AAAA') }
ok(await bad(() => decryptBytes(kB, tampered, { from: 'A', to: 'B', id })), 'tampered ciphertext rejected')
const env2 = await encryptBytes(kA, packMessage({ text: 'xin chào' }), { from: 'A', to: 'B', id })
ok(env2.iv !== env.iv && env2.ct !== env.ct, 'fresh IV per message')
ok((await fingerprint(a.publicJwk)) !== (await fingerprint(b.publicJwk)) && samePublicKey(a.publicJwk, { ...a.publicJwk }), 'fingerprints differ per key')
console.log(`\n${pass} passed, ${fail} failed`)
process.exit(fail ? 1 : 0)
