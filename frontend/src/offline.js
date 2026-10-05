// Basic offline support (K14 / S07 / NFR-02 / NFR-06).
//
// What works without a network:
//   - entering records (Nhập số): they are saved in IndexedDB ("queue") and
//     shown straight away flagged as pending,
//   - editing a record (queued the same way),
//   - viewing the history that was last loaded (cached copy of GET /me/entries,
//     customers, profile...) and searching/filtering it locally.
// When the connection comes back the queue is replayed in order. Creates carry
// a client-chosen id (`clientId`) so a retry after a lost response can never
// create a duplicate. An edit carries the `updatedAt` it was based on; if the
// server copy changed meanwhile the server answers 409 and the user is asked
// (see SyncStatus.vue) whether to keep their version or the server's.
//
// Deliberately NOT synced / not available offline: chat, voice calls,
// deleting records, anything admin.
import { reactive } from 'vue'
import { api, ApiError } from './api'
import { useAuthStore } from './stores/auth'

export const syncState = reactive({
  online: typeof navigator === 'undefined' ? true : navigator.onLine,
  syncing: false,
  pending: 0, // queued operations of the current user
  conflicts: [], // [{ opId, entryId, mine, server }] waiting for the user's choice
  failures: [], // [{ id, message }] operations the server rejected (not retried)
})

// ---- tiny IndexedDB wrapper (stores: queue, kv) ---------------------------

let dbPromise = null
function openDb() {
  if (!dbPromise) {
    dbPromise = new Promise((resolve, reject) => {
      if (typeof indexedDB === 'undefined') {
        reject(new Error('IndexedDB không khả dụng'))
        return
      }
      const req = indexedDB.open('xoso-offline', 1)
      req.onupgradeneeded = () => {
        const db = req.result
        if (!db.objectStoreNames.contains('queue')) db.createObjectStore('queue', { keyPath: 'opId' })
        if (!db.objectStoreNames.contains('kv')) db.createObjectStore('kv', { keyPath: 'key' })
      }
      req.onsuccess = () => resolve(req.result)
      req.onerror = () => reject(req.error)
    })
  }
  return dbPromise
}

async function tx(store, mode, fn) {
  const db = await openDb()
  return new Promise((resolve, reject) => {
    const t = db.transaction(store, mode)
    const result = fn(t.objectStore(store))
    t.oncomplete = () => resolve(result?.result)
    t.onerror = () => reject(t.error)
    t.onabort = () => reject(t.error)
  })
}

async function kvGet(key) {
  try {
    const row = await tx('kv', 'readonly', (s) => s.get(key))
    return row ? row.value : null
  } catch {
    return null
  }
}
async function kvSet(key, value) {
  try {
    await tx('kv', 'readwrite', (s) => s.put({ key, value }))
  } catch {
    /* cache is best-effort */
  }
}

async function queueAll() {
  try {
    const all = (await tx('queue', 'readonly', (s) => s.getAll())) || []
    return all.sort((a, b) => a.seq - b.seq)
  } catch {
    return []
  }
}
const queuePut = (op) => tx('queue', 'readwrite', (s) => s.put(op))
const queueDelete = (opId) => tx('queue', 'readwrite', (s) => s.delete(opId))

// ---- helpers --------------------------------------------------------------

// The queue/caches are per account: the user id is the JWT `sub`.
function currentUserId() {
  const token = useAuthStore().token
  if (!token) return null
  try {
    const payload = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')
    return JSON.parse(atob(payload)).sub || null
  } catch {
    return null
  }
}

const isNetworkError = (err) => err instanceof ApiError && err.status === 0

function newUuid() {
  if (globalThis.crypto?.randomUUID) return crypto.randomUUID()
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0
    return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16)
  })
}

let seqCounter = 0
const nextSeq = () => Date.now() * 1000 + (seqCounter++ % 1000)

const listeners = new Set()
/** Called after the queue was replayed / a conflict was resolved so views can reload. */
export function onEntriesChanged(cb) {
  listeners.add(cb)
  return () => listeners.delete(cb)
}
const notify = () => listeners.forEach((cb) => cb())

async function userOps() {
  const uid = currentUserId()
  return (await queueAll()).filter((op) => op.userId === uid)
}
export async function refreshPending() {
  syncState.pending = (await userOps()).length
}

function markOffline() {
  syncState.online = false
}

