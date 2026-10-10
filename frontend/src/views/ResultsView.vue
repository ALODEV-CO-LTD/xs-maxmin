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
import { effectiveConfig } from '../scoringConfig'
import { entryDetail } from '../scoringSummary'
import { entryStations, loadStations, regionList, regionOf, stationName, stationsOn } from '../lotteryStations'
import { assignStations, parseColumns } from '../lotteryColumns'
import { readClipboardImage, usePasteImage } from '../pasteImage'
import { showConfirm } from '../confirm'
import AppDatePicker from '../components/AppDatePicker.vue'
import AppIcon from '../components/AppIcon.vue'
import AppSelect from '../components/AppSelect.vue'
import { nextTick, onMounted, computed, reactive, ref, watch } from 'vue'
import { api } from '../api'
import { loadAllEntries } from '../offline'
import { today } from '../dates'
import { useRoute } from 'vue-router'

const entries = ref([])
const loading = ref(true)
const loadError = ref('')
const customers = ref([])
const selectedCustomer = ref('')
const onlyMissing = ref(true)

const draft = reactive({}) // id -> string being typed, seeded from entry.result
const savingAll = ref(false)
const saveAllMsg = ref('')
const saveAllError = ref('')

function formatNumber(n) {
  return new Intl.NumberFormat('vi-VN').format(n)
}

async function load() {
  loading.value = true
  loadError.value = ''
  try {
    const list = await loadAllEntries({ overlay: false })
    entries.value = list.entries
    for (const e of list.entries) draft[e.id] = e.result || ''
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
})

