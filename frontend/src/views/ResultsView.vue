<!--
  Nhập kết quả: two things live on this page.

  1. "Kết quả xổ số Miền Bắc" - the official daily draw (27 numbers), a
     shared/public fact stored via GET/POST /lottery-results?date=... (see
     backend/routes/api/lottery-results/index.dart). Fill by hand or via
     OCR from a photo of the result table (client-side tesseract.js, same
     "suggest, never auto-save" approach as EntriesView's image import).
     Lives HERE (not on ScoringView/"Tính điểm") because entering the raw
     draw result is itself a form of "entering results" - ScoringView only
     ever *reads* whatever was saved here, it doesn't duplicate this form.

  2. The per-entry "Điểm ra" list - type it by hand for each entry. For
     the auto-calculated version (using the draw result above + the payout
     rate), see ScoringView.vue ("Tính điểm"), a separate tab so "just type
     the number" and "auto-calc" stay two distinct, uncluttered screens.

  API: GET/POST /lottery-results, GET /me/entries,
       PATCH /me/entries/:id with only `{ result }`.
-->
<script setup>
import AppButton from '../components/AppButton.vue'
import { effectiveConfig } from '../scoringConfig'
import { entryDetail } from '../scoringSummary'
import { loadAllEntries } from '../offline'
import { entryStations, loadStations, regionList, regionOf, stationName, stationsOn } from '../lotteryStations'
import { assignStations, parseColumns } from '../lotteryColumns'
import { readClipboardImage, usePasteImage } from '../pasteImage'
import { showConfirm } from '../confirm'
import AppDatePicker from '../components/AppDatePicker.vue'
import AppIcon from '../components/AppIcon.vue'
import AppSelect from '../components/AppSelect.vue'
import { nextTick, onMounted, computed, reactive, ref, watch } from 'vue'
import { api } from '../api'
import { today } from '../dates'
import { useRoute } from 'vue-router'

const entries = ref([])
const loading = ref(true)
const loadError = ref('')
const customers = ref([])
const selectedCustomer = ref('')

// "Điểm ra" is never typed: it is worked out from the saved result of the day and each customer's own config,
// and only for the entries written for the day being entered (see syncScores).
const syncMsg = ref('')
const syncError = ref('')

function formatNumber(n) {
  return new Intl.NumberFormat('vi-VN').format(n)
}

async function load() {
  loading.value = true
  loadError.value = ''
  try {
    const list = await loadAllEntries({ overlay: false })
    entries.value = list.entries
  } catch (err) {
    loadError.value = err.message || 'Không tải được số liệu'
  } finally {
    loading.value = false
  }
}

async function loadCustomers() {
  try {
    const { customers: list } = await api.get('/me/customers')
    customers.value = list
  } catch (_) {
    // Leave empty - the dropdown just shows no customers.
  }
}

// Same payout config the "Tính điểm" page uses (fallback = backend default).
const rates = ref({
  de: { rate: 70, tiers: ['dacBiet'], digits: 2 },
  lo: {
    rate: 20,
    tiers: ['dacBiet', 'giaiNhat', 'giaiNhi', 'giaiBa', 'giaiTu', 'giaiNam', 'giaiSau', 'giaiBay'],
    digits: 2,
  },
})
async function loadRates() {
  try {
    const { rates: r } = await api.get('/me/scoring-settings')
    if (r && Object.keys(r).length) rates.value = r
  } catch (_) {
    // keep fallback
  }
}

onMounted(async () => {
  await Promise.all([load(), loadCustomers(), loadRates()])
  if (!selectedCustomer.value && customers.value.length) selectedCustomer.value = customers.value[0].name
  await loadDayResults()
})

// Only the entries of the day whose result is being entered.
const filtered = computed(() => {
  return entries.value.filter((e) => {
    if (e.entryDate !== lotteryDate.value) return false
    if (selectedCustomer.value && (e.customerName || '(Không tên)') !== selectedCustomer.value) return false
    return true
  })
})

// Group so a customer's name is shown once, not repeated on every one of
// their rows - same treatment as ScoringView's "Tính điểm" list.
const groupedByCustomer = computed(() => {
  const byName = new Map()
  for (const e of filtered.value) {
    const name = e.customerName || '(Không tên)'
    if (!byName.has(name)) byName.set(name, [])
    byName.get(name).push(e)
  }
  return [...byName.entries()]
    .map(([name, list]) => ({ name, entries: list }))
    .sort((a, b) => a.name.localeCompare(b.name, 'vi'))
})

// ---- Điểm ra, calculated ----------------------------------------------------------------------------------
function toNumber(str) {
  if (!str) return 0
  const n = parseFloat(String(str).replace(/[^\d.-]/g, ''))
  return Number.isFinite(n) ? n : 0
}
// Points out of one entry over the results of the stations it counts for (sum); null when none of them has a result yet.
function computeScoreFromResults(entry, byStation) {
  // The customer's own config if they have one, else the account-wide one.
  const cust = customers.value.find((c) => c.name === entry.customerName)
  const own = cust?.scoringRates
  const done = entryStations(entry).filter((st) => byStation[st])
  if (!done.length) return null
  // Rates are per region: each station is scored with the config of its own region.
  return done.reduce((sum, st) => sum + entryDetail(entry, byStation[st], effectiveConfig(rates.value, own, entry.betType, regionOf(st).id), { region: regionOf(st).id, customerRegion: cust?.homeRegion || null }).out, 0)
}

const dayResults = ref({}) // station id -> saved result of the selected day
async function loadDayResults() {
  try {
    const { results } = await api.get(`/lottery-results?date=${lotteryDate.value}&all=1`)
    dayResults.value = Object.fromEntries(results.map((r) => [r.station, r]))
  } catch (_) {
    dayResults.value = {}
  }
}
// Calculated "Điểm ra" of an entry (null = the day has no result for its station yet).
const scoreOf = (e) => computeScoreFromResults(e, dayResults.value)

// Stores the calculated value on every entry of the day (called after a result is saved).
// Safety: when this would OVERWRITE an "Điểm ra" that is already there with a different number, ask first
// (a misread result would otherwise silently change the money of every customer that day), and keep the old
// values so "Hoàn tác" can put them back.
const undoSync = ref(null) // { date, items: [{ id, prev }] } of the last automatic update
async function syncScores() {
  syncMsg.value = ''
  syncError.value = ''
  const changes = []
  for (const e of entries.value) {
    if (e.entryDate !== lotteryDate.value) continue
    const v = scoreOf(e)
    if (v === null || String(v) === (e.result || '')) continue
    changes.push({ e, value: String(v), prev: e.result || '' })
  }
  if (!changes.length) return
  const overwrites = changes.filter((c) => c.prev !== '' && toNumber(c.prev) !== toNumber(c.value))
  if (overwrites.length) {
    const ok = await showConfirm({
      title: 'Cập nhật Điểm ra',
      message:
        `Kết quả vừa lưu sẽ cập nhật Điểm ra của ${changes.length} số liệu ngày ${lotteryDate.value.split('-').reverse().join('/')}, ` +
        `trong đó ${overwrites.length} số liệu đã có Điểm ra khác sẽ bị ghi đè. Bạn có thể bấm "Hoàn tác" ngay sau đó. Tiếp tục?`,
      confirmText: 'Cập nhật',
    })
    if (!ok) {
      syncMsg.value = 'Đã lưu kết quả xổ số, chưa cập nhật Điểm ra (bạn chọn không ghi đè).'
      return
    }
  }
  const done = []
  let failed = 0
  for (const c of changes) {
    try {
      const updated = await api.patch(`/me/entries/${c.e.id}`, { result: c.value })
      const idx = entries.value.findIndex((x) => x.id === c.e.id)
      if (idx !== -1) entries.value[idx] = updated
      done.push({ id: c.e.id, prev: c.prev })
    } catch (_) {
      failed++
    }
  }
  undoSync.value = done.length ? { date: lotteryDate.value, items: done } : null
  if (done.length) syncMsg.value = `Đã tính và lưu điểm ra cho ${done.length} số liệu.`
  if (failed) syncError.value = `${failed} số liệu chưa lưu được điểm ra, lưu lại kết quả để thử lại.`
}

// Puts back the "Điểm ra" values that the last automatic update replaced.
const undoing = ref(false)
async function undoScores() {
  const u = undoSync.value
  if (!u || undoing.value) return
  undoing.value = true
  syncError.value = ''
  let back = 0
  let failed = 0
  for (const it of u.items) {
    try {
      const updated = await api.patch(`/me/entries/${it.id}`, { result: it.prev })
      const idx = entries.value.findIndex((x) => x.id === it.id)
      if (idx !== -1) entries.value[idx] = updated
      back++
    } catch (_) {
      failed++
    }
  }
  undoSync.value = null
  syncMsg.value = `Đã hoàn tác Điểm ra của ${back} số liệu.`
  if (failed) syncError.value = `${failed} số liệu chưa hoàn tác được.`
  undoing.value = false
}

// ---- Kết quả xổ số (Miền Bắc / Miền Trung / Miền Nam, theo đài) ------------------------------------------

// ?date=YYYY-MM-DD (link from the Tính điểm day cards) opens that day.
const queryDate = String(useRoute().query.date || '')
const lotteryDate = ref(/^\d{4}-\d{2}-\d{2}$/.test(queryDate) ? queryDate : today())
watch(lotteryDate, loadDayResults)

// ‹ › step the day by one, so yesterday's saved result is one tap away.
function shiftDay(delta) {
  const [y, m, d] = lotteryDate.value.split('-').map(Number)
  const next = new Date(Date.UTC(y, m - 1, d + delta))
  lotteryDate.value = next.toISOString().slice(0, 10)
}
const lotteryLoading = ref(false)
const lotteryError = ref('')
const lotterySaving = ref(false)
const lotterySaveMsg = ref('')

// Region and station (đài) being entered. Miền Bắc has one draw a day; Miền Nam / Miền Trung 2-4 stations that rotate
// by weekday (lotteryStations.js). The prize grid follows the region's structure.
const region = ref('mb')
const station = ref('mb')
const structure = computed(() => regionOf(region.value).structure)
// Đài của miền: các đài QUAY trong ngày theo lịch + các đài khác bạn thêm tay (lịch có thể đổi, hoặc nhập kết quả ngày cũ của đài khác).
// Đài đã có kết quả lưu trong ngày nhưng không nằm trong lịch cũng tự hiện.
const scheduledStations = computed(() => stationsOn(region.value, lotteryDate.value))
const extraStations = ref([])
const stationChoices = computed(() => [...scheduledStations.value, ...extraStations.value.filter((id) => !scheduledStations.value.includes(id))])
// Mọi đài còn lại của miền (đủ cả danh mục), để chọn thêm.
const otherStations = computed(() =>
  Object.keys(regionOf(region.value).stations || {})
    .filter((id) => !stationChoices.value.includes(id))
    .map((id) => ({ value: id, label: stationName(id) })),
)
const addStationPick = ref('')
function addStation(id) {
  if (!id) return
  if (!extraStations.value.includes(id)) extraStations.value.push(id)
  board[id] = shapeForm(null)
  boardSaved[id] = false
  activeCol.value = id
  addStationPick.value = ''
}
const singleTiers = ['dacBiet', 'giaiNhat'] // stored as one string, every other group is a list

function blankLotteryForm() {
  const f = {}
  for (const p of structure.value) f[p.tier] = singleTiers.includes(p.tier) ? '' : Array(p.count).fill('')
  return f
}
const lotteryForm = reactive(blankLotteryForm())
const hasSavedLottery = ref(false)
// A saved result is only displayed; "Sửa" unlocks the boxes.
// The form is also locked after a photo has been read (it only shows what was read); "Sửa" unlocks it.
const lotteryLocked = ref(false)
const lotteryReadOnly = computed(() => lotteryLocked.value)
// A form object for the region's structure, filled from `values` where they fit.
function shapeForm(values) {
  const out = {}
  const blank = blankLotteryForm()
  for (const p of structure.value) {
    const v = values?.[p.tier]
    // a group may hold more numbers than the region's usual count (extra boxes): keep them all
    out[p.tier] = singleTiers.includes(p.tier) ? v || '' : Array.isArray(v) && v.length >= p.count ? [...v] : blank[p.tier]
  }
  return out
}
function resetLotteryForm(values) {
  for (const k of Object.keys(lotteryForm)) delete lotteryForm[k]
  Object.assign(lotteryForm, shapeForm(values))
}

// Phones / small tablets: the prize grid is collapsed behind a dropdown
// toggle. It opens by itself as soon as there is anything in it (OCR filled it,
// a saved result was loaded, or the user typed), or when the user taps it.
const gridOpen = ref(false)
// The region's usual count of every group must be filled; boxes added beyond it are optional (empty ones are dropped on save).
const requiredFilled = (form) =>
  structure.value.every((p) => {
    const v = form?.[p.tier]
    return Array.isArray(v) ? v.slice(0, p.count).every((x) => (x || '').trim()) && v.length >= p.count : !!(v || '').trim()
  })
const valuesOf = (p, v) => (Array.isArray(v) ? v.map((x) => (x || '').trim()).filter((x, i) => i < p.count || x) : (v || '').trim())
function addCell(p) {
  const v = colData(curCol.value)?.[p.tier]
  if (Array.isArray(v)) v.push('')
}
function removeCell(p) {
  const v = colData(curCol.value)?.[p.tier]
  if (Array.isArray(v) && v.length > p.count) v.pop()
}
const flatValues = () => structure.value.flatMap((p) => [].concat(lotteryForm[p.tier] ?? ''))
const filledCount = computed(() => flatValues().filter((v) => (v || '').trim()).length)
const TOTAL_BOXES = computed(() => structure.value.reduce((n, p) => n + p.count, 0))
watch(filledCount, (n) => {
  if (n > 0) gridOpen.value = true
})
const lotteryDeleting = ref(false)

function applyLotteryResult(r) {
  hasSavedLottery.value = !!r
  lotteryLocked.value = !!r
  resetLotteryForm(r)
}

async function loadLottery() {
  if (region.value !== 'mb') return loadBoard()
  lotteryError.value = ''
  lotterySaveMsg.value = ''
  lotteryLoading.value = true
  try {
    const { result } = await api.get(`/lottery-results?date=${lotteryDate.value}&station=${encodeURIComponent(station.value)}`)
    applyLotteryResult(result)
  } catch (err) {
    lotteryError.value = err.message || 'Không tải được kết quả xổ số'
  } finally {
    lotteryLoading.value = false
  }
}

// Keep the station valid for the region/date, reshape the grid and load what is saved for it.
let applying = false // true while a recognised column is being written into the form (the watchers must not reload over it)
watch([region, lotteryDate], () => {
  if (applying) return
  const choices = stationChoices.value
  if (!choices.includes(station.value)) station.value = choices[0] || region.value
  resetLotteryForm(null)
  loadLottery()
})
// Notices belong to the region they were produced in: switching Miền Bắc / Trung / Nam starts with a clean slate
// (a photo that switches the region by itself keeps its own note, see processMcImage).
watch(region, () => {
  if (applying) return
  for (const m of [lotteryError, lotterySaveMsg, lrOcrError, mcError, mcNote, syncMsg, syncError]) m.value = ''
  mcWarnings.value = []
})
watch(station, () => {
  if (applying) return
  resetLotteryForm(null)
  loadLottery()
})
const stationLabelOf = computed(() => regionOf(region.value).name)

onMounted(async () => {
  await loadStations()
  loadLottery()
})

async function saveLottery() {
  if (region.value !== 'mb') return saveBoard()
  lotteryError.value = ''
  lotterySaveMsg.value = ''
  if (!requiredFilled(lotteryForm)) {
    lotteryError.value = `Vui lòng nhập đủ ${TOTAL_BOXES.value} số trước khi lưu.`
    return
  }
  lotterySaving.value = true
  try {
    const body = { drawDate: lotteryDate.value, station: station.value }
    for (const p of structure.value) {
      body[p.tier] = valuesOf(p, lotteryForm[p.tier])
    }
    await api.post('/lottery-results', body)
    lotterySaveMsg.value = `Đã lưu kết quả xổ số ${stationLabelOf.value} ngày ${lotteryDate.value}.`
    hasSavedLottery.value = true
    lotteryLocked.value = true
    // Entries of this day can span several stations: score them with every result saved that day.
    await loadDayResults()
    await syncScores()
  } catch (err) {
    lotteryError.value = err.message || 'Không lưu được kết quả xổ số'
  } finally {
    lotterySaving.value = false
  }
}

async function deleteLottery() {
  if (!(await showConfirm({
    title: 'Xoá kết quả',
    message: `Xoá kết quả xổ số ${stationLabelOf.value} ngày ${lotteryDate.value}? Không thể hoàn tác.`,
    confirmText: 'Xoá',
    danger: true,
  }))) return
  lotteryError.value = ''
  lotterySaveMsg.value = ''
  lotteryDeleting.value = true
  try {
    await api.del(`/lottery-results?date=${lotteryDate.value}&station=${encodeURIComponent(station.value)}`)
    applyLotteryResult(null)
    await loadDayResults()
    lotterySaveMsg.value = `Đã xoá kết quả xổ số ${stationLabelOf.value} ngày ${lotteryDate.value}.`
  } catch (err) {
    lotteryError.value = err.message || 'Không xoá được'
  } finally {
    lotteryDeleting.value = false
  }
}

// ---- Miền Nam / Miền Trung: one table for every station drawing that day (like the printed sheet) ----------------
// Columns = the day's stations, rows = prizes from G.8 (top) to G.ĐB (bottom). Typing, pasting a photo and saving all work
// on this one table; a column is saved only when it is completely filled.
const board = reactive({}) // station id -> form
const boardSaved = reactive({}) // station id -> true while a saved result exists
const boardRead = reactive({}) // station id -> true when filled from a photo (empty cells are flagged)
const boardStations = computed(() => (region.value === 'mb' ? [] : stationChoices.value))
const boardTiers = computed(() => [...structure.value].reverse())
const flatOf = (form) => structure.value.flatMap((p) => [].concat(form?.[p.tier] ?? ''))
const boardFilled = (st) => flatOf(board[st]).filter((v) => (v || '').trim()).length
const cellBad = (st, p, v) => {
  const t = (v || '').trim()
  return t ? t.length !== p.digits : !!boardRead[st]
}
const boardDeleting = ref('')
const boardEdit = reactive({}) // station id -> true while a saved column is unlocked
const boardLocked = (st) => !!(boardSaved[st] || boardRead[st]) && !boardEdit[st]

// Cả ba miền dùng MỘT bảng giống nhau: Miền Bắc là bảng một cột ('mb'), Miền Trung / Miền Nam mỗi đài một cột. Miền Bắc giữ
// dữ liệu trong lotteryForm, các đài trong board[st]; các hàm dưới đây ẩn sự khác nhau đó khỏi bảng.
const MB_COL = 'mb'
const ocrRunning = computed(() => (region.value === 'mb' ? lrOcrRunning.value : mcRunning.value))
const ocrProgress = computed(() => (region.value === 'mb' ? lrOcrProgress.value : mcProgress.value))
const tableCols = computed(() => (region.value === 'mb' ? [MB_COL] : boardStations.value))
const colName = (st) => (st === MB_COL ? 'Miền Bắc' : stationName(st))
const colData = (st) => (st === MB_COL ? lotteryForm : board[st])
const colLocked = (st) => (st === MB_COL ? lotteryReadOnly.value : boardLocked(st))
const colSaved = (st) => (st === MB_COL ? hasSavedLottery.value : !!boardSaved[st])
const colBad = (st, p, v) => {
  if (st !== MB_COL) return cellBad(st, p, v)
  const t = (v || '').trim()
  return t ? t.length !== p.digits : false
}
const colDeleting = (st) => (st === MB_COL ? lotteryDeleting.value : boardDeleting.value === st)
function colEdit(st) {
  if (st === MB_COL) lotteryLocked.value = false
  else boardEdit[st] = true
}
function colDelete(st) {
  return st === MB_COL ? deleteLottery() : deleteBoardColumn(st)
}
// Cả ba miền cùng MỘT cấu trúc (danh sách giải dọc như Miền Bắc, Đặc biệt trên cùng): Miền Bắc là một form; Miền Trung / Miền Nam
// chọn đài ở dãy nút phía trên rồi nhập đúng form đó cho đài đang chọn.
const activeCol = ref('')
const curCol = computed(() => (tableCols.value.includes(activeCol.value) ? activeCol.value : tableCols.value[0] || ''))
const curFilled = computed(() => (curCol.value === MB_COL ? filledCount.value : curCol.value ? boardFilled(curCol.value) : 0))

// Only digits can be typed or pasted into a prize box, and never more than the prize has.
function digitsOnly(form) {
  for (const p of structure.value) {
    const clean = (v) => String(v ?? '').replace(/\D/g, '').slice(0, p.digits)
    const v = form[p.tier]
    if (Array.isArray(v)) v.forEach((x, k) => x !== clean(x) && (v[k] = clean(x)))
    else if (v !== undefined && v !== clean(v)) form[p.tier] = clean(v)
  }
}
watch(lotteryForm, () => digitsOnly(lotteryForm), { deep: true })
watch(board, () => Object.values(board).forEach(digitsOnly), { deep: true })

async function loadBoard() {
  lotteryError.value = ''
  lotterySaveMsg.value = ''
  lotteryLoading.value = true
  try {
    const { results } = await api.get(`/lottery-results?date=${lotteryDate.value}&all=1`)
    const by = Object.fromEntries(results.map((r) => [r.station, r]))
    // stations of this region that have a saved result today but are not on the schedule (added by hand earlier)
    extraStations.value = results.map((r) => r.station).filter((id) => id !== 'mb' && regionOf(id).id === region.value && !scheduledStations.value.includes(id))
    for (const o of [board, boardSaved, boardRead, boardEdit]) for (const k of Object.keys(o)) delete o[k]
    for (const st of boardStations.value) {
      board[st] = shapeForm(by[st])
      boardSaved[st] = !!by[st]
    }
  } catch (err) {
    lotteryError.value = err.message || 'Không tải được kết quả xổ số'
  } finally {
    lotteryLoading.value = false
  }
}

async function saveBoard() {
  lotteryError.value = ''
  lotterySaveMsg.value = ''
  const todo = boardStations.value.filter((st) => boardFilled(st) > 0)
  if (!todo.length) {
    lotteryError.value = 'Chưa có số nào để lưu.'
    return
  }
  const total = TOTAL_BOXES.value
  const partial = todo.filter((st) => !requiredFilled(board[st]))
  if (partial.length) {
    lotteryError.value = `${partial.map(stationName).join(', ')}: chưa nhập đủ ${total} số. Điền đủ hoặc xoá hết cột đó rồi lưu lại.`
    return
  }
  lotterySaving.value = true
  try {
    for (const st of todo) {
      const body = { drawDate: lotteryDate.value, station: st }
      for (const p of structure.value) {
        body[p.tier] = valuesOf(p, board[st][p.tier])
      }
      await api.post('/lottery-results', body)
      boardSaved[st] = true
      boardRead[st] = false
      boardEdit[st] = false
    }
    lotterySaveMsg.value = `Đã lưu kết quả ${todo.map(stationName).join(', ')} ngày ${lotteryDate.value.split('-').reverse().join('/')}.`
    await loadDayResults()
    await syncScores()
  } catch (err) {
    lotteryError.value = err.message || 'Không lưu được kết quả xổ số'
  } finally {
    lotterySaving.value = false
  }
}

async function deleteBoardColumn(st) {
  if (!(await showConfirm({
    title: 'Xoá kết quả',
    message: `Xoá kết quả xổ số ${stationName(st)} ngày ${lotteryDate.value}? Không thể hoàn tác.`,
    confirmText: 'Xoá',
    danger: true,
  }))) return
  lotteryError.value = ''
  lotterySaveMsg.value = ''
  boardDeleting.value = st
  try {
    await api.del(`/lottery-results?date=${lotteryDate.value}&station=${encodeURIComponent(st)}`)
    board[st] = shapeForm(null)
    boardSaved[st] = false
    boardRead[st] = false
    await loadDayResults()
    lotterySaveMsg.value = `Đã xoá kết quả xổ số ${stationName(st)} ngày ${lotteryDate.value}.`
  } catch (err) {
    lotteryError.value = err.message || 'Không xoá được'
  } finally {
    boardDeleting.value = ''
  }
}

// OCR for the 27-number result table - same "suggest, never auto-save"
// approach as EntriesView's image import, extended to bucket recognized
// digit-groups by length into the right prize tier (best-effort: OCR can
// drop leading zeros or misread a table cell, so this only ever fills
// fields the form doesn't already have a value for - always review before
// saving).
const lrOcrRunning = ref(false)
const lrOcrProgress = ref(0)
const lrOcrError = ref('')
const lrOcrPreviewUrl = ref('')
const lrFileInput = ref(null)

function pickLrImage() {
  lrFileInput.value?.click()
}

function onLrImageSelected(e) {
  const file = e.target.files?.[0]
  e.target.value = ''
  if (file) processLrImage(file)
}

async function processLrImage(file) {
  lrOcrError.value = ''
  if (lrOcrPreviewUrl.value) URL.revokeObjectURL(lrOcrPreviewUrl.value)
  lrOcrPreviewUrl.value = URL.createObjectURL(file)

  lrOcrRunning.value = true
  lrOcrProgress.value = 0
  try {
    const { recognizeLotteryTable } = await import('../ocr')
    const { text } = await recognizeLotteryTable(file, { onProgress: (p) => (lrOcrProgress.value = p) })
    applyLrOcrGuess(text)
  } catch (err) {
    const { describeOcrError } = await import('../ocr')
    lrOcrError.value = describeOcrError(err)
  } finally {
    lrOcrRunning.value = false
  }
}

function applyLrOcrGuess(text) {
  lotteryLocked.value = true
  // Chỉ nhận những "từ" (tách bởi khoảng trắng) mà TOÀN BỘ là chữ số -
  // bỏ hẳn nhãn cột kiểu "13GH", "2GH" (thường gặp khi chụp từ trang web
  // khác) thay vì cố tách phần số ra khỏi chúng: \d+ với lookaround từng
  // bị quantifier backtrack khớp nhầm (vd. khớp "1" từ "13GH" vì "3" phía
  // sau cũng là chữ số, không phải chữ cái, nên qua được lookahead).
  // Không chặn được hết nhiễu (ví dụ năm "2026" trong ngày quay vẫn là
  // một "từ" số thuần 4 chữ số), nhưng chặn đúng trường hợp đã gặp.
  const tokens = (text.match(/\S+/g) || []).filter((w) => /^\d+$/.test(w))
  const byLen = { 5: [], 4: [], 3: [], 2: [] }
  for (const t of tokens) {
    if (byLen[t.length]) byLen[t.length].push(t)
  }

  // 5-digit tokens, in reading order: đặc biệt, nhất, nhì(2), ba(6)
  const five = byLen[5]
  let i = 0
  if (!lotteryForm.dacBiet.trim() && five[i]) lotteryForm.dacBiet = five[i++]
  if (!lotteryForm.giaiNhat.trim() && five[i]) lotteryForm.giaiNhat = five[i++]
  for (let k = 0; k < 2; k++) if (!lotteryForm.giaiNhi[k]?.trim() && five[i]) lotteryForm.giaiNhi[k] = five[i++]
  for (let k = 0; k < 6; k++) if (!lotteryForm.giaiBa[k]?.trim() && five[i]) lotteryForm.giaiBa[k] = five[i++]

  // 4-digit tokens: tư(4), năm(6)
  const four = byLen[4]
  let j = 0
  for (let k = 0; k < 4; k++) if (!lotteryForm.giaiTu[k]?.trim() && four[j]) lotteryForm.giaiTu[k] = four[j++]
  for (let k = 0; k < 6; k++) if (!lotteryForm.giaiNam[k]?.trim() && four[j]) lotteryForm.giaiNam[k] = four[j++]

  // 3-digit: sáu(3)
  const three = byLen[3]
  for (let k = 0; k < 3; k++) if (!lotteryForm.giaiSau[k]?.trim() && three[k]) lotteryForm.giaiSau[k] = three[k]

  // 2-digit: bảy(4)
  const two = byLen[2]
  for (let k = 0; k < 4; k++) if (!lotteryForm.giaiBay[k]?.trim() && two[k]) lotteryForm.giaiBay[k] = two[k]
}

// ---- Đọc ảnh bảng kết quả Miền Nam / Miền Trung (nhiều đài, mỗi đài một cột) ----------------------------
// The photo is read in the browser, the columns are rebuilt from the word positions (lotteryColumns.js) and every
// column is only a SUGGESTION: it is shown for review and nothing is saved until the user presses a save button.
const mcRunning = ref(false)
const mcProgress = ref(0)
const mcError = ref('')
const mcNote = ref('')
const mcWarnings = ref([]) // columns that were not read completely: shown so the red cells are explained
const mcFileInput = ref(null)

function onMcImageSelected(e) {
  const file = e.target.files?.[0]
  e.target.value = ''
  if (file) processMcImage(file)
}

async function processMcImage(file) {
  mcError.value = ''
  mcNote.value = ''
  mcWarnings.value = []
  mcRunning.value = true
  mcProgress.value = 0
  try {
    await loadStations()
    const { recognizeLotteryWords } = await import('../ocr')
    const { words } = await recognizeLotteryWords(file, { onProgress: (p) => (mcProgress.value = p) })
    const parsed = parseColumns(words)
    if (!parsed.columns.length) {
      mcError.value = 'Không nhận ra bảng kết quả (cần thấy giải đặc biệt 6 số của từng đài). Hãy chụp rõ cả bảng hoặc nhập tay.'
      return
    }
    // Which region and day the photo is of: from its title ("XSMT ... 09/10/2026"), else what is selected now.
    const text = words.map((w) => String(w.text)).join(' ').toLowerCase()
    const seenRegion = /xsmt/.test(text) ? 'mt' : /xsmn/.test(text) ? 'mn' : region.value
    const date = parsed.date || lotteryDate.value
    const candidates = stationsOn(seenRegion, date)
    assignStations(parsed.columns, candidates)
    if (seenRegion !== region.value || date !== lotteryDate.value) {
      applying = true
      region.value = seenRegion
      lotteryDate.value = date
      await nextTick()
      applying = false
      mcNote.value = `Ảnh là kết quả ${regionOf(seenRegion).name} ngày ${date.split('-').reverse().join('/')}; đã chuyển sang miền và ngày này.`
    }
    await loadBoard()
    // Every recognised column goes straight into the table under its station.
    for (const c of parsed.columns) {
      if (!c.station || !board[c.station]) {
        mcWarnings.value.push('Có một cột chưa xác định được đài, nên chưa điền vào bảng.')
        continue
      }
      board[c.station] = shapeForm(c.values)
      boardRead[c.station] = true
      boardEdit[c.station] = false
      if (!c.complete) mcWarnings.value.push(`${stationName(c.station)}: ${c.issues.join('; ')}`)
    }
    lotterySaveMsg.value = 'Đã điền bảng từ ảnh. Kiểm tra các ô (ô đỏ là chưa đủ hoặc sai độ dài) rồi bấm "Lưu kết quả".'
  } catch (err) {
    const { describeOcrError } = await import('../ocr')
    mcError.value = describeOcrError(err)
  } finally {
    mcRunning.value = false
  }
}

// Paste (Ctrl/Cmd+V) or the "Dán ảnh" buttons: the picture goes to the reader of the region on screen.
usePasteImage(
  (file) => (region.value === 'mb' ? processLrImage(file) : processMcImage(file)),
  () => !lrOcrRunning.value && !mcRunning.value,
)
async function pasteFromButton() {
  const err = region.value === 'mb' ? lrOcrError : mcError
  err.value = ''
  try {
    const file = await readClipboardImage()
    if (region.value === 'mb') processLrImage(file)
    else processMcImage(file)
  } catch (e) {
    err.value = e.message
  }
}

function pickMcImage() {
  mcFileInput.value?.click()
}

function clearLotteryForm() {
  if (region.value !== 'mb') {
    for (const st of boardStations.value) {
      board[st] = shapeForm(null)
      boardRead[st] = false
      boardEdit[st] = true
    }
    mcWarnings.value = []
    return
  }
  resetLotteryForm(null)
  lotteryLocked.value = false
  if (lrOcrPreviewUrl.value) URL.revokeObjectURL(lrOcrPreviewUrl.value)
  lrOcrPreviewUrl.value = ''
  lrOcrError.value = ''
}
</script>

<template>
  <div class="page">
    <h1 class="page-title">Nhập kết quả</h1>
    <p class="page-subtitle">
      Nhập kết quả xổ số (Miền Bắc, Miền Trung, Miền Nam) rồi bấm "Lưu kết quả" để điểm ra tự hiện theo số và điểm vào, rồi bấm "Lưu điểm ra" để lưu cho tất cả khách hàng. Kết quả xổ số đã lưu chỉ hiển thị; bấm "Sửa" để chỉnh.
    </p>

    <div class="card lottery-card">
      <div class="lottery-head">
        <h3 style="margin: 0">Kết quả xổ số {{ stationLabelOf }}</h3>
        <div class="date-nav">
          <AppButton variant="ghost" size="sm" aria-label="Ngày trước" title="Ngày trước" @click="shiftDay(-1)">‹</AppButton>
          <AppDatePicker v-model="lotteryDate" class="lottery-date" />
          <AppButton variant="ghost" size="sm" aria-label="Ngày sau" title="Ngày sau" @click="shiftDay(1)">›</AppButton>
        </div>
      </div>

      <div class="region-tabs" role="tablist" aria-label="Miền">
        <button
          v-for="r in regionList()"
          :key="r.id"
          type="button"
          role="tab"
          class="region-tab"
          :class="{ on: region === r.id }"
          :aria-selected="region === r.id"
          @click="region = r.id"
        >
          {{ r.name }}
        </button>
      </div>
      <!-- Đọc từ ảnh: cùng một khung cho cả ba miền (Miền Bắc một cột, Miền Trung / Miền Nam mỗi đài một cột) -->
      <div class="ocr-box mc-box">
        <input v-if="region === 'mb'" ref="lrFileInput" type="file" accept="image/*" capture="environment" style="display: none" @change="onLrImageSelected" />
        <input v-else ref="mcFileInput" type="file" accept="image/*" style="display: none" @change="onMcImageSelected" />
        <AppButton variant="secondary" block :disabled="ocrRunning" @click="region === 'mb' ? pickLrImage() : pickMcImage()">
<AppIcon v-if="!ocrRunning" name="camera" />
          {{ ocrRunning ? `Đang đọc ảnh... ${ocrProgress}%` : 'Đọc kết quả từ ảnh' }}
</AppButton>
        <button type="button" class="btn btn-ghost btn-sm paste-btn" :disabled="ocrRunning" @click="pasteFromButton">Dán ảnh từ bộ nhớ tạm</button>
        <p class="ocr-hint">
          Chọn hoặc dán ảnh (Ctrl/Cmd+V) bảng kết quả{{ region === 'mb' ? '' : ' (mỗi đài một cột)' }}. Xử lý ngay trên trình duyệt; kết quả chỉ là gợi ý để bạn kiểm tra (đặc biệt số có số 0 ở đầu), chưa lưu cho tới khi bạn bấm lưu.
        </p>
        <div v-if="region === 'mb' ? lrOcrError : mcError" class="alert alert-error" style="margin-top: 8px">{{ region === 'mb' ? lrOcrError : mcError }}</div>
        <div v-if="region !== 'mb' && mcNote" class="alert alert-success" style="margin-top: 8px">{{ mcNote }}</div>
        <img v-if="region === 'mb' && lrOcrPreviewUrl && !lrOcrRunning" :src="lrOcrPreviewUrl" alt="Ảnh đã chọn" class="ocr-thumb-lg" />
        <ul v-if="region !== 'mb' && mcWarnings.length" class="mc-warnings">
          <li v-for="(w, i) in mcWarnings" :key="i">{{ w }}</li>
        </ul>
      </div>

      <div v-if="lotteryLoading" class="page-subtitle">Đang tải...</div>
      <template v-else>
        <div v-if="lotteryError" class="alert alert-error">{{ lotteryError }}</div>
        <div v-if="lotterySaveMsg" class="alert alert-success">{{ lotterySaveMsg }}</div>

        <p v-if="!tableCols.length" class="page-subtitle">Ngày này không có đài nào của miền này.</p>
        <template v-else>
          <div v-if="region !== 'mb'" class="region-tabs station-tabs" role="tablist" aria-label="Đài">
            <button
              v-for="st in tableCols"
              :key="st"
              type="button"
              role="tab"
              class="station-chip"
              :class="{ on: curCol === st }"
              :aria-selected="curCol === st"
              @click="activeCol = st"
            >
              {{ colName(st) }}<span v-if="colSaved(st)" class="chip-saved" title="Đã lưu"> ✓</span>
            </button>
            <AppSelect v-if="otherStations.length" v-model="addStationPick" class="station-add" aria-label="Thêm đài khác" @update:model-value="addStation">
              <option value="">+ Đài khác ({{ otherStations.length }})</option>
              <option v-for="o in otherStations" :key="o.value" :value="o.value">{{ o.label }}</option>
            </AppSelect>
          </div>

          <button
            type="button"
            class="grid-toggle"
            :class="{ open: gridOpen }"
            :aria-expanded="gridOpen"
            aria-controls="lottery-grid"
            @click="gridOpen = !gridOpen"
          >
            <span class="grid-toggle-label">Nhập tay các giải{{ region !== 'mb' ? ` · ${colName(curCol)}` : '' }}</span>
            <span class="grid-toggle-count">{{ curFilled }}/{{ TOTAL_BOXES }}</span>
            <AppIcon name="chevron-down" class="grid-toggle-chevron" />
          </button>

          <div v-if="colData(curCol)" id="lottery-grid" class="lottery-grid" :class="{ collapsed: !gridOpen, readonly: colLocked(curCol) }">
            <div v-for="p in structure" :key="p.tier" class="tier-row">
              <label>{{ p.label }}<span class="tier-count">{{ p.count }} ô · {{ p.digits }} số</span></label>
              <input
                v-if="singleTiers.includes(p.tier)"
                v-model="colData(curCol)[p.tier]"
                :readonly="colLocked(curCol)"
                :maxlength="p.digits"
                :placeholder="'0'.repeat(p.digits)"
                :class="[`num${p.digits}`, { bad: colBad(curCol, p, colData(curCol)[p.tier]) }]"
                inputmode="numeric"
                autocomplete="off"
                :aria-label="`${p.label} ${colName(curCol)}`"
              />
              <div v-else class="tier-inputs">
                <input
                  v-for="(v, k) in colData(curCol)[p.tier]"
                  :key="k"
                  v-model="colData(curCol)[p.tier][k]"
                  :readonly="colLocked(curCol)"
                  :maxlength="p.digits"
                  :placeholder="'0'.repeat(p.digits)"
                  :class="[`num${p.digits}`, { bad: colBad(curCol, p, v) }]"
                  inputmode="numeric"
                  autocomplete="off"
                  :aria-label="`${p.label} ${colName(curCol)} số ${k + 1}`"
                />
                <span v-if="!colLocked(curCol)" class="cell-tools">
                  <button type="button" class="cell-btn" :aria-label="`Thêm ô ${p.label}`" title="Thêm một ô nếu kết quả có nhiều số hơn" @click="addCell(p)">+</button>
                  <button v-if="colData(curCol)[p.tier].length > p.count" type="button" class="cell-btn" :aria-label="`Bớt ô ${p.label}`" title="Bớt ô vừa thêm" @click="removeCell(p)">−</button>
                </span>
              </div>
            </div>
          </div>

          <div class="lottery-actions">
            <AppButton variant="danger" size="sm" v-if="colSaved(curCol)"  :disabled="colDeleting(curCol)" @click="colDelete(curCol)">
{{ colDeleting(curCol) ? 'Đang xoá...' : 'Xoá kết quả này' }}
</AppButton>
            <AppButton variant="secondary" size="sm" :disabled="!colLocked(curCol)" @click="colEdit(curCol)">Sửa</AppButton>
            <AppButton variant="ghost" size="sm" @click="clearLotteryForm">Xoá form</AppButton>
            <AppButton variant="primary" :disabled="lotterySaving || !tableCols.length" @click="saveLottery">{{ lotterySaving ? 'Đang lưu...' : 'Lưu kết quả' }}</AppButton>
          </div>
        </template>
      </template>
    </div>

    <div v-if="loading" class="card">Đang tải...</div>
    <div v-else-if="loadError" class="alert alert-error">{{ loadError }}</div>
    <template v-else>
      <div class="filters card">
        <strong class="filters-title">Điểm ra ngày {{ lotteryDate.split('-').reverse().join('/') }}</strong>
        <div class="field filter-customer" style="margin: 0">
          <AppSelect v-model="selectedCustomer" aria-label="Khách hàng">
            <option value="">Tất cả khách hàng</option>
            <option v-for="c in customers" :key="c.id" :value="c.name">{{ c.name }}</option>
          </AppSelect>
        </div>
        <span class="page-subtitle filters-note">Tự tính theo kết quả đã lưu và công thức của từng khách.</span>
      </div>

      <div v-if="syncMsg" class="alert alert-success sync-msg">
        <span>{{ syncMsg }}</span>
        <AppButton variant="secondary" size="sm" v-if="undoSync"  :disabled="undoing" @click="undoScores">{{ undoing ? 'Đang hoàn tác...' : 'Hoàn tác' }}</AppButton>
      </div>
      <div v-if="syncError" class="alert alert-error">{{ syncError }}</div>

      <div v-if="groupedByCustomer.length === 0" class="card">Không có số liệu nào của ngày này.</div>

      <div v-else class="customer-groups">
        <div v-for="group in groupedByCustomer" :key="group.name" class="card customer-group">
          <div class="customer-group-head">
            <strong>{{ group.name }}</strong>
            <span class="page-subtitle">{{ group.entries.length }} số</span>
          </div>

          <div class="result-list">
            <div v-for="entry in group.entries" :key="entry.id" class="result-row">
              <div class="result-value">{{ entry.value }}</div>
              <div class="result-meta">
                <span v-if="entry.score">Điểm vào: {{ formatNumber(Number(entry.score) || entry.score) }}</span>
              </div>
              <div class="result-out">
                <template v-if="scoreOf(entry) !== null">
                  Điểm ra: <strong>{{ formatNumber(scoreOf(entry)) }}</strong>
                </template>
                <span v-else class="muted-out">Chưa có kết quả xổ số</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>

<style scoped>
.lottery-card {
  margin-bottom: 16px;
}
.filters-title {
  margin-right: 8px;
}
.filters-note {
  margin: 0;
}
.result-out {
  order: 4;
  flex: 1 1 160px;
  font-size: 15px;
}
.muted-out {
  color: var(--muted);
}
.date-nav {
  display: inline-flex;
  align-items: center;
  gap: 4px;
}
.date-nav .btn {
  min-width: 36px;
  font-size: 20px;
  line-height: 1;
}
.lottery-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 12px;
  flex-wrap: wrap;
}
.lottery-date {
  padding: 8px 10px;
  border: 1.5px solid var(--border);
  border-radius: var(--radius-md);
  background: var(--bg);
  color: var(--text);
  font-size: 14px;
}
.paste-btn {
  margin-top: 6px;
}
.mc-warnings {
  margin: 8px 0 0;
  padding-left: 18px;
  font-size: 13px;
  color: var(--danger-text);
}
.cell-tools { display: inline-flex; gap: 4px; align-self: center; }
.cell-btn { width: 30px; height: 30px; font-size: 18px; line-height: 1; color: var(--primary); background: var(--card); border: 1px dashed var(--primary); border-radius: 8px; cursor: pointer; }
.station-add {
  min-width: 170px;
  max-width: 220px;
}
.chip-saved {
  color: #16a34a;
  font-weight: 700;
}
.station-chip.on .chip-saved {
  color: #fff;
}
.lottery-grid input.bad {
  border-color: var(--danger);
}
.board-wrap {
  overflow-x: auto;
}
.board {
  width: 100%;
  max-width: min(960px, calc(120px + var(--cols) * 330px)); /* một cột (Miền Bắc) không bị kéo rộng */
  min-width: calc(88px + var(--cols) * 150px);
  border-collapse: collapse;
  table-layout: fixed;
}
.board th,
.board td {
  padding: 8px 6px;
  text-align: center;
  vertical-align: middle;
  border: 1px solid var(--border);
}
.board thead th {
  font-size: 14px;
  color: var(--text-primary);
  background: var(--surface);
}
.board thead th.saved {
  color: var(--success-text);
}
.board-saved {
  display: block;
  font-size: 11.5px;
  font-weight: 600;
}
.board th.board-tier .tier-count {
  display: block;
  margin-top: 2px;
  font-size: 11px;
  font-weight: 400;
  color: var(--text-secondary);
}
.board th.board-tier {
  width: 88px;
  font-size: 13px;
  color: var(--muted);
  background: var(--surface);
}
.board tbody tr:nth-child(even) td {
  background: var(--surface-2, var(--surface));
}
.board-cell {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
}
.board-cell input {
  width: 100%;
  max-width: 120px;
  height: 34px;
  padding: 0 6px;
  font: inherit;
  font-size: 16px;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
  text-align: center;
  color: var(--text-primary);
  background: var(--card);
  border: 1px solid var(--input-border);
  border-radius: 8px;
}
.board-cell input.big {
  height: 40px;
  font-size: 18px;
  color: var(--danger-text);
}
.board-top .board-cell input:not(.big) {
  color: var(--danger-text);
}
.board-cell input.bad {
  border-color: var(--danger-text);
  background: var(--danger-bg, var(--card));
}
.board-cell input:focus {
  outline: 2px solid var(--primary);
  outline-offset: 0;
}
.mc-box {
  margin-bottom: 12px;
}
.region-tabs {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  margin: 10px 0 8px;
}
.region-tab,
.station-chip {
  min-height: 34px;
  padding: 0 14px;
  font: inherit;
  font-size: 14px;
  color: var(--muted);
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 999px;
  cursor: pointer;
}
.region-tab.on,
.station-chip.on {
  color: #fff;
  background: var(--primary);
  border-color: var(--primary);
}
.num6 {
  width: 76px;
}
.ocr-box {
  margin-bottom: 14px;
  padding-bottom: 14px;
  border-bottom: 1px dashed var(--border);
}
.ocr-hint {
  font-size: 14px;
  color: var(--muted);
  margin: 6px 0 0;
}
.ocr-thumb-lg {
  margin-top: 10px;
  max-width: 100%;
  max-height: 220px;
  border-radius: var(--radius-md);
  border: 1px solid var(--border);
  display: block;
}
.lottery-grid {
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.tier-row {
  display: flex;
  align-items: center;
  gap: 10px;
  flex-wrap: wrap;
}
.tier-row > label {
  width: 84px;
  flex-shrink: 0;
  font-size: 14px;
  font-weight: 700;
  color: var(--muted);
}
.tier-inputs {
  display: flex;
  gap: 6px;
  flex-wrap: wrap;
}
.tier-row input {
  border: 1.5px solid var(--border);
  border-radius: var(--radius-sm);
  background: var(--bg);
  color: var(--text);
  text-align: center;
  font-weight: 700;
  padding: 8px 4px;
}
.tier-row input:focus {
  outline: none;
  border-color: var(--accent);
}
.num5 {
  width: 54px;
}
.num4 {
  width: 46px;
}
.num3 {
  width: 40px;
}
.num2 {
  width: 36px;
}
.lottery-actions {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
  margin-top: 14px;
}
.filters {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  flex-wrap: wrap;
  margin-bottom: 16px;
}
.check-field {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 14px;
  color: var(--text);
  white-space: nowrap;
}
.customer-groups {
  display: flex;
  flex-direction: column;
  gap: 12px;
}
.customer-group-head {
  display: flex;
  align-items: baseline;
  gap: 8px;
  margin-bottom: 10px;
  padding-bottom: 8px;
  border-bottom: 1px solid var(--border);
}
.result-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.result-row {
  padding: 10px 0;
  border-bottom: 1px dashed var(--border);
}
.result-row:last-child {
  border-bottom: none;
  padding-bottom: 0;
}
.result-row-top {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-wrap: wrap;
  margin-bottom: 6px;
}
.result-value {
  font-size: 17px;
  font-weight: 700;
  color: var(--accent-strong);
  margin-bottom: 4px;
}
.result-meta {
  font-size: 14px;
  color: var(--muted);
  margin-bottom: 10px;
}
.result-input-row {
  display: flex;
  gap: 8px;
}
.result-input-row input {
  flex: 1;
  min-width: 0;
  padding: 10px 12px;
  border: 1.5px solid var(--border);
  border-radius: var(--radius-md);
  background: var(--bg);
  color: var(--text);
  font-size: 14px;
}
.result-input-row input:focus {
  outline: none;
  border-color: var(--accent);
}
@media (max-width: 480px) {
  .tier-row > label {
    width: 100%;
  }
}
/* ---- Layout refinements: centred, bounded entry area ---- */
.lottery-card {
  padding: 20px 24px;
}
/* one shared, readable column inside the (very wide) card */
.lottery-head,
.ocr-box,
.lottery-grid,
.lottery-actions,
.lottery-card > .alert,
.lottery-card > .page-subtitle {
  max-width: 760px;
  margin-left: auto;
  margin-right: auto;
}
.lottery-head {
  margin-bottom: 16px;
}
.lottery-head h3 {
  font-size: 18px;
}
.lottery-date {
  height: 40px;
  padding: 0 12px;
  font-size: 14px;
  border: 1px solid var(--input-border);
  border-radius: 10px;
  background: var(--surface);
}
.lottery-date:focus {
  outline: none;
  border-color: var(--primary);
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--primary) 35%, transparent);
}

