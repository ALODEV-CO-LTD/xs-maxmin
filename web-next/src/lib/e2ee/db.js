// Per-account IndexedDB for end-to-end encrypted chat. Everything here stays on
// this device: the private key, the decrypted history and the per-friend
// settings. Nothing is ever uploaded (docs/MA_HOA_2_DAU.md).
//   identity  {id:'self', privateKey: CryptoKey (non-extractable), publicJwk}
//   peers     {id: friendId, jwk, fingerprint, changed: bool}  last key we saw
//   messages  {id, peerId, mine, text, att:{name,type,size,isImage,blob}|null,
//              createdAt, status: sending|sent|delivered|failed, reason?}
//   meta      {id: key, value}  (unread counts, retention settings)
export function openChatDb(userId) {
  return new Promise((resolve, reject) => {
    if (typeof indexedDB === 'undefined') return reject(new Error('no-indexeddb'))
    const req = indexedDB.open(`mamba-e2ee-${userId}`, 1)
    req.onupgradeneeded = () => {
      const db = req.result
      db.createObjectStore('identity', { keyPath: 'id' })
      db.createObjectStore('peers', { keyPath: 'id' })
      const m = db.createObjectStore('messages', { keyPath: 'id' })
      m.createIndex('peer', ['peerId', 'createdAt'])
      db.createObjectStore('meta', { keyPath: 'id' })
    }
    req.onsuccess = () => resolve(req.result)
    req.onerror = () => reject(req.error)
  })
}

const done = (tx) => new Promise((res, rej) => ((tx.oncomplete = () => res()), (tx.onerror = tx.onabort = () => rej(tx.error))))
const wrap = (req) => new Promise((res, rej) => ((req.onsuccess = () => res(req.result)), (req.onerror = () => rej(req.error))))

export const get = (db, store, key) => wrap(db.transaction(store).objectStore(store).get(key))
export const getAll = (db, store) => wrap(db.transaction(store).objectStore(store).getAll())
export async function put(db, store, value) {
  const tx = db.transaction(store, 'readwrite')
  tx.objectStore(store).put(value)
  await done(tx)
}
export async function del(db, store, key) {
  const tx = db.transaction(store, 'readwrite')
  tx.objectStore(store).delete(key)
  await done(tx)
}
export const messagesOf = (db, peerId) =>
  wrap(db.transaction('messages').objectStore('messages').index('peer').getAll(IDBKeyRange.bound([peerId, 0], [peerId, Infinity])))