const filtered = computed(() => {
  return entries.value.filter((e) => {
    if (onlyMissing.value && e.result) return false
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

// Entries whose typed/auto-filled "Điểm ra" differs from what is stored.
const dirtyEntries = computed(() => entries.value.filter((e) => (draft[e.id] ?? '').trim() !== (e.result || '')))

// One button saves every changed "Điểm ra", across all customers.
async function saveAllResults() {
  saveAllMsg.value = ''
  saveAllError.value = ''
  const list = [...dirtyEntries.value]
  if (!list.length) return
  savingAll.value = true
  let ok = 0
  let failed = 0
  for (const entry of list) {
    try {
      const updated = await api.patch(`/me/entries/${entry.id}`, { result: (draft[entry.id] || '').trim() })
      const idx = entries.value.findIndex((e) => e.id === entry.id)
      if (idx !== -1) entries.value[idx] = updated
      draft[entry.id] = updated.result || ''
      ok++
    } catch (_) {
      failed++
    }
  }
  savingAll.value = false
  if (ok) saveAllMsg.value = `Đã lưu điểm ra cho ${ok} số liệu.`
  if (failed) saveAllError.value = `${failed} số liệu không lưu được, thử lại.`
}

// ---- Auto-fill "Điểm ra" from a lottery result (display only, saved by the button above) ----
function toNumber(str) {
  if (!str) return 0
  const n = parseFloat(String(str).replace(/[^\d.-]/g, ''))
  return Number.isFinite(n) ? n : 0
}
// Points out of one entry over the results of the stations it counts for (sum); null when none of them has a result yet.
function computeScoreFromResults(entry, byStation) {
  // The customer's own config if they have one, else the account-wide one.
  const own = customers.value.find((c) => c.name === entry.customerName)?.scoringRates
  const config = effectiveConfig(rates.value, own, entry.betType)
  const lrs = entryStations(entry).map((st) => byStation[st]).filter(Boolean)
  if (!lrs.length) return null
  return lrs.reduce((sum, lr) => sum + entryDetail(entry, lr, config).out, 0)
}
function fillResultsForDate(date, byStation) {
  for (const e of entries.value) {
    if (e.entryDate !== date) continue
    const v = computeScoreFromResults(e, byStation)
    if (v !== null) draft[e.id] = String(v)
  }
}

// ---- Kết quả xổ số (Miền Bắc / Miền Trung / Miền Nam, theo đài) ------------------------------------------

// ?date=YYYY-MM-DD (link from the Tính điểm day cards) opens that day.
const queryDate = String(useRoute().query.date || '')
const lotteryDate = ref(/^\d{4}-\d{2}-\d{2}$/.test(queryDate) ? queryDate : today())
const lotteryLoading = ref(false)
const lotteryError = ref('')
const lotterySaving = ref(false)
const lotterySaveMsg = ref('')

// Region and station (đài) being entered. Miền Bắc has one draw a day; Miền Nam / Miền Trung 2-4 stations that rotate
// by weekday (lotteryStations.js). The prize grid follows the region's structure.
const region = ref('mb')
const station = ref('mb')
const structure = computed(() => regionOf(region.value).structure)
const stationChoices = computed(() => stationsOn(region.value, lotteryDate.value))
const singleTiers = ['dacBiet', 'giaiNhat'] // stored as one string, every other group is a list

function blankLotteryForm() {
  const f = {}
  for (const p of structure.value) f[p.tier] = singleTiers.includes(p.tier) ? '' : Array(p.count).fill('')
  return f
}
const lotteryForm = reactive(blankLotteryForm())
const hasSavedLottery = ref(false)
function resetLotteryForm(values) {
  for (const k of Object.keys(lotteryForm)) delete lotteryForm[k]
  const blank = blankLotteryForm()
  for (const p of structure.value) {
    const v = values?.[p.tier]
    lotteryForm[p.tier] = singleTiers.includes(p.tier) ? v || '' : Array.isArray(v) && v.length === p.count ? [...v] : blank[p.tier]
  }
}

// Phones / small tablets: the prize grid is collapsed behind a dropdown
// toggle. It opens by itself as soon as there is anything in it (OCR filled it,
// a saved result was loaded, or the user typed), or when the user taps it.
const gridOpen = ref(false)
const flatValues = () => structure.value.flatMap((p) => [].concat(lotteryForm[p.tier] ?? ''))
const filledCount = computed(() => flatValues().filter((v) => (v || '').trim()).length)
const TOTAL_BOXES = computed(() => structure.value.reduce((n, p) => n + p.count, 0))
watch(filledCount, (n) => {
  if (n > 0) gridOpen.value = true
})
const lotteryDeleting = ref(false)

function applyLotteryResult(r) {
  hasSavedLottery.value = !!r
  resetLotteryForm(r)
}

async function loadLottery() {
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
watch(station, () => {
  if (applying) return
  resetLotteryForm(null)
  loadLottery()
})
const stationLabelOf = computed(() => `${regionOf(region.value).name}${region.value === 'mb' ? '' : ` · ${stationName(station.value)}`}`)

onMounted(async () => {
  await loadStations()
  loadLottery()
})

async function saveLottery() {
  lotteryError.value = ''
  lotterySaveMsg.value = ''
  const allFilled = flatValues().every((v) => (v || '').trim())
  if (!allFilled) {
    lotteryError.value = `Vui lòng nhập đủ ${TOTAL_BOXES.value} số trước khi lưu.`
    return
  }
  lotterySaving.value = true
  try {
    const body = { drawDate: lotteryDate.value, station: station.value }
    for (const p of structure.value) {
      const v = lotteryForm[p.tier]
      body[p.tier] = Array.isArray(v) ? v.map((x) => x.trim()) : v.trim()
    }
    await api.post('/lottery-results', body)
    lotterySaveMsg.value = `Đã lưu kết quả xổ số ${stationLabelOf.value} ngày ${lotteryDate.value}.`
    hasSavedLottery.value = true
    // Entries of this day can span several stations: score them with every result saved that day.
    const { results } = await api.get(`/lottery-results?date=${lotteryDate.value}&all=1`)
    fillResultsForDate(lotteryDate.value, Object.fromEntries(results.map((r) => [r.station, r])))
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
    lotterySaveMsg.value = `Đã xoá kết quả xổ số ${stationLabelOf.value} ngày ${lotteryDate.value}.`
  } catch (err) {
    lotteryError.value = err.message || 'Không xoá được'
  } finally {
    lotteryDeleting.value = false
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
const mcCols = ref([]) // [{ station, source, values, issues, complete, headerText }]
const mcDate = ref('')
const mcFileInput = ref(null)
const mcSavingAll = ref(false)
const mcStationOptions = computed(() => Object.entries(regionOf(region.value).stations || {}).map(([id, name]) => ({ id, name })))

function onMcImageSelected(e) {
  const file = e.target.files?.[0]
  e.target.value = ''
  if (file) processMcImage(file)
}

async function processMcImage(file) {
  mcError.value = ''
  mcNote.value = ''
  mcCols.value = []
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
    mcDate.value = date
    mcCols.value = parsed.columns.map((c) => ({ ...c, region: seenRegion }))
    if (seenRegion !== region.value || date !== lotteryDate.value) {
      applying = true
      region.value = seenRegion
      lotteryDate.value = date
      await nextTick()
      applying = false
      mcNote.value = `Ảnh là kết quả ${regionOf(seenRegion).name} ngày ${date.split('-').reverse().join('/')}; đã chuyển sang miền và ngày này.`
    }
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

async function mcFill(col) {
  if (!col.station) return
  applying = true
  region.value = regionOf(col.station).id
  lotteryDate.value = mcDate.value
  station.value = col.station
  await nextTick()
  applying = false
  resetLotteryForm(col.values)
  hasSavedLottery.value = false
  gridOpen.value = true
  lotterySaveMsg.value = `Đã điền ${stationName(col.station)} vào form. Hãy kiểm tra rồi bấm "Lưu kết quả".`
}

const mcDuplicate = computed(() => {
  const ids = mcCols.value.map((c) => c.station).filter(Boolean)
  return ids.length !== new Set(ids).size
})
const mcSavable = computed(() => mcCols.value.length > 0 && !mcDuplicate.value && mcCols.value.every((c) => c.station && c.complete))

async function mcSaveAll() {
  if (!mcSavable.value) return
  mcSavingAll.value = true
  lotteryError.value = ''
  lotterySaveMsg.value = ''
  try {
    for (const col of mcCols.value) {
      await api.post('/lottery-results', { drawDate: mcDate.value, station: col.station, ...col.values })
    }
    const { results } = await api.get(`/lottery-results?date=${mcDate.value}&all=1`)
    fillResultsForDate(mcDate.value, Object.fromEntries(results.map((r) => [r.station, r])))
    lotterySaveMsg.value = `Đã lưu kết quả ${mcCols.value.length} đài ngày ${mcDate.value.split('-').reverse().join('/')}.`
    mcCols.value = []
    await loadLottery()
  } catch (err) {
    lotteryError.value = err.message || 'Không lưu được kết quả'
  } finally {
    mcSavingAll.value = false
  }
}

function clearLotteryForm() {
  resetLotteryForm(null)
  if (lrOcrPreviewUrl.value) URL.revokeObjectURL(lrOcrPreviewUrl.value)
  lrOcrPreviewUrl.value = ''
  lrOcrError.value = ''
}
</script>

<template>
  <div class="page">
    <h1 class="page-title">Nhập kết quả</h1>
    <p class="page-subtitle">
      Nhập kết quả xổ số (Miền Bắc, Miền Trung, Miền Nam; chọn miền và đài), bấm "Lưu kết quả" để điểm ra tự hiện theo số và điểm vào, rồi bấm "Lưu điểm ra" để lưu cho tất cả khách hàng. Có thể sửa tay từng ô trước khi lưu.
    </p>

    <div class="card lottery-card">
      <div class="lottery-head">
        <h3 style="margin: 0">Kết quả xổ số {{ stationLabelOf }}</h3>
        <AppDatePicker v-model="lotteryDate" class="lottery-date" />
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
      <div v-if="region !== 'mb'" class="station-chips" aria-label="Đài">
        <button
          v-for="st in stationChoices"
          :key="st"
          type="button"
          class="station-chip"
          :class="{ on: station === st }"
          :aria-pressed="station === st"
          @click="station = st"
        >
          {{ stationName(st) }}
        </button>
        <span v-if="!stationChoices.length" class="page-subtitle">Hôm nay không có đài nào của miền này.</span>
      </div>

      <div v-if="region === 'mb'" class="ocr-box">
        <input
          ref="lrFileInput"
          type="file"
          accept="image/*"
          capture="environment"
          style="display: none"
          @change="onLrImageSelected"
        />
        <button type="button" class="btn btn-secondary btn-block" :disabled="lrOcrRunning" @click="pickLrImage">
          <AppIcon v-if="!lrOcrRunning" name="camera" />
          {{ lrOcrRunning ? `Đang đọc ảnh... ${lrOcrProgress}%` : 'Đọc kết quả từ ảnh' }}
        </button>
        <button type="button" class="btn btn-ghost btn-sm paste-btn" :disabled="lrOcrRunning" @click="pasteFromButton">Dán ảnh từ bộ nhớ tạm</button>
        <p class="ocr-hint">Xử lý ngay trên trình duyệt. Chọn ảnh hoặc dán ảnh (Ctrl/Cmd+V). Đọc ảnh có thể sai (đặc biệt số có số 0 ở đầu). Luôn kiểm tra lại trước khi lưu.</p>
        <div v-if="lrOcrError" class="alert alert-error" style="margin-top: 8px">{{ lrOcrError }}</div>
        <img v-if="lrOcrPreviewUrl && !lrOcrRunning" :src="lrOcrPreviewUrl" alt="Ảnh đã chọn" class="ocr-thumb-lg" />
      </div>

      <!-- Miền Nam / Miền Trung: một ảnh bảng kết quả có nhiều đài (mỗi đài một cột) -->
      <div v-if="region !== 'mb'" class="ocr-box mc-box">
        <input ref="mcFileInput" type="file" accept="image/*" style="display: none" @change="onMcImageSelected" />
        <button type="button" class="btn btn-secondary btn-block" :disabled="mcRunning" @click="pickMcImage">
          <AppIcon v-if="!mcRunning" name="camera" />
          {{ mcRunning ? `Đang đọc ảnh... ${mcProgress}%` : 'Đọc kết quả từ ảnh (nhiều đài)' }}
        </button>
        <button type="button" class="btn btn-ghost btn-sm paste-btn" :disabled="mcRunning" @click="pasteFromButton">Dán ảnh từ bộ nhớ tạm</button>
        <p class="ocr-hint">
          Chọn hoặc dán ảnh (Ctrl/Cmd+V) bảng kết quả Miền Nam / Miền Trung (mỗi đài một cột). Xử lý ngay trên trình duyệt; kết quả chỉ là gợi ý để bạn kiểm tra, chưa lưu cho tới khi bạn bấm lưu.
        </p>
        <div v-if="mcError" class="alert alert-error" style="margin-top: 8px">{{ mcError }}</div>
        <div v-if="mcNote" class="alert alert-success" style="margin-top: 8px">{{ mcNote }}</div>

        <div v-if="mcCols.length" class="mc-cols">
          <div v-for="(col, ci) in mcCols" :key="ci" class="mc-col" :class="{ bad: !col.complete }">
            <div class="mc-col-head">
              <AppSelect v-model="col.station" :aria-label="`Đài của cột ${ci + 1}`">
                <option v-for="o in mcStationOptions" :key="o.id" :value="o.id">{{ o.name }}</option>
              </AppSelect>
              <span class="mc-source">{{ col.source ? `nhận theo ${col.source}` : '' }}</span>
            </div>
            <p v-if="col.complete" class="mc-ok">Đọc đủ 18 số</p>
            <p v-else class="mc-warn">Chưa đủ: {{ col.issues.join('; ') }}. Kiểm tra và sửa trong form.</p>
            <details class="mc-numbers">
              <summary>Xem các số đã đọc</summary>
              <dl>
                <template v-for="p in regionOf(col.region).structure" :key="p.tier">
                  <dt>{{ p.label }}</dt>
                  <dd>{{ [].concat(col.values[p.tier] ?? []).map((v) => v || '·').join('  ') }}</dd>
                </template>
              </dl>
            </details>
            <button type="button" class="btn btn-ghost btn-sm" :disabled="!col.station" @click="mcFill(col)">Điền vào form để sửa</button>
          </div>
          <p v-if="mcDuplicate" class="mc-warn">Hai cột đang trùng một đài, hãy chọn lại.</p>
          <button type="button" class="btn btn-primary btn-sm" :disabled="!mcSavable || mcSavingAll" @click="mcSaveAll">
            {{ mcSavingAll ? 'Đang lưu...' : `Lưu kết quả ${mcCols.length} đài này` }}
          </button>
        </div>
      </div>

      <div v-if="lotteryLoading" class="page-subtitle">Đang tải...</div>
      <template v-else>
        <div v-if="lotteryError" class="alert alert-error">{{ lotteryError }}</div>
        <div v-if="lotterySaveMsg" class="alert alert-success">{{ lotterySaveMsg }}</div>

        <button
          type="button"
          class="grid-toggle"
          :class="{ open: gridOpen }"
          :aria-expanded="gridOpen"
          aria-controls="lottery-grid"
          @click="gridOpen = !gridOpen"
        >
          <span class="grid-toggle-label">Nhập tay các giải</span>
          <span class="grid-toggle-count">{{ filledCount }}/{{ TOTAL_BOXES }}</span>
          <AppIcon name="chevron-down" class="grid-toggle-chevron" />
        </button>

        <div id="lottery-grid" class="lottery-grid" :class="{ collapsed: !gridOpen }">
          <div v-for="p in structure" :key="p.tier" class="tier-row">
            <label>{{ p.label }}</label>
            <input v-if="singleTiers.includes(p.tier)" v-model="lotteryForm[p.tier]" :maxlength="p.digits" :class="`num${p.digits}`" inputmode="numeric" />
            <div v-else class="tier-inputs">
              <input
                v-for="(v, k) in lotteryForm[p.tier]"
                :key="k"
                v-model="lotteryForm[p.tier][k]"
                :maxlength="p.digits"
                :class="`num${p.digits}`"
                inputmode="numeric"
              />
            </div>
          </div>
        </div>

        <div class="lottery-actions">
          <button
            v-if="hasSavedLottery"
            type="button"
            class="btn btn-danger btn-sm"
            :disabled="lotteryDeleting"
            @click="deleteLottery"
          >
            {{ lotteryDeleting ? 'Đang xoá...' : 'Xoá kết quả này' }}
          </button>
          <button type="button" class="btn btn-ghost btn-sm" @click="clearLotteryForm">Xoá form</button>
          <button type="button" class="btn btn-primary" :disabled="lotterySaving" @click="saveLottery">
            {{ lotterySaving ? 'Đang lưu...' : 'Lưu kết quả' }}
          </button>
        </div>
      </template>
    </div>

    <div v-if="loading" class="card">Đang tải...</div>
    <div v-else-if="loadError" class="alert alert-error">{{ loadError }}</div>
    <template v-else>
      <div class="filters card">
        <label class="check-field">
          <input type="checkbox" v-model="onlyMissing" />
          Chỉ hiện số liệu chưa có điểm ra
        </label>
        <div class="field filter-customer" style="margin: 0">
          <AppSelect v-model="selectedCustomer" aria-label="Khách hàng">
            <option value="">Tất cả khách hàng</option>
            <option v-for="c in customers" :key="c.id" :value="c.name">{{ c.name }}</option>
          </AppSelect>
        </div>
        <button
          type="button"
          class="btn btn-primary filters-save"
          :disabled="savingAll || dirtyEntries.length === 0"
          @click="saveAllResults"
        >
          {{ savingAll ? 'Đang lưu...' : `Lưu điểm ra${dirtyEntries.length ? ` (${dirtyEntries.length})` : ''}` }}
        </button>
      </div>

      <div v-if="saveAllMsg" class="alert alert-success">{{ saveAllMsg }}</div>
      <div v-if="saveAllError" class="alert alert-error">{{ saveAllError }}</div>

      <div v-if="groupedByCustomer.length === 0" class="card">
        {{ onlyMissing ? 'Không còn số liệu nào cần nhập kết quả.' : 'Không có số liệu phù hợp.' }}
      </div>

      <div v-else class="customer-groups">
        <div v-for="group in groupedByCustomer" :key="group.name" class="card customer-group">
          <div class="customer-group-head">
            <strong>{{ group.name }}</strong>
            <span class="page-subtitle">{{ group.entries.length }} số</span>
          </div>

          <div class="result-list">
            <div v-for="entry in group.entries" :key="entry.id" class="result-row">
              <div class="result-row-top">
                <span class="chip">{{ entry.entryDate }}</span>
              </div>
              <div class="result-value">{{ entry.value }}</div>
              <div class="result-meta">
                <span v-if="entry.score">Điểm vào: {{ formatNumber(Number(entry.score) || entry.score) }}</span>
              </div>
              <div class="result-input-row">
                <input
                  v-model="draft[entry.id]"
                  type="text"
                  inputmode="decimal"
                  placeholder="Điểm ra"
                />
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
.mc-box {
  margin-bottom: 12px;
}
.mc-cols {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
  gap: 10px;
  margin-top: 10px;
}
.mc-col {
  padding: 10px;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 10px;
}
.mc-col.bad {
  border-color: var(--danger-text);
}
.mc-col-head {
  display: flex;
  flex-direction: column;
  gap: 2px;
  margin-bottom: 6px;
}
.mc-source,
.mc-ok,
.mc-warn {
  margin: 0 0 6px;
  font-size: 12.5px;
  color: var(--muted);
}
.mc-ok {
  color: var(--success-text);
}
.mc-warn {
  color: var(--danger-text);
  grid-column: 1 / -1;
}
.mc-numbers {
  margin-bottom: 6px;
  font-size: 13px;
}
.mc-numbers dl {
  display: grid;
  grid-template-columns: auto 1fr;
  gap: 2px 10px;
  margin: 6px 0 0;
}
.mc-numbers dt {
  color: var(--muted);
}
.mc-numbers dd {
  margin: 0;
  font-variant-numeric: tabular-nums;
  overflow-wrap: anywhere;
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
.station-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  margin-bottom: 10px;
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
  background: transparent;
  border: 1px solid transparent;
  border-radius: 8px;
  transition: background 0.12s ease, border-color 0.12s ease;
}
.lottery-grid .tier-row input:hover {
  background: color-mix(in srgb, var(--primary) 8%, transparent);
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
</style>
