'use client'
import './CustomersScreen.css'
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { useRouter, useSearchParams } from 'next/navigation'
import ActionBar from '@/components/ActionBar'
import AppButton from '@/components/AppButton'
import AppIcon from '@/components/AppIcon'
import AppSelect from '@/components/AppSelect'
import MaskedValue from '@/components/MaskedValue'
import ModalDialog from '@/components/ModalDialog'
import { api } from '@/lib/api'
import { showConfirm } from '@/lib/confirm'
import { allStationOptions, loadStations } from '@/lib/lotteryStations'
import { cachedGet, loadAllEntries } from '@/lib/offline'
import { DEFAULT_RATES } from '@/lib/scoringConfig'
import { useStations } from '@/lib/useStations'
import ScoringConfigEditor from '@/features/scoring/settings/ScoringConfigEditor'
import ScoringSettings from '@/features/scoring/settings/ScoringSettings'
import {
  REGION_OPTIONS, buildCustomers, createCustomer, entriesUrl, filterCustomers, formatNumber, removeConfirm,
  saveError, sortRoster, writeError,
} from './customersLogic'

/* eslint-disable @typescript-eslint/no-explicit-any */
type RosterRow = { id: string; name: string; phone?: string; defaultStation?: string; homeRegion?: string; scoringRates?: any }