/* "Đọc kết quả từ ảnh": upload / action area */
.ocr-box {
  margin-bottom: 16px;
  padding-bottom: 16px;
}
.ocr-box > .btn {
  min-height: 64px;
  flex-direction: column;
  gap: 4px;
  border: 1.5px dashed var(--input-border);
  border-radius: 10px;
  background: var(--surface);
  color: var(--text-primary);
}
.ocr-box > .btn :deep(.app-icon) {
  width: 24px;
  height: 24px;
  color: var(--text-secondary);
}
.ocr-box > .btn:hover:not(:disabled) {
  background: var(--primary-soft);
  border-color: var(--primary);
}
.ocr-box > .btn:hover:not(:disabled) :deep(.app-icon) {
  color: var(--primary);
}
.ocr-hint {
  font-size: 14px;
  line-height: 1.5;
  color: var(--text-secondary);
  margin: 8px 0 0;
}

/* Prize grid: label column + inputs, rows separated by a hairline */
.lottery-grid {
  gap: 0;
}
.tier-row {
  display: grid;
  grid-template-columns: 96px minmax(0, 1fr);
  align-items: center;
  gap: 12px;
  padding: 10px 0;
}
.tier-row + .tier-row {
  border-top: 1px solid var(--border);
}
.tier-row > label {
  width: auto;
  font-size: 14px;
  color: var(--text-secondary);
}
.tier-inputs {
  gap: 8px;
}
.tier-row input {
  height: 44px;
  padding: 0 4px;
  font-size: 18px;
  letter-spacing: 0.06em;
  font-variant-numeric: tabular-nums;
  border: 1px solid var(--input-border);
  border-radius: 10px;
  background: var(--surface);
  color: var(--text-primary);
  transition: border-color 0.15s ease, box-shadow 0.15s ease;
}
.tier-row input:hover {
  border-color: var(--input-border-hover);
}
.tier-row input:focus {
  outline: none;
  border-color: var(--primary);
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--primary) 35%, transparent);
}
.num5 {
  width: 76px;
}
.num4 {
  width: 66px;
}
.num3 {
  width: 58px;
}
.num2 {
  width: 50px;
}

