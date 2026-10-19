/* eslint-disable @typescript-eslint/no-explicit-any */
'use client'
import './ScoringScreen.css'
import Link from 'next/link'
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import AppButton from '@/components/AppButton'
import AppDatePicker from '@/components/AppDatePicker'
import AppIcon from '@/components/AppIcon'
import AppSelect from '@/components/AppSelect'
import MaskedValue from '@/components/MaskedValue'
import ModalDialog from '@/components/ModalDialog'
import { api } from '@/lib/api'
import { betTypeLabel } from '@/lib/betTypes'
import { readCalcSync } from '@/lib/calcSync'
import { localDateString } from '@/lib/dates'
import { entryStations, isRegionCode, loadStations, regionOf, stationName } from '@/lib/lotteryStations'
import { useMasked } from '@/lib/maskStore'
import { loadAllEntries } from '@/lib/offline'
import { DEFAULT_RATES } from '@/lib/scoringConfig'
import { summarize } from '@/lib/scoringSummary'
import { useStations } from '@/lib/useStations'
import DeleteDataDialog from './DeleteDataDialog'
import DeletionSchedules from './DeletionSchedules'
import ScoringSummary from './ScoringSummary'
import {
  PAGE_DAYS, addedNotice, areaName, buildDays, computeOne, dayLabel, emptyMessage, filterEntries, filterMissing, formatNumber, isOpen,
  lrKey, money, openKey, rangeForDay, singleDayOf,
} from './scoringLogic'

// Tính điểm: tab riêng, tách khỏi "Nhập kết quả" (ResultsView giữ form nhập kết quả xổ số). Màn này tự động hoàn toàn - không
// ô nhập, không nút lưu. Hiện số liệu của MỘT khách gom theo NGÀY (mới nhất trước, ngày mới nhất mở sẵn, ngày cũ thu gọn),
// kèm tổng từng ngày. Với mỗi dòng của ngày đang MỞ: tra kết quả xổ số đã lưu của chính ngày/đài đó (nhớ theo ngày+đài); chưa
// có thì "Chưa có kết quả" và không ghi gì; có thì so N chữ số cuối (cấu hình theo kiểu đánh) với các giải cấu hình, nhân tỉ lệ,
// và PATCH vào `data_entries.result` - chỉ khi khác số đang lưu. Ngày chỉ được tính khi mở.
// Ẩn số liệu: số hiện "••••" khi bật mask (lib/maskStore.js). "Xóa số liệu", "Đặt lịch xóa": đều cần mật khẩu.
// API: GET /lottery-results?date=&station=, GET /me/scoring-settings, GET /me/entries, GET /me/customers,
//      PATCH /me/entries/:id chỉ `{ result }`, POST /me/entries/bulk-delete, /me/deletion-schedules (trong DeletionSchedules).

type Status = { state: 'computing' | 'no-lottery' | 'saved' | 'error'; value: number | null; error?: string }

