'use client'
// State + actions of the Nhập số screen (port of the script part of EntriesView.vue, new "points only" version).
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { api } from '../../lib/api'
import { useAuthStore } from '../../lib/authStore'
import { cachedGet, loadEntries, onEntriesChanged, updateEntry, addConflict } from '../../lib/offline'
import { loadStations, regionOf } from '../../lib/lotteryStations'
import { useStations } from '../../lib/useStations'
import { showConfirm } from '../../lib/confirm'
import { today } from '../../lib/dates'
import { writeCalcSync } from '../../lib/calcSync'
import { navigate } from '../../lib/hooks'
import {
  addedText, betTypesFor, blankRow, checkRows, editChanges, editError, entryPayload, fixRowTypes, listFor, mergeRows,
  nextUid, queuedNotice, saveItems, customerEntries,
} from './logic'

export function useEntries() {
  const user = useAuthStore((s) => s.user)
  const [entries, setEntries] = useState([])
  const [loading, setLoading] = useState(true)
  const [loadError, setLoadError] = useState('')
  const [fromCache, setFromCache] = useState(false)
  const [customers, setCustomers] = useState([])
  const [accountRates, setAccountRates] = useState({ de: {}, lo: {} })
  const [templates, setTemplates] = useState([])
  const [customerName, setCustomerName] = useState('')
  const [station, setStation] = useState('mb')
  const [rows, setRows] = useState(() => [blankRow()])
  const [note, setNote] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [formError, setFormError] = useState('')
  const [notice, setNotice] = useState('')
  const [addedMsg, setAddedMsg] = useState('')
  const [boxPrefill, setBoxPrefill] = useState(null)
  const fromChat = useRef(false)
  const forcedStation = useRef(null)
  const addedTimer = useRef(null)
  const date = today() // the day numbers are entered: always today
  useStations() // re-render when the đài catalog has loaded

  const own = customers.find((c) => c.name === customerName)?.scoringRates
  const regionId = regionOf(station).id
  const betTypes = useMemo(() => betTypesFor(accountRates, own, regionId), [accountRates, own, regionId])
  const defaultStation = customers.find((c) => c.name === customerName)?.defaultStation || 'mb'

  const setUser = (fn) => useAuthStore.setState((s) => ({ user: fn(s.user) }))
  const bumpUsed = (d) => setUser((u) => (u?.stats ? { ...u, stats: { ...u.stats, used: Math.max(u.stats.used + d, 0) } } : u))

  const flashAdded = (text) => {
    setAddedMsg(text)
    clearTimeout(addedTimer.current)
    addedTimer.current = setTimeout(() => setAddedMsg(''), 7000)
  }
  useEffect(() => () => clearTimeout(addedTimer.current), [])

  const loadAll = useCallback(async () => {
    setLoading(true)
    setLoadError('')
    try {
      const [me, list] = await Promise.all([cachedGet('/me'), loadEntries()])
      useAuthStore.setState({ user: me })
      setEntries(list.entries)
      setFromCache(list.fromCache)
    } catch (err) {
      setLoadError(err.message || 'Không tải được dữ liệu')
    } finally {
      setLoading(false)
    }
  }, [])

  // first load: list, roster, bet types, templates, and what the chat or "Thêm khách hàng" handed over
  useEffect(() => {
    let alive = true
    loadStations()
    loadAll()
    ;(async () => {
      let rates = null
      try {
        const r = (await cachedGet('/me/scoring-settings')).rates
        if (r && Object.keys(r).length) {
          rates = r
          if (alive) setAccountRates(r)
        }
      } catch { /* keep the fallback list */ }
      try {
        const list = (await cachedGet('/me/customers')).customers
        if (alive) setCustomers(list)
        const q = new URLSearchParams(window.location.search).get('customer')
        if (q && list.some((c) => c.name === q)) setCustomerName(q)
        if (q !== null) window.history.replaceState(null, '', window.location.pathname)
      } catch { /* the select shows none */ }
      try {
        if (alive) setTemplates((await cachedGet('/me/syntax-templates')).templates)
      } catch { /* parsing still works with the defaults */ }
      // "Tính toán > Dùng cho Nhập số" in the chat leaves the text for this screen (read once)
      let pre = null
      try {
        pre = JSON.parse(sessionStorage.getItem('entries-prefill') || 'null')
        sessionStorage.removeItem('entries-prefill')
      } catch { /* private mode / old format */ }
      if (alive && pre?.text) {
        fromChat.current = true
        if (pre.station) forcedStation.current = pre.station
        if (pre.customer) setCustomerName(pre.customer)
        if (pre.station) setStation(pre.station)
        setBoxPrefill(pre.text)
      }
      void rates
    })()
    const stop = onEntriesChanged(loadAll)
    return () => {
      alive = false
      stop()
    }
  }, [loadAll])

  // a customer's own default đài (unless the chat chose one)
  useEffect(() => {
    setStation(forcedStation.current || defaultStation)
    forcedStation.current = null
  }, [customerName, defaultStation])
  useEffect(() => setRows((r) => fixRowTypes(r, betTypes)), [betTypes])
  // Tính điểm opens on the customer and day chosen here
  useEffect(() => writeCalcSync({ customer: customerName, date }), [customerName, date])

  const canAdd = user?.package?.isActive !== false // an unknown package does not block (the list is still loading)
  const shown = useMemo(() => listFor(entries, { customerName, date, station }), [entries, customerName, date, station])
  const ofCustomer = useMemo(() => customerEntries(entries, customerName), [entries, customerName])
  const savedTemplate = templates.find((t) => t.customerName === customerName) || null

  // ---- manual rows
  const addRow = () => setRows((r) => [...r, blankRow(r[r.length - 1]?.type)])
  const removeRow = (uid) => setRows((r) => (r.length > 1 ? r.filter((x) => x.uid !== uid) : [blankRow(betTypes[0])]))
  const patchRow = (uid, patch) => setRows((r) => r.map((x) => (x.uid === uid ? { ...x, ...patch } : x)))
  const addRowsFromDrafts = (drafts) =>
    setRows((r) => mergeRows(r, drafts.map((d) => ({ uid: nextUid(), type: d.type, value: d.value, score: d.score }))))

  const payloadOf = (item) => entryPayload({ customerName, type: item.type, value: item.value, score: item.score, station, note, date })

  const afterSaving = (saved, failed) => {
    if (saved.length) {
      setEntries((list) => [...saved.map((s) => s.entry).reverse(), ...list])
      bumpUsed(saved.filter((s) => !s.queued).length)
    }
    const queued = saved.filter((s) => s.queued).length
    if (queued) setNotice(queuedNotice(queued))
    if (saved.length) flashAdded(addedText(saved.length, customerName, queued))
    return queued
    void failed
  }

  async function submit() {
    setFormError('')
    const check = checkRows(customerName, rows)
    if (check.error) return setFormError(check.error)
    setSubmitting(true)
    try {
      const { saved, failed } = await saveItems(check.started, payloadOf)
      afterSaving(saved, failed)
      const done = new Set(saved.map((s) => s.item.uid))
      setRows((r) => {
        const left = r.filter((x) => !done.has(x.uid))
        return left.length ? left : [blankRow(betTypes[0])]
      })
      if (failed.length) setFormError(failed.join(' · '))
      if (saved.length) setNote('')
    } finally {
      setSubmitting(false)
    }
  }

  /** Saves the ticked rows of the message / photo preview. Resolves { savedUids, error }. */
  async function saveDrafts(picked) {
    const { saved, failed } = await saveItems(picked, payloadOf)
    afterSaving(saved, failed)
    return { savedUids: saved.map((s) => s.item.uid), error: failed.join(' · '), savedCount: saved.length }
  }
  /** Once numbers that came from the chat are all saved: on to Tính điểm, open on that customer and day. */
  function finishChatFlow(savedCount) {
    if (!fromChat.current || !savedCount) return
    fromChat.current = false
    navigate(`/scoring?${new URLSearchParams({ customer: customerName.trim(), date, added: String(savedCount) })}`)
  }

  // ---- edit / delete
  async function saveEdit(entry, fields) {
    const err = editError(fields)
    if (err) return err
    const changes = editChanges(entry, fields)
    try {
      const { entry: updated, queued } = await updateEntry(entry, changes)
      setEntries((list) => list.map((e) => (e.id === entry.id ? updated : e)))
      if (queued) setNotice('Đang offline: thay đổi đã lưu trên máy, sẽ tự đồng bộ khi có mạng.')
      return ''
    } catch (e) {
      if (e.status === 409 && e.data?.conflict) {
        addConflict(entry, changes, e.data.server) // edited elsewhere meanwhile: SyncStatus asks which one to keep
        return ''
      }
      return e.message || 'Không lưu được thay đổi'
    }
  }

  /** Deletes one entry; resolves the error text ('' = done or cancelled). */
  async function deleteEntry(entry) {
    if (entry.pending) return 'Số liệu đang chờ đồng bộ, hãy đợi đồng bộ xong rồi xoá.'
    if (!(await showConfirm({ title: 'Xoá số liệu', message: `Xoá số liệu "${entry.value}" (${entry.customerName})? Không thể hoàn tác.`, confirmText: 'Xoá', danger: true }))) return ''
    try {
      await api.del(`/me/entries/${entry.id}`)
      setEntries((list) => list.filter((e) => e.id !== entry.id))
      bumpUsed(-1)
      return ''
    } catch (err) {
      return err.message || 'Không xoá được'
    }
  }
  /** Deletes every (synced) entry of the chosen customer after a confirmation; resolves an error text or ''. */
  async function deleteAll() {
    const list = ofCustomer.filter((e) => !e.pending)
    if (!list.length) return ''
    if (!(await showConfirm({ title: 'Xoá tất cả số liệu', message: `Xoá toàn bộ ${list.length} số liệu của khách hàng "${customerName}"? Không thể hoàn tác.`, confirmText: 'Xoá tất cả', danger: true }))) return ''
    let failed = 0
    for (const e of list) {
      try {
        await api.del(`/me/entries/${e.id}`)
        setEntries((all) => all.filter((x) => x.id !== e.id))
        bumpUsed(-1)
      } catch {
        failed++
      }
    }
    return failed ? `${failed} số liệu không xoá được, thử lại.` : ''
  }

  // ---- syntax templates
  async function saveTemplate(config) {
    if (!customerName) return ''
    if (!(await showConfirm({ title: 'Lưu mẫu cú pháp', message: `Lưu cách viết này làm mẫu riêng cho khách hàng "${customerName}"? Lần sau dán tin nhắn của khách này sẽ được phân tích theo mẫu.`, confirmText: 'Lưu mẫu' }))) return ''
    try {
      const saved = await api.post('/me/syntax-templates', { customerName, config })
      setTemplates((t) => [...t.filter((x) => x.customerName !== saved.customerName), saved])
      return 'Đã lưu mẫu cho khách này.'
    } catch (err) {
      return err.message || 'Không lưu được mẫu'
    }
  }
  async function deleteTemplate() {
    const t = savedTemplate
    if (!t) return ''
    try {
      await api.del(`/me/syntax-templates/${t.id}`)
      setTemplates((all) => all.filter((x) => x.id !== t.id))
      return 'Đã xoá mẫu.'
    } catch (err) {
      return err.message || 'Không xoá được mẫu'
    }
  }

  return {
    user, entries, loading, loadError, fromCache, customers, accountRates, customerName, setCustomerName, station, setStation,
    rows, note, setNote, submitting, formError, notice, setNotice, addedMsg, date, betTypes, regionId, canAdd, shown, ofCustomer,
    savedTemplate, boxPrefill, takeBoxPrefill: () => { const t = boxPrefill; setBoxPrefill(null); return t },
    addRow, removeRow, patchRow, addRowsFromDrafts, submit, saveDrafts, finishChatFlow, saveEdit, deleteEntry, deleteAll,
    saveTemplate, deleteTemplate, reload: loadAll,
  }
}