/* Actions sit right under the grid, inside the same column */
.lottery-actions {
  align-items: center;
  gap: 8px;
  margin-top: 8px;
  padding-top: 16px;
  border-top: 1px solid var(--border);
}
.lottery-actions .btn {
  min-height: 40px;
  padding: 0 18px;
  font-size: 14px;
  border-radius: 10px;
}
.lottery-actions .btn-danger {
  margin-right: auto;
}
.lottery-actions .btn-ghost {
  color: var(--text-primary);
  border: 1px solid var(--input-border);
}
.lottery-actions .btn-ghost:hover {
  background: var(--surface);
}

/* Toolbar: checkbox and search close together */
.filters {
  justify-content: flex-start;
  gap: 16px 24px;
  padding: 12px 16px;
}
.check-field {
  gap: 10px;
  font-size: 14px;
  cursor: pointer;
}
.check-field input {
  width: 18px;
  height: 18px;
  accent-color: var(--primary);
}
.filters .field {
  flex: 0 1 340px;
}
.filters .filter-customer {
  --ctl-h: 40px;
}
.filters-save {
  margin-left: auto;
  min-height: 40px;
  padding: 0 18px;
  border-radius: 10px;
}
.filters .field input {
  height: 40px;
  padding: 0 14px;
  font-size: 14px;
  border-radius: 10px;
  border: 1px solid var(--input-border);
}