export default function ScoringScreen() {
  const [entries, setEntries] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [loadError, setLoadError] = useState('')
  // Phải chọn MỘT khách trước khi hiện gì - màn này là chỗ làm việc theo khách (như Nhập số), không phải danh sách mọi người.
  const [selectedCustomer, setSelectedCustomer] = useState('')
  const [customers, setCustomers] = useState<any[]>([])
  const onlyMissing = false // bản Vue không còn ô lọc này
  const regionFilter = 'all'
  // Mở ở hôm nay; "ngày" là một giá trị (màn chỉ hỏi khách và ngày).
  const [dateFrom, setDateFrom] = useState(() => localDateString())
  const [dateTo, setDateTo] = useState(() => localDateString())
  const day = singleDayOf(dateFrom, dateTo)
  const setDay = (v: string) => {
    const [f, t] = rangeForDay(v)
    setDateFrom(f)
    setDateTo(t)
  }
  const [shownDays, setShownDays] = useState(PAGE_DAYS)
  const [openState, setOpenState] = useState<Record<string, boolean>>({})
  const [rates, setRates] = useState<any>({ ...DEFAULT_RATES })
  const [calcVersion, setCalcVersion] = useState(0)
  const [autoCalcRunning, setAutoCalcRunning] = useState(0)
  const [autoCalcError, setAutoCalcError] = useState('')
  const [deleteOpen, setDeleteOpen] = useState(false)
  const [deleteDay, setDeleteDay] = useState('')
  const [scheduleOpen, setScheduleOpen] = useState(false)
  const [notice, setNotice] = useState('')

  const masked = useMasked()
  const { regions } = useStations()

  // `${ngày}|${đài}` -> kết quả | null; entry.id -> trạng thái tính. Là bộ nhớ đổi tại chỗ (ref) + số phiên bản để vẽ lại.
  const cache = useRef<Record<string, any>>({})
  const statuses = useRef<Record<string, Status>>({})
  const [cacheView, setCacheView] = useState<Record<string, any>>({})
  const [statusView, setStatusView] = useState<Record<string, Status>>({})
  const syncCache = () => setCacheView({ ...cache.current })
  const syncStatus = () => setStatusView({ ...statuses.current })
  const calculated = useRef(new Set<string>())

  // Mỗi khách có thể có cấu hình tính điểm riêng (sửa ở Khách hàng); cấu hình của tài khoản là mặc định.
  const customerRow = customers.find((c) => c.name === selectedCustomer)
  const customerRates = customerRow?.scoringRates || null
  const customerRegion = customerRow?.homeRegion || null
  const ctx = useMemo(() => ({ rates, customerRates, customerRegion }), [rates, customerRates, customerRegion])

  // Reset số ngày đang hiện khi đổi khách / khoảng ngày (chỉnh state lúc vẽ, không cần effect).
  const filterKey = `${selectedCustomer}|${dateFrom}|${dateTo}|${onlyMissing}|${regionFilter}`
  const [prevFilterKey, setPrevFilterKey] = useState(filterKey)
  if (prevFilterKey !== filterKey) {
    setPrevFilterKey(filterKey)
    setShownDays(PAGE_DAYS)
  }

  const rangeEntries = useMemo(
    () => (void regions, filterEntries(entries, { customer: selectedCustomer, region: regionFilter, from: dateFrom, to: dateTo })),
    [entries, selectedCustomer, dateFrom, dateTo, regions],
  )
  const allDays = useMemo(() => (void regions, buildDays(rangeEntries, cacheView, statusView, ctx)), [rangeEntries, cacheView, statusView, ctx, regions])
  const days = useMemo(() => filterMissing(allDays, onlyMissing), [allDays, onlyMissing])
  const getResult = useCallback((date: string, station: string) => cacheView[lrKey(date, station)], [cacheView])
  // Cách nhìn bằng tiền của từng ngày (scoringSummary.js): lô, tiền gửi, tiền trúng, còn lại.
  const dayMoney = useMemo(
    () => Object.fromEntries(days.map((d: any) => [d.date, summarize([d], rates, customerRates, getResult, { customerRegion })])),
    [days, rates, customerRates, getResult, customerRegion],
  )
  const visibleDays = useMemo(() => days.slice(0, shownDays), [days, shownDays])
  const hiddenDayCount = Math.max(0, days.length - shownDays)
  const open = (date: string) => isOpen(openState, date, days)

  async function load() {
    setLoading(true)
    setLoadError('')
    try {
      // mọi trang; không có sửa cục bộ chờ gửi (ở đây bản ghi được PATCH thẳng lên máy chủ)
      const list = await loadAllEntries({ overlay: false })
      setEntries(list.entries)
    } catch (err) {
      setLoadError((err as Error).message || 'Không tải được số liệu')
    } finally {
      setLoading(false)
    }
  }
  async function loadCustomers(): Promise<any[]> {
    try {
      const { customers: list } = await api.get('/me/customers')
      setCustomers(list)
      return list
    } catch {
      return [] // để trống - ô chọn sẽ không có khách
    }
  }
  async function loadRates() {
    try {
      const { rates: r } = await api.get('/me/scoring-settings')
      if (r && Object.keys(r).length) setRates(r)
    } catch {
      // giữ tỉ lệ mặc định nếu lỗi - không nghiêm trọng, vẫn tính được
    }
  }

  async function fetchLotteryFor(date: string, station = 'mb') {
    const key = lrKey(date, station)
    if (key in cache.current) return cache.current[key]
    try {
      const { result } = await api.get(`/lottery-results?date=${date}&station=${encodeURIComponent(station)}`)
      cache.current[key] = result
      syncCache()
      return result
    } catch {
      cache.current[key] = null
      syncCache()
      return null
    }
  }

  // Bản mới nhất của các giá trị mà tác vụ bất đồng bộ cần đọc.
  const latest = useRef<any>({})
  useEffect(() => {
    latest.current = { ctx, selectedCustomer, calcVersion, visibleDays, days, allDays, openState }
  })

  async function computeDay(d: any) {
    const L = latest.current
    const key = `${L.selectedCustomer}|${d.date}|${L.calcVersion}`
    if (calculated.current.has(key)) return
    calculated.current.add(key)
    setAutoCalcRunning((n) => n + 1)
    try {
      for (const entry of d.entries) {
        statuses.current[entry.id] = { state: 'computing', value: null }
        syncStatus()
        const { status, updated } = await computeOne(entry, latest.current.ctx, {
          fetchLottery: fetchLotteryFor,
          patch: (id: string, body: any) => api.patch(`/me/entries/${id}`, body),
        })
        if (updated) setEntries((list) => list.map((e) => (e.id === entry.id ? updated : e)))
        statuses.current[entry.id] = status as Status
        syncStatus()
      }
    } catch (err) {
      setAutoCalcError((err as Error).message || 'Có lỗi khi tính điểm ra')
    } finally {
      setAutoCalcRunning((n) => n - 1)
    }
  }

  // Tính mọi ngày đang mở và đang hiện (và ngày vừa được mở).
  const openK = openKey(visibleDays, days, openState, selectedCustomer, calcVersion)
  useEffect(() => {
    for (const d of latest.current.visibleDays) if (isOpen(latest.current.openState, d.date, latest.current.days)) computeDay(d)
    // eslint-disable-next-line react-hooks/exhaustive-deps -- chỉ chạy lại khi khóa đổi, như watch của Vue
  }, [openK])

  // Tra kết quả xổ số cho mọi ngày trong khoảng (huy hiệu trạng thái đúng cả ở thẻ thu gọn; tổng theo khoảng). Nhớ theo ngày+đài.
  const prefetchToken = useRef(0)
  const prefetchK = allDays.map((d: any) => d.date).join('|') + `#${calcVersion}`
  useEffect(() => {
    const token = ++prefetchToken.current
    const queue: [string, string][] = []
    for (const d of latest.current.allDays) {
      for (const st of new Set<string>(d.entries.flatMap((e: any) => entryStations(e)))) {
        if (!(lrKey(d.date, st) in cache.current)) queue.push([d.date, st])
      }
    }
    const worker = async () => {
      while (queue.length && token === prefetchToken.current) {
        const [date, st] = queue.shift()!
        await fetchLotteryFor(date, st)
      }
    }
    Promise.all([worker(), worker(), worker(), worker()])
  }, [prefetchK])

  function recalc() {
    calculated.current.clear()
    cache.current = {}
    setCacheView({})
    setCalcVersion((v) => v + 1)
  }

  function openDelete(date = '') {
    setDeleteDay(date)
    setDeleteOpen(true)
  }
  async function onDeleted(n: number) {
    setDeleteOpen(false)
    setNotice(`Đã xóa ${n} số liệu.`)
    calculated.current.clear()
    await load()
  }

  const started = useRef(false)
  useEffect(() => {
    if (started.current) return
    started.current = true
    ;(async () => {
      const [, , list] = await Promise.all([load(), loadRates(), loadCustomers(), loadStations()])
      const q = new URLSearchParams(window.location.search)
      const customer = q.get('customer')
      const date = q.get('date')
      const added = q.get('added')
      // Từ Nhập số (luồng tin nhắn): mở sẵn đúng khách và đúng ngày vừa nhập, rồi bỏ tham số khỏi địa chỉ.
      if (!customer) {
        // Không có liên kết: theo khách và ngày đã chọn ở Nhập số.
        const sync = readCalcSync()
        if (sync.customer && list.some((c: any) => c.name === sync.customer)) setSelectedCustomer(sync.customer)
        if (sync.date) setDay(sync.date)
      }
      if (customer && list.some((c: any) => c.name === customer)) {
        setSelectedCustomer(customer)
        if (date) {
          setDateFrom(date)
          setDateTo(date)
        }
        if (added) setNotice(addedNotice(customer, date, added))
      }
      if (customer || date || added) window.history.replaceState(null, '', '/scoring')
    })()
  }, [])

  const areaDeps = { isRegionCode, regionOf, stationName }
  return (
    <div className="page scoring-page">
      <h1 className="page-title">Tính điểm</h1>
      <p className="page-subtitle">
        Điểm ra được máy tự động tính và lưu, theo kết quả xổ số đã nhập ở trang{' '}
        <Link href="/results" className="tap-link">Nhập kết quả</Link>. Tỉ lệ ăn và giải đối chiếu của từng khách chỉnh ở trang{' '}
        <Link href="/customers" className="tap-link">Khách hàng</Link> (nút Cấu hình tính điểm ở từng khách).
      </p>

      <div className="toolbar card">
        <div className="toolbar-actions">
          <AppButton variant="secondary" size="sm" onClick={() => openDelete('')}>Xóa số liệu</AppButton>
          <AppButton variant="secondary" size="sm" onClick={() => setScheduleOpen(true)}>Đặt lịch xóa</AppButton>
        </div>
      </div>

      {autoCalcError && <div className="alert alert-error">{autoCalcError}</div>}
      {notice && <div className="alert alert-success" role="status">{notice}</div>}

      {loading ? (
        <div className="card">Đang tải...</div>
      ) : loadError ? (
        <div className="alert alert-error">{loadError}</div>
      ) : (
        <>
          <div className="filters card">
            <div className="field filter-customer">
              <label>Khách hàng</label>
              <div className="input-wrap">
                <AppSelect value={selectedCustomer} onChange={setSelectedCustomer}>
                  <option value="">-- Chọn khách hàng --</option>
                  {customers.map((c) => <option key={c.id} value={c.name}>{c.name}</option>)}
                </AppSelect>
              </div>
            </div>
            <div className="field filter-date">
              <label>Ngày</label>
              <AppDatePicker value={day} onChange={setDay} />
            </div>
            <AppButton variant="secondary" size="sm" disabled={autoCalcRunning > 0 || !selectedCustomer} onClick={recalc}>
              {autoCalcRunning > 0 ? 'Đang tính...' : '↻ Tính lại'}
            </AppButton>
            {day && <AppButton variant="ghost" size="sm" onClick={() => setDay('')}>Xem mọi ngày</AppButton>}
          </div>

          {selectedCustomer && days.length > 0 && (
            <ScoringSummary days={days} accountRates={rates} customerRates={customerRates} customerRegion={customerRegion} getResult={getResult} />
          )}

          {!selectedCustomer ? (
            <div className="card empty-state">
              <AppIcon name="users" className="empty-icon" />
              <p>Chọn khách hàng ở trên để xem điểm ra của họ.</p>
            </div>
          ) : days.length === 0 ? (
            <div className="card empty-state">
              {emptyMessage({ onlyMissing, rangeCount: rangeEntries.length, customerHasEntries: entries.some((e) => e.customerName === selectedCustomer) })}
            </div>
          ) : (
            <>
              <div className="day-list">
                {visibleDays.map((d: any) => {
                  const m = dayMoney[d.date]
                  const isDayOpen = open(d.date)
                  const lab = dayLabel(d.date)
                  const remainingCls = m.settled.lots && !masked ? (m.remaining > 0 ? 'pos' : m.remaining < 0 ? 'neg' : '') : ''
                  return (
                    <section key={d.date} className={`card day-card${isDayOpen ? ' open' : ''}`}>
                      <div className="day-head">
                        <button
                          type="button"
                          className="day-toggle"
                          aria-expanded={isDayOpen}
                          aria-controls={`day-${d.date}`}
                          onClick={() => setOpenState((s) => ({ ...s, [d.date]: !isDayOpen }))}
                        >
                          <div className="day-title">
                            <AppIcon name="chevron-down" className="day-chevron" />
                            <strong>{lab.date}</strong>
                            <span className="day-weekday">{lab.weekday}</span>
                            <span className="chip count-chip">{d.entries.length} dòng</span>
                          </div>
                          <div className="day-figures">
                            <div className="cell">
                              <span className="cell-label">Số lô</span>
                              <span className="cell-value"><MaskedValue text={formatNumber(m.sent.lots)} /></span>
                            </div>
                            <div className="cell">
                              <span className="cell-label">Tiền gửi</span>
                              <span className="cell-value"><MaskedValue text={money(m.sent.money)} /></span>
                            </div>
                            <div className="cell">
                              <span className="cell-label">Tiền trúng</span>
                              <span className="cell-value">{m.settled.lots ? <MaskedValue text={money(m.won.money)} /> : '-'}</span>
                            </div>
                            <div className="cell">
                              <span className="cell-label">Còn lại</span>
                              <span className={`cell-value ${remainingCls}`}>
                                {m.settled.lots ? <MaskedValue text={(m.remaining > 0 ? '+' : '') + money(m.remaining)} /> : '-'}
                              </span>
                            </div>
                          </div>
                        </button>
                        <div className="day-meta">
                          {d.lottery === 'yes' ? (
                            <span className="chip chip-ok">Đã có kết quả xổ số</span>
                          ) : d.lottery === 'partial' ? (
                            <>
                              <span className="chip chip-warn">Thiếu kết quả của một số đài</span>
                              <Link href={`/results?date=${d.date}`} className="tap-link meta-link">Nhập kết quả</Link>
                            </>
                          ) : d.lottery === 'no' ? (
                            <>
                              <span className="chip chip-warn">Chưa có kết quả xổ số</span>
                              <Link href={`/results?date=${d.date}`} className="tap-link meta-link">Nhập kết quả</Link>
                            </>
                          ) : (
                            <span className="chip">Đang kiểm tra...</span>
                          )}
                          <button type="button" className="btn btn-ghost btn-sm day-del" onClick={() => openDelete(d.date)}>Xóa ngày này</button>
                        </div>
                      </div>

                      {isDayOpen && (
                        <div id={`day-${d.date}`} className="result-list">
                          {d.entries.map((entry: any) => {
                            const st = statusView[entry.id]
                            return (
                              <div key={entry.id} className="result-row">
                                <div className="result-row-top">
                                  <span className="chip">{betTypeLabel(entry.betType || 'de')}</span>
                                  <span className="chip">{areaName(entry.station, areaDeps)}</span>
                                  {st?.state === 'saved' && !masked && (
                                    <span className={`chip${(st.value ?? 0) > 0 ? ' chip-accent' : ''}`}>
                                      {(st.value ?? 0) > 0 && <AppIcon name="check" />}
                                      {(st.value ?? 0) > 0 ? 'Trúng' : 'Không trúng'}
                                    </span>
                                  )}
                                </div>
                                <div className="result-cells">
                                  <div className="cell">
                                    <span className="cell-label">Số</span>
                                    <span className="cell-value cell-number"><MaskedValue text={entry.value} /></span>
                                  </div>
                                  <div className="cell">
                                    <span className="cell-label">Điểm vào</span>
                                    <span className="cell-value">
                                      <MaskedValue text={entry.score ? formatNumber(Number(entry.score) || entry.score) : '-'} />
                                    </span>
                                  </div>
                                  <div className="cell">
                                    <span className="cell-label">Điểm ra</span>
                                    {st?.state === 'computing' ? (
                                      <span className="cell-value cell-pending">Đang tính...</span>
                                    ) : st?.state === 'no-lottery' ? (
                                      <span className="cell-value cell-pending">Chưa có kết quả</span>
                                    ) : st?.state === 'error' ? (
                                      <span className="cell-value cell-error">{st.error}</span>
                                    ) : st?.state === 'saved' ? (
                                      <span className={`cell-value${!masked && (st.value ?? 0) > 0 ? ' cell-win' : ''}`}>
                                        <MaskedValue text={formatNumber(st.value ?? 0)} />
                                      </span>
                                    ) : (
                                      <span className="cell-value cell-pending">
                                        {entry.result ? <MaskedValue text={formatNumber(Number(entry.result) || 0)} /> : 'Chưa có kết quả'}
                                      </span>
                                    )}
                                  </div>
                                </div>
                              </div>
                            )
                          })}
                        </div>
                      )}
                    </section>
                  )
                })}
              </div>

              {hiddenDayCount > 0 && (
                <button type="button" className="btn btn-secondary more-btn" onClick={() => setShownDays((n) => n + PAGE_DAYS)}>
                  Xem thêm ngày cũ ({Math.min(PAGE_DAYS, hiddenDayCount)} / còn {hiddenDayCount} ngày)
                </button>
              )}
            </>
          )}
        </>
      )}

      <DeleteDataDialog
        open={deleteOpen}
        customerName={selectedCustomer}
        dateFrom={dateFrom}
        dateTo={dateTo}
        singleDay={deleteDay}
        onDeleted={onDeleted}
        onClose={() => setDeleteOpen(false)}
      />
      <ModalDialog
        open={scheduleOpen}
        title="Đặt lịch xóa"
        description="Hệ thống tự xóa số liệu theo lịch, một lần hoặc lặp lại. Dữ liệu đã xóa không thể khôi phục."
        wide
        onClose={() => setScheduleOpen(false)}
        footer={<AppButton variant="secondary" onClick={() => setScheduleOpen(false)}>Đóng</AppButton>}
      >
        <DeletionSchedules embedded customerName={selectedCustomer} />
      </ModalDialog>
    </div>
  )
}