// Khách hàng: danh sách khách của tài khoản (GET/POST/DELETE /me/customers) gộp với số liệu từ các lượt nhập (GET /me/entries):
// số lượt, điểm vào, điểm ra, lợi nhuận. "Thêm khách hàng" mở hộp thoại (tên, SĐT, đài mặc định); "Sửa" đổi SĐT; nút
// "Cấu hình tính điểm" mở hộp chi tiết của khách (đài mặc định, miền, bảng giá riêng); "Cấu hình tính điểm mặc định" mở
// bảng chung. Xoá chỉ xoá khỏi danh sách, số liệu đã nhập giữ nguyên. Logic thuần ở customersLogic.js.
export default function CustomersScreen() {
  const router = useRouter()
  const params = useSearchParams()
  useStations() // đài xổ số tải xong thì danh sách đài vẽ lại
  // Opened via "+ Thêm khách hàng mới" on Nhập số: after adding a customer, go back there.
  const fromEntries = params.get('from') === 'entries'

  const [newStation, setNewStation] = useState('mb')
  const [addOpen, setAddOpen] = useState(fromEntries)
  const [entries, setEntries] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [loadError, setLoadError] = useState('')
  const [fromCache, setFromCache] = useState(false) // showing the copy saved on this device (offline)
  const [search, setSearch] = useState('')
  const [expanded, setExpanded] = useState<string | null>(null)

  const [roster, setRoster] = useState<RosterRow[]>([]) // from /me/customers
  const [newCustomerName, setNewCustomerName] = useState('')
  const [newCustomerPhone, setNewCustomerPhone] = useState('')
  const [addingCustomer, setAddingCustomer] = useState(false)
  const [addError, setAddError] = useState('')
  const [deletingId, setDeletingId] = useState<string | null>(null)

  const loadRoster = useCallback(async () => {
    try {
      // cachedGet: last saved copy when offline
      const { customers: list } = await cachedGet('/me/customers')
      setRoster(list)
    } catch {
      // Non-fatal - the page still works from entries alone, just without "add new customer" until this loads.
    }
  }, [])

  // ---- Cấu hình tính điểm: riêng từng khách (nút ở từng dòng) + mặc định chung (nút trên đầu) ----
  const [accountRates, setAccountRates] = useState<Record<string, any>>({ ...DEFAULT_RATES })
  const loadAccountRates = useCallback(async () => {
    try {
      const { rates } = await cachedGet('/me/scoring-settings')
      if (rates && Object.keys(rates).length) setAccountRates(rates)
    } catch {
      /* keep the built-in fallback */
    }
  }, [])
  const [defaultConfigOpen, setDefaultConfigOpen] = useState(params.get('config') === 'default')
  const closeDefaultConfig = () => {
    setDefaultConfigOpen(false)
    void loadAccountRates()
  }

  const customers = useMemo(() => buildCustomers(roster, entries), [roster, entries])
  const filteredCustomers = useMemo(() => filterCustomers(customers, search), [customers, search])
  const detail = useMemo(() => customers.find((c) => c.name === expanded) || null, [customers, expanded])
  const rosterRow = useMemo(() => roster.find((r) => r.id === detail?.rosterId) || null, [roster, detail])
  const patchRoster = (id: string, patch: Partial<RosterRow>) => setRoster((list) => list.map((r) => (r.id === id ? { ...r, ...patch } : r)))

  // The lottery this customer plays by default: what Nhập số starts from for them.
  const [stationMsg, setStationMsg] = useState('')
  async function saveDefaultStation(code: string) {
    const row = rosterRow
    if (!row) return
    setStationMsg('')
    try {
      const res = await api.patch(`/me/customers/${row.id}`, { defaultStation: code })
      patchRoster(row.id, { defaultStation: res.defaultStation })
      setStationMsg('Đã lưu đài mặc định')
    } catch (err) {
      setStationMsg(saveError(err, 'Không lưu được đài'))
    }
  }
  // The customer's own region: decides how "Đầu" is scored on a Miền Bắc result (Bắc 1 lô = 1 điểm, Nam/Trung ×4 giải bảy).
  const [regionMsg, setRegionMsg] = useState('')
  async function saveHomeRegion(v: string) {
    const row = rosterRow
    if (!row) return
    setRegionMsg('')
    try {
      const res = await api.patch(`/me/customers/${row.id}`, { homeRegion: v })
      patchRoster(row.id, { homeRegion: res.homeRegion })
      setRegionMsg('Đã lưu miền của khách')
    } catch (err) {
      setRegionMsg(saveError(err, 'Không lưu được miền của khách'))
    }
  }
  function onCustomerConfigSaved(map: any) {
    if (rosterRow) patchRoster(rosterRow.id, { scoringRates: map })
  }

  async function addCustomer(e: React.FormEvent) {
    e.preventDefault()
    const name = newCustomerName.trim()
    if (!name) return
    setAddError('')
    setAddingCustomer(true)
    try {
      const { created, warn } = await createCustomer(api, { name, phone: newCustomerPhone.trim(), station: newStation })
      setRoster((list) => sortRoster([...list, created]))
      if (warn) setAddError(warn)
      else setAddOpen(false)
      setNewCustomerName('')
      setNewCustomerPhone('')
      setNewStation('mb')
      if (fromEntries) {
        router.push(entriesUrl(created.name))
        return
      }
    } catch (err) {
      setAddError(writeError(err, 'Không thêm được khách hàng'))
    } finally {
      setAddingCustomer(false)
    }
  }

  async function removeCustomer(id: string, name: string) {
    if (!(await showConfirm(removeConfirm(name)))) return
    setDeletingId(id)
    try {
      await api.del(`/me/customers/${id}`)
      setRoster((list) => list.filter((c) => c.id !== id))
    } catch (err) {
      setAddError(writeError(err, 'Không xoá được'))
    } finally {
      setDeletingId(null)
    }
  }

  const load = useCallback(async () => {
    setLoading(true)
    setLoadError('')
    try {
      // every page of the history (counts/totals must not miss old records); the saved copy when offline
      const list = await loadAllEntries()
      setEntries(list.entries)
      setFromCache(list.fromCache)
    } catch (err) {
      setLoadError((err as Error).message || 'Không tải được số liệu')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    loadStations()
    // eslint-disable-next-line react-hooks/set-state-in-effect -- first load of the three lists
    void load()
    void loadRoster()
    void loadAccountRates()
  }, [load, loadRoster, loadAccountRates])

  // The detail box owns one history entry while open, so the browser/phone Back button closes the box instead of leaving
  // the page. Closing by button/Esc/overlay removes that entry again (history.back) so no ping-pong state is left behind.
  const detailHistory = useRef(false)
  useEffect(() => {
    const onKeydown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setExpanded(null)
    }
    const onPopState = () => {
      if (detailHistory.current) {
        detailHistory.current = false // the entry was already popped by the browser
        setExpanded(null)
      }
    }
    window.addEventListener('keydown', onKeydown)
    window.addEventListener('popstate', onPopState)
    return () => {
      window.removeEventListener('keydown', onKeydown)
      window.removeEventListener('popstate', onPopState)
    }
  }, [])
  const detailOpen = !!detail
  useEffect(() => {
    if (detailOpen && !detailHistory.current) {
      history.pushState({ ...history.state, customerDetail: true }, '')
      detailHistory.current = true
    } else if (!detailOpen && detailHistory.current) {
      detailHistory.current = false
      history.back()
    }
  }, [detailOpen])
  const detailBox = useRef<HTMLDivElement>(null)
  useEffect(() => {
    if (expanded) detailBox.current?.focus()
  }, [expanded])

  // "Sửa": edit a customer's phone number in a small dialog.
  const [editing, setEditing] = useState<any>(null) // the table row being edited
  const [phoneDraft, setPhoneDraft] = useState('')
  const [phoneMsg, setPhoneMsg] = useState('')
  const [savingPhone, setSavingPhone] = useState(false)
  function openEdit(c: any) {
    setEditing(c)
    setPhoneDraft(c.phone || '')
    setPhoneMsg('')
  }
  async function savePhone(e: React.FormEvent) {
    e.preventDefault()
    const c = editing
    if (!c?.rosterId) return
    setSavingPhone(true)
    setPhoneMsg('')
    try {
      const res = await api.patch(`/me/customers/${c.rosterId}`, { phone: phoneDraft.trim() })
      patchRoster(c.rosterId, { phone: res.phone })
      setEditing(null)
    } catch (err) {
      setPhoneMsg(writeError(err, 'Không lưu được số điện thoại'))
    } finally {
      setSavingPhone(false)
    }
  }

  const stationOptions = allStationOptions()
  const closeAdd = () => {
    setAddOpen(false)
    setAddError('')
  }

  return (
    <div className="page customers-page">
      <h1 className="page-title">Khách hàng</h1>
      <p className="page-subtitle">Danh sách khách hàng của bạn. Bấm &quot;Thêm khách hàng&quot; để thêm khách mới; số liệu vào/ra được tổng hợp từ các lượt nhập.</p>

      {fromCache && <div className="alert alert-warning">Đang offline: hiển thị số liệu đã lưu trên máy. Thêm/xoá khách hàng cần có mạng.</div>}
      {loading ? (
        <div className="card">Đang tải...</div>
      ) : loadError ? (
        <div className="alert alert-error">{loadError}</div>
      ) : (
        <>
          <div className="config-row">
            <AppButton variant="primary" size="sm" onClick={() => setAddOpen(true)}>+ Thêm khách hàng</AppButton>
            <AppButton variant="secondary" size="sm" onClick={() => setDefaultConfigOpen(true)}>Cấu hình tính điểm mặc định</AppButton>
          </div>
          <div className="field search-field">
            <div className="input-wrap">
              <AppIcon name="search" className="search-icon" />
              <input value={search} onChange={(e) => setSearch(e.target.value)} type="text" placeholder="Tìm theo tên khách hàng..." />
            </div>
          </div>

          {customers.length === 0 ? (
            <div className="card">Chưa có khách hàng nào. Bấm &quot;Thêm khách hàng&quot; để bắt đầu.</div>
          ) : filteredCustomers.length === 0 ? (
            <div className="card">Không tìm thấy khách hàng phù hợp.</div>
          ) : (
            <div className="table-wrap">
              <table className="table stack-table">
                <thead>
                  <tr>
                    <th>STT</th>
                    <th>Tên</th>
                    <th>SĐT</th>
                    <th>Điểm đầu vào</th>
                    <th>Điểm đầu ra</th>
                    <th>Lợi nhuận</th>
                    <th>Thao tác</th>
                  </tr>
                </thead>
                <tbody>
                  {filteredCustomers.map((c: any, i: number) => (
                    <tr key={c.name} className="row-clickable" onClick={() => setExpanded(c.name)}>
                      <td data-label="STT">{i + 1}</td>
                      <td data-label="Tên">{c.name}</td>
                      <td data-label="SĐT">{c.phone || '-'}</td>
                      <td data-label="Điểm đầu vào"><MaskedValue text={formatNumber(c.vao)} /></td>
                      <td data-label="Điểm đầu ra"><MaskedValue text={formatNumber(c.ra)} /></td>
                      <td data-label="Lợi nhuận" className={c.chenhLech >= 0 ? 'calc-in' : 'calc-out'}><MaskedValue text={formatNumber(c.chenhLech)} /></td>
                      <td className="actions-cell">
                        {c.rosterId && <AppButton variant="secondary" size="sm" onClick={(e) => { e.stopPropagation(); openEdit(c) }}>Sửa</AppButton>}
                        <button type="button" className="btn btn-secondary btn-sm btn-detail" onClick={(e) => { e.stopPropagation(); setExpanded(c.name) }}>
                          Cấu hình tính điểm
                        </button>
                        {c.rosterId ? (
                          <button type="button" className="btn btn-ghost btn-sm btn-remove" disabled={deletingId === c.rosterId} onClick={(e) => { e.stopPropagation(); void removeCustomer(c.rosterId, c.name) }}>
                            {deletingId === c.rosterId ? 'Đang xoá...' : 'Xoá khỏi danh sách'}
                          </button>
                        ) : (
                          <span className="muted-note" title="Khách này chỉ xuất hiện trong số liệu đã nhập, chưa được thêm vào danh sách" />
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </>
      )}

      <ModalDialog open={defaultConfigOpen} title="Cấu hình tính điểm mặc định" xwide back onClose={closeDefaultConfig}>
        <ScoringSettings embedded onSaved={() => void loadAccountRates()} />
      </ModalDialog>

      <ModalDialog open={addOpen} title="Thêm khách hàng" onClose={closeAdd}>
        <form className="add-dialog-form" onSubmit={addCustomer}>
          <div className="field">
            <label htmlFor="add-name">Tên khách hàng</label>
            <div className="input-wrap">
              <input id="add-name" value={newCustomerName} onChange={(e) => setNewCustomerName(e.target.value)} type="text" placeholder="Tên khách hàng" disabled={addingCustomer} data-autofocus />
            </div>
          </div>
          <div className="field">
            <label htmlFor="add-phone">Số điện thoại</label>
            <div className="input-wrap">
              <input id="add-phone" value={newCustomerPhone} onChange={(e) => setNewCustomerPhone(e.target.value)} type="tel" inputMode="tel" placeholder="Không bắt buộc" disabled={addingCustomer} />
            </div>
          </div>
          <div className="field">
            <label>Đài xổ số mặc định khi nhập số</label>
            <AppSelect value={newStation} onChange={setNewStation} aria-label="Đài mặc định">
              {stationOptions.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
            </AppSelect>
          </div>
          <p className="page-subtitle" style={{ margin: '0 0 12px' }}>Cấu hình tính điểm của khách đặt sau, ở nút &quot;Cấu hình tính điểm&quot; trong danh sách.</p>
          {addError && <div className="alert alert-error add-customer-error">{addError}</div>}
          <ActionBar align="end">
            <AppButton variant="ghost" disabled={addingCustomer} onClick={closeAdd}>Huỷ</AppButton>
            <AppButton variant="primary" type="submit" loading={addingCustomer} disabled={!newCustomerName.trim()}>{addingCustomer ? 'Đang thêm...' : 'Thêm khách hàng'}</AppButton>
          </ActionBar>
        </form>
      </ModalDialog>

      <ModalDialog open={!!editing} title={editing ? `Sửa ${editing.name}` : ''} onClose={() => setEditing(null)}>
        <form className="cd-phone" onSubmit={savePhone}>
          <label>
            Số điện thoại
            <input value={phoneDraft} onChange={(e) => setPhoneDraft(e.target.value)} type="tel" inputMode="tel" placeholder="Chưa có" disabled={savingPhone} data-autofocus />
          </label>
          <AppButton variant="primary" type="submit" disabled={savingPhone || phoneDraft.trim() === (editing?.phone || '')}>{savingPhone ? 'Đang lưu...' : 'Lưu'}</AppButton>
        </form>
        {phoneMsg && <p className="alert alert-error" role="alert" style={{ marginTop: 10 }}>{phoneMsg}</p>}
      </ModalDialog>

      {detail && typeof document !== 'undefined' && createPortal(
        <div
          className="cd-overlay"
          onMouseDown={(e) => e.target === e.currentTarget && setExpanded(null)}
          onKeyDown={(e) => e.key === 'Escape' && setExpanded(null)}
        >
          <div className="cd-box" role="dialog" aria-modal="true" aria-labelledby="cd-title" tabIndex={-1} ref={detailBox}>
            <div className="cd-head">
              <button type="button" className="cd-close" aria-label="Đóng" title="Đóng" onClick={() => setExpanded(null)}>
                <AppIcon name="arrow-left" />
              </button>
              <h2 id="cd-title" className="cd-name">{detail.name}</h2>
            </div>
            <div className="cd-top">
              {detail.rosterId && rosterRow && (
                <section className="cd-station" aria-label="Đài mặc định">
                  <label className="cd-station-label">Đài xổ số mặc định khi nhập số cho khách này</label>
                  <div className="cd-station-row">
                    <AppSelect value={rosterRow.defaultStation || 'mb'} onChange={saveDefaultStation} aria-label="Đài mặc định">
                      {stationOptions.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
                    </AppSelect>
                    {stationMsg && <span className="muted-note" role="status">{stationMsg}</span>}
                  </div>
                </section>
              )}
              {detail.rosterId && rosterRow && (
                <section className="cd-station" aria-label="Miền của khách">
                  <label className="cd-station-label">Khách thuộc miền nào (để tính Đầu ở đài Miền Bắc)</label>
                  <div className="cd-station-row">
                    <AppSelect value={rosterRow.homeRegion || ''} onChange={saveHomeRegion} aria-label="Miền của khách">
                      {REGION_OPTIONS.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
                    </AppSelect>
                    {regionMsg && <span className="muted-note" role="status">{regionMsg}</span>}
                  </div>
                </section>
              )}
            </div>
            {detail.rosterId && rosterRow && (
              <section className="cd-config" aria-label="Cấu hình tính điểm của khách này">
                <h3 className="cd-config-title">Cấu hình tính điểm của khách này{rosterRow.scoringRates ? ' (có cấu hình riêng)' : ''}</h3>
                <ScoringConfigEditor scope="customer" customer={rosterRow} accountRates={accountRates} onSaved={onCustomerConfigSaved} />
              </section>
            )}
          </div>
        </div>,
        document.body,
      )}
    </div>
  )
}