/* Empty / loading placeholder under the toolbar (presentation only) */
.page > .card:not(.lottery-card):not(.filters) {
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 120px;
  padding: 32px 24px;
  background: var(--surface);
  border: 1px dashed var(--input-border);
  color: var(--text-secondary);
  font-size: 15px;
  text-align: center;
}

@media (max-width: 640px) {
  .lottery-card {
    padding: 16px;
  }
  .tier-row {
    grid-template-columns: 1fr;
    gap: 6px;
  }
  .lottery-actions {
    flex-wrap: wrap;
  }
  .filters .field {
    flex: 1 1 100%;
  }
  .filters-save {
    flex: 1 1 100%;
    margin-left: 0;
  }
}

/* The date field is an AppDatePicker: the wrapper only sizes it, the trigger
   inside draws the control (so no frame on the wrapper). */
.lottery-date,
.lottery-date:focus {
  width: 180px;
  height: 40px;
  padding: 0;
  border: 0;
  background: transparent;
  box-shadow: none;
}
@media (max-width: 480px) {
  .lottery-date {
    width: 100%;
  }
}
/* ---- Compact one-page workspace (wide desktop): entry form left, customers right ---- */
@media (min-width: 1200px) {
  .page {
    max-width: none;
    padding: 10px 24px 12px;
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    grid-template-rows: repeat(4, auto) minmax(0, 1fr);
    gap: 0 20px;
    align-items: start;
  }
  .page > .page-title,
  .page > .page-subtitle {
    grid-column: 1 / -1;
  }
  .page-title {
    font-size: 22px;
    margin-bottom: 2px;
  }
  .page > .page-subtitle {
    margin-bottom: 8px;
    font-size: 14px;
  }
  .page > .lottery-card {
    grid-column: 1;
    grid-row: 3 / -1;
    margin: 0;
  }
  .page > :not(.page-title):not(.page-subtitle):not(.lottery-card) {
    grid-column: 2;
  }
  /* Miền Nam / Miền Trung: the table of stations needs the full width, the customers go below it */
  .page.board-mode > .lottery-card {
    grid-column: 1 / -1;
    grid-row: auto;
  }
  .page.board-mode > :not(.page-title):not(.page-subtitle):not(.lottery-card) {
    grid-column: 1 / -1;
  }

  /* the form column no longer needs its own centred 760px column */
  .lottery-head,
  .ocr-box,
  .lottery-grid,
  .lottery-actions,
  .lottery-card > .alert,
  .lottery-card > .page-subtitle {
    max-width: none;
  }
  .lottery-card {
    padding: 12px 16px 14px;
    border-radius: 14px;
  }
  .lottery-head {
    margin-bottom: 8px;
  }
  .lottery-head h3 {
    font-size: 16px;
  }
  .lottery-date {
    height: 36px;
  }
  .ocr-box {
    margin-bottom: 6px;
    padding-bottom: 8px;
  }
  .ocr-box > .btn {
    min-height: 44px;
    flex-direction: row;
    gap: 8px;
  }
  .ocr-hint {
    margin-top: 4px;
    font-size: 14px;
  }
  /* labels stay left-aligned; only the numbers are centred in the space beside them */
  .tier-row {
    grid-template-columns: 84px minmax(0, 1fr);
    gap: 8px;
    padding: 5px 0;
  }
  .tier-row > label {
    font-size: 14px;
  }
  .tier-inputs {
    gap: 6px;
    justify-content: center;
  }
  .tier-row > input {
    justify-self: center;
  }
  .tier-row input {
    height: 38px;
    font-size: 16px;
  }
  .num5 {
    width: 62px;
  }
  .num4 {
    width: 56px;
  }
  .num3 {
    width: 50px;
  }
  .num2 {
    width: 44px;
  }
  .lottery-actions {
    margin-top: 4px;
    padding-top: 10px;
  }

  /* right column: toolbar + customer groups (scrolls inside) */
  .filters {
    margin-bottom: 8px;
    padding: 8px 14px;
  }
  .customer-groups {
    max-height: calc(100vh - 200px);
    overflow-y: auto;
    padding-right: 4px;
  }
  .page > .card:not(.lottery-card):not(.filters) {
    min-height: 0;
    padding: 20px;
  }

  /* each customer entry on one row: date | number | stake | result input + save */
  .result-list {
    gap: 0;
  }
  .result-row,
  .result-row:last-child {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 6px 16px;
    padding: 8px 0;
    border-bottom: 1px dashed var(--border);
  }
  .result-row:last-child {
    border-bottom: 0;
  }
  .result-row-top {
    order: 1;
    margin: 0;
  }
  .result-value {
    order: 2;
    min-width: 56px;
    margin: 0;
    font-size: 18px;
  }
  .result-meta {
    order: 3;
    min-width: 110px;
    margin: 0;
    font-size: 14px;
  }
  .result-input-row {
    order: 4;
    flex: 1 1 220px;
    min-width: 0;
  }
  .result-row > .alert {
    order: 5;
    flex: 1 1 100%;
    margin: 0;
  }
  .customer-group {
    padding: 12px 16px;
  }
  .customer-group-head {
    margin-bottom: 4px;
    padding-bottom: 6px;
  }
}

