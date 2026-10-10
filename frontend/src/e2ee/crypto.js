// End-to-end encryption primitives (docs/MA_HOA_2_DAU.md). WebCrypto only, no
// dependencies, and no DOM use so it also runs under Node for tests.
//
//   identity   ECDH P-256 key pair per device; the private key is created
//              non-extractable and never leaves the device.
//   session    ECDH(my private, friend public) -> HKDF-SHA-256 -> AES-256-GCM key
//              (salt = hash of the two user ids, so both sides derive the same key).
//   message    AES-GCM, fresh random 96-bit IV per message, the sender/recipient/
//              message ids are authenticated as AAD so a ciphertext cannot be
//              replayed under another id or between other people.
//
// Known limit: static per-device keys give no forward secrecy (a later key
// compromise decrypts recorded traffic). A ratchet is the next step.
const subtle = globalThis.crypto.subtle
const enc = new TextEncoder()
const dec = new TextDecoder()
const CURVE = { name: 'ECDH', namedCurve: 'P-256' }
const INFO = enc.encode('mamba-e2ee-v1')

export function b64encode(bytes) {
  let s = ''
  const u8 = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes)
  for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode(...u8.subarray(i, i + 0x8000))
  return btoa(s)
}
export function b64decode(str) {
  const bin = atob(str)
  const out = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i)
  return out
}

const pickPublic = (jwk) => ({ kty: jwk.kty, crv: jwk.crv, x: jwk.x, y: jwk.y })

export async function generateIdentity() {
  const pair = await subtle.generateKey(CURVE, false, ['deriveBits'])
  return { privateKey: pair.privateKey, publicJwk: pickPublic(await subtle.exportKey('jwk', pair.publicKey)) }
}

export const samePublicKey = (a, b) => !!a && !!b && a.x === b.x && a.y === b.y

// Short code both people can read out to check they hold each other's real key.
export async function fingerprint(jwk) {
  const hash = new Uint8Array(await subtle.digest('SHA-256', enc.encode(`${jwk.x}.${jwk.y}`)))
  const hex = Array.from(hash.subarray(0, 10), (b) => b.toString(16).padStart(2, '0')).join('').toUpperCase()
  return hex.match(/.{1,5}/g).join('-')
}

// AES key shared by `myId` and `peerId`.
export async function deriveSessionKey(myPrivateKey, peerPublicJwk, myId, peerId) {
  const peerKey = await subtle.importKey('jwk', pickPublic(peerPublicJwk), CURVE, false, [])
  const bits = await subtle.deriveBits({ name: 'ECDH', public: peerKey }, myPrivateKey, 256)
  const hkdfKey = await subtle.importKey('raw', bits, 'HKDF', false, ['deriveKey'])
  const salt = new Uint8Array(await subtle.digest('SHA-256', enc.encode([myId, peerId].sort().join('|'))))
  return subtle.deriveKey({ name: 'HKDF', hash: 'SHA-256', salt, info: INFO }, hkdfKey, { name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt'])
}

const aad = (from, to, id) => enc.encode(`${from}|${to}|${id}`)

export async function encryptBytes(key, plaintext, { from, to, id }) {
  const iv = globalThis.crypto.getRandomValues(new Uint8Array(12))
  const ct = await subtle.encrypt({ name: 'AES-GCM', iv, additionalData: aad(from, to, id) }, key, plaintext)
  return { iv: b64encode(iv), ct: b64encode(ct) }
}

export async function decryptBytes(key, { iv, ct }, { from, to, id }) {
  const plain = await subtle.decrypt({ name: 'AES-GCM', iv: b64decode(iv), additionalData: aad(from, to, id) }, key, b64decode(ct))
  return new Uint8Array(plain)
}

// Plaintext frame: [4-byte header length][header JSON][raw file bytes]. Keeping the
// file as raw bytes (not base64) leaves room for a 5 MB file under the relay's cap.
export function packMessage({ text = '', ts = Date.now(), att = null }, fileBytes = null) {
  const header = enc.encode(JSON.stringify({ v: 1, t: text, ts, a: att }))
  const out = new Uint8Array(4 + header.length + (fileBytes ? fileBytes.length : 0))
  new DataView(out.buffer).setUint32(0, header.length)
  out.set(header, 4)
  if (fileBytes) out.set(fileBytes, 4 + header.length)
  return out
}

export function unpackMessage(bytes) {
  const len = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(0)
  if (len > bytes.length - 4) throw new Error('bad frame')
  const header = JSON.parse(dec.decode(bytes.subarray(4, 4 + len)))
  if (header.v !== 1) throw new Error('unsupported version')
  return { text: String(header.t || ''), ts: Number(header.ts) || Date.now(), att: header.a || null, file: bytes.subarray(4 + len) }
}

export function newMessageId() {
  return b64encode(globalThis.crypto.getRandomValues(new Uint8Array(16))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}