// ---- cached GETs (profile, customers, bet types...) ----------------------

/** GET with a cached fallback: returns the fresh response, or the last
 *  cached one when the network is down (throws only if there is neither). */
export async function cachedGet(path) {
  const key = `get:${currentUserId()}:${path}`
  try {
    const data = await api.get(path)
    syncState.online = true
    kvSet(key, data)
    return data
  } catch (err) {
    if (!isNetworkError(err)) throw err
    markOffline()
    const cached = await kvGet(key)
    if (cached) return cached
    throw err
  }
}

// ---- entries --------------------------------------------------------------

// Server list + not-yet-synced operations laid over it, so the user sees
// their own offline work immediately.
async function overlayPending(list) {
  const ops = (await userOps()).filter((op) => !op.conflict)
  let out = [...list]
  for (const op of ops) {
    if (op.type === 'create') {
      if (!out.some((e) => e.id === op.entryId)) out.unshift({ ...op.payload, id: op.entryId, createdAt: op.createdAt, updatedAt: op.createdAt })
    } else if (op.type === 'patch') {
      out = out.map((e) => (e.id === op.entryId ? { ...e, ...op.payload } : e))
    }
  }
  const pendingIds = new Set(ops.map((op) => op.entryId))
  return out.map((e) => (pendingIds.has(e.id) ? { ...e, pending: true } : e))
}

/** Loads the entry history; falls back to the cached copy when offline. */
export async function loadEntries() {
  const key = `entries:${currentUserId()}`
  try {
    const { entries } = await api.get('/me/entries')
    syncState.online = true
    kvSet(key, entries)
    await refreshPending()
    return { entries: await overlayPending(entries), fromCache: false }
  } catch (err) {
    if (!isNetworkError(err)) throw err
    markOffline()
    const cached = await kvGet(key)
    await refreshPending()
    return { entries: await overlayPending(cached || []), fromCache: true }
  }
}

async function cacheEntryLocally(entry) {
  const key = `entries:${currentUserId()}`
  const cached = (await kvGet(key)) || []
  const i = cached.findIndex((e) => e.id === entry.id)
  if (i === -1) cached.unshift(entry)
  else cached[i] = entry
  await kvSet(key, cached)
}

/** Creates an entry; when the network is down it is queued instead.
 *  Resolves `{ entry, queued }`. Other errors (quota, validation) are thrown. */
export async function createEntry(payload) {
  const entryId = newUuid()
  try {
    const entry = await api.post('/me/entries', { ...payload, clientId: entryId })
    syncState.online = true
    cacheEntryLocally(entry)
    return { entry, queued: false }
  } catch (err) {
    if (!isNetworkError(err)) throw err
    markOffline()
    const createdAt = new Date().toISOString()
    await queuePut({
      opId: newUuid(),
      seq: nextSeq(),
      userId: currentUserId(),
      type: 'create',
      entryId,
      payload: { ...payload },
      createdAt,
    })
    await refreshPending()
    return { entry: { ...payload, id: entryId, createdAt, updatedAt: createdAt, pending: true }, queued: true }
  }
}

/** Edits an entry (`changes` = fields to PATCH). Offline -> queued; a still
 *  unsynced create just absorbs the change. 409 conflicts from the server are
 *  thrown as ApiError with `.data.conflict` for the caller to hand to
 *  `addConflict`. Resolves `{ entry, queued }`. */
export async function updateEntry(entry, changes) {
  const ops = await userOps()
  const pendingCreate = ops.find((op) => op.type === 'create' && op.entryId === entry.id)
  if (pendingCreate) {
    pendingCreate.payload = { ...pendingCreate.payload, ...changes }
    await queuePut(pendingCreate)
    return { entry: { ...entry, ...changes, pending: true }, queued: true }
  }
  const pendingPatch = ops.find((op) => op.type === 'patch' && op.entryId === entry.id)
  if (!pendingPatch) {
    try {
      const updated = await api.patch(`/me/entries/${entry.id}`, { ...changes, baseUpdatedAt: entry.updatedAt })
      syncState.online = true
      cacheEntryLocally(updated)
      return { entry: updated, queued: false }
    } catch (err) {
      if (!isNetworkError(err)) throw err
      markOffline()
    }
  }
  // offline (or an earlier edit is already waiting): queue / merge
  if (pendingPatch) {
    pendingPatch.payload = { ...pendingPatch.payload, ...changes }
    await queuePut(pendingPatch)
  } else {
    await queuePut({
      opId: newUuid(),
      seq: nextSeq(),
      userId: currentUserId(),
      type: 'patch',
      entryId: entry.id,
      baseUpdatedAt: entry.updatedAt,
      payload: { ...changes },
      createdAt: new Date().toISOString(),
    })
  }
  await refreshPending()
  return { entry: { ...entry, ...changes, pending: true }, queued: true }
}