/* ---- Prize grid as a dropdown (phones / small tablets only) ---- */
.grid-toggle {
  display: none;
}
@media (max-width: 900px) {
  .grid-toggle {
    display: flex;
    align-items: center;
    gap: 8px;
    width: 100%;
    min-height: 44px;
    margin: 0 0 8px;
    padding: 0 14px;
    font-family: var(--font-body);
    font-size: 15px;
    font-weight: 600;
    text-align: left;
    color: var(--text-primary);
    background: var(--surface);
    border: 1px solid var(--input-border);
    border-radius: 10px;
    cursor: pointer;
    transition: border-color 0.15s ease, box-shadow 0.15s ease;
  }
  .grid-toggle:hover {
    border-color: var(--input-border-hover);
  }
  .grid-toggle:focus-visible,
  .grid-toggle.open {
    outline: none;
    border-color: var(--primary);
    box-shadow: 0 0 0 3px color-mix(in srgb, var(--primary) 35%, transparent);
  }
  .grid-toggle-label {
    flex: 1;
  }
  .grid-toggle-count {
    padding: 1px 8px;
    font-size: 12px;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    color: var(--text-secondary);
    background: var(--card);
    border: 1px solid var(--border);
    border-radius: 999px;
  }
  .grid-toggle-chevron {
    flex: none;
    width: 18px;
    height: 18px;
    color: var(--text-secondary);
    transition: transform 0.15s ease;
  }
  .grid-toggle.open .grid-toggle-chevron {
    transform: rotate(180deg);
  }
  .lottery-grid.collapsed {
    display: none;
  }
}
/* ---- Prize table look: bare bold numbers spread across striped rows,
   Đặc biệt and Giải bảy in red. Still real inputs (hover/focus shows a box). ---- */
.lottery-grid .tier-row {
  padding: 4px 12px;
  border-top: 0;
}
.lottery-grid .tier-row:nth-child(odd) {
  background: var(--surface);
}
.lottery-grid .tier-inputs {
  display: grid;
  grid-auto-flow: column;
  grid-auto-columns: minmax(0, 1fr);
  gap: 4px;
  justify-content: stretch;
  width: 100%;
}
.lottery-grid .tier-row > input {
  justify-self: stretch;
}
.lottery-grid .tier-row input {
  width: 100%;
  min-width: 0;
  height: 38px;
  padding: 0 2px;
  font-family: var(--font-display);
  font-size: 20px;
  font-weight: 800;
  letter-spacing: 0.01em;
  font-variant-numeric: tabular-nums;
  color: var(--text-primary);
  text-align: center;
  background: var(--card);
  border: 1px solid var(--input-border);
  border-radius: 8px;
  transition: background 0.12s ease, border-color 0.12s ease;
}
.lottery-grid .tier-row input::placeholder,
.board-cell input::placeholder {
  font-weight: 500;
  color: var(--muted);
  opacity: 0.45;
}
.lottery-grid .tier-row > input {
  max-width: 180px;
  justify-self: center;
}
.lottery-grid .tier-row input:hover {
  border-color: var(--primary);
}
.lottery-grid.readonly .tier-row input,
.board-cell input[readonly] {
  cursor: default;
  background: transparent;
  border-color: transparent;
}
.lottery-grid.readonly .tier-row input:hover,
.lottery-grid.readonly .tier-row input:focus {
  border-color: transparent;
  box-shadow: none;
}
.tier-count {
  display: block;
  font-size: 11.5px;
  font-weight: 500;
  color: var(--muted);
}
.lottery-grid .tier-row input:focus {
  outline: none;
  background: var(--card);
  border-color: var(--primary);
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--primary) 30%, transparent);
}
.lottery-grid .tier-row:first-child input,
.lottery-grid .tier-row:last-child input {
  color: var(--danger-text);
}
@media (max-width: 640px) {
  .lottery-grid .tier-row {
    padding: 4px 8px;
  }
  .lottery-grid .tier-inputs {
    gap: 0;
  }
  .lottery-grid .tier-row input {
    font-size: 14px;
    height: 36px;
    padding: 0;
  }
}
.sync-msg {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}
</style>