// ---- sync -----------------------------------------------------------------

/** Registers a conflict found while editing online (no queued op behind it). */
export function addConflict(entry, mine, server) {
  syncState.conflicts.push({ opId: null, entryId: entry.id, mine, server })
}

/** Replays the queue. Safe to call any time; does nothing while offline. */
export async function flushQueue() {
  if (syncState.syncing) return
  const uid = currentUserId()
  if (!uid) return
  syncState.syncing = true
  let changed = false
  try {
    for (const op of await userOps()) {
      if (op.conflict) continue
      try {
        if (op.type === 'create') {
          await api.post('/me/entries', { ...op.payload, clientId: op.entryId })
        } else {
          await api.patch(`/me/entries/${op.entryId}`, { ...op.payload, baseUpdatedAt: op.baseUpdatedAt })
        }
        await queueDelete(op.opId)
        changed = true
        syncState.online = true
      } catch (err) {
        if (isNetworkError(err)) {
          markOffline()
          break
        }
        // 401 (session gone) / 5xx (server hiccup): keep the queue, retry later
        if (err instanceof ApiError && (err.status === 401 || err.status >= 500)) break
        if (err instanceof ApiError && err.status === 409 && err.data?.conflict) {
          op.conflict = true
          await queuePut(op)
          if (!syncState.conflicts.some((c) => c.opId === op.opId)) {
            syncState.conflicts.push({ opId: op.opId, entryId: op.entryId, mine: op.payload, server: err.data.server })
          }
          continue
        }
        // The server refused it for good (quota, deleted entry, invalid...):
        // drop it so it cannot block the queue, and tell the user.
        await queueDelete(op.opId)
        changed = true
        syncState.failures.push({
          id: op.opId,
          message: `Không đồng bộ được "${op.payload?.value ?? ''}": ${err.message || 'lỗi không rõ'}`,
        })
      }
    }
  } finally {
    syncState.syncing = false
    await refreshPending()
  }
  if (changed) notify()
}

/** The user's decision for a conflict: keep `mine` (overwrite) or `server`. */
export async function resolveConflict(conflict, choice) {
  const dropFromList = () => {
    syncState.conflicts = syncState.conflicts.filter((c) => c !== conflict)
  }
  try {
    if (choice === 'mine') {
      const updated = await api.patch(`/me/entries/${conflict.entryId}`, { ...conflict.mine, force: true })
      cacheEntryLocally(updated)
    } else {
      cacheEntryLocally(conflict.server)
    }
    if (conflict.opId) await queueDelete(conflict.opId)
    dropFromList()
    await refreshPending()
    notify()
  } catch (err) {
    if (isNetworkError(err)) {
      markOffline()
      throw new ApiError(0, 'Đang offline, thử lại khi có mạng')
    }
    throw err
  }
}

export function dismissFailure(id) {
  syncState.failures = syncState.failures.filter((f) => f.id !== id)
}

let started = false
let timer = null
/** Starts the connectivity listeners + periodic retry. Call once (AppShell). */
export function startSync() {
  if (started) return
  started = true
  window.addEventListener('online', () => {
    syncState.online = true
    flushQueue()
  })
  window.addEventListener('offline', () => {
    syncState.online = false
  })
  timer = setInterval(async () => {
    if (syncState.pending > 0 || !syncState.online) {
      // a cheap probe: any answer from the server (even 401) means we are online
      try {
        await fetch('/api/announcements', { method: 'GET', cache: 'no-store' })
        syncState.online = true
      } catch {
        syncState.online = false
        return
      }
      flushQueue()
    }
  }, 20000)
  refreshPending().then(() => {
    if (syncState.pending > 0 && navigator.onLine) flushQueue()
  })
}

export function stopSync() {
  if (timer) clearInterval(timer)
  timer = null
  started = false
}
