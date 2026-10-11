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
import { loadStations, regionList, regionOf, stationName, stationsOn } from '../lotteryStations'
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

// ---- Kết quả xổ số (Miền Bắc / Miền Trung / Miền Nam, theo đài) ------------------------------------------

// ?date=YYYY-MM-DD (link from the Tính điểm day cards) opens that day.
const queryDate = String(useRoute().query.date || '')
const lotteryDate = ref(/^\d{4}-\d{2}-\d{2}$/.test(queryDate) ? queryDate : today())
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
const stationChoices = computed(() => stationsOn(region.value, lotteryDate.value))
const singleTiers = ['dacBiet', 'giaiNhat'] // stored as one string, every other group is a list

function blankLotteryForm() {
  const f = {}
  for (const p of structure.value) f[p.tier] = singleTiers.includes(p.tier) ? '' : Array(p.count).fill('')
  return f
}
const lotteryForm = reactive(blankLotteryForm())
const hasSavedLottery = ref(false)
// A saved result is only displayed; "Sửa" unlocks the boxes.
const lotteryEditing = ref(false)
const lotteryReadOnly = computed(() => hasSavedLottery.value && !lotteryEditing.value)
// A form object for the region's structure, filled from `values` where they fit.
function shapeForm(values) {
  const out = {}
  const blank = blankLotteryForm()
  for (const p of structure.value) {
    const v = values?.[p.tier]
    out[p.tier] = singleTiers.includes(p.tier) ? v || '' : Array.isArray(v) && v.length === p.count ? [...v] : blank[p.tier]
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
const flatValues = () => structure.value.flatMap((p) => [].concat(lotteryForm[p.tier] ?? ''))
const filledCount = computed(() => flatValues().filter((v) => (v || '').trim()).length)
const TOTAL_BOXES = computed(() => structure.value.reduce((n, p) => n + p.count, 0))
watch(filledCount, (n) => {
  if (n > 0) gridOpen.value = true
})
const lotteryDeleting = ref(false)

function applyLotteryResult(r) {
  hasSavedLottery.value = !!r
  lotteryEditing.value = false
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
    lotteryEditing.value = false
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
const boardLocked = (st) => !!boardSaved[st] && !boardEdit[st]

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
  const partial = todo.filter((st) => boardFilled(st) < total)
  if (partial.length) {
    lotteryError.value = `${partial.map(stationName).join(', ')}: chưa nhập đủ ${total} số. Điền đủ hoặc xoá hết cột đó rồi lưu lại.`
    return
  }
  lotterySaving.value = true
  try {
    for (const st of todo) {
      const body = { drawDate: lotteryDate.value, station: st }
      for (const p of structure.value) {
        const v = board[st][p.tier]
        body[p.tier] = Array.isArray(v) ? v.map((x) => x.trim()) : v.trim()
      }
      await api.post('/lottery-results', body)
      boardSaved[st] = true
      boardRead[st] = false
      boardEdit[st] = false
    }
    lotterySaveMsg.value = `Đã lưu kết quả ${todo.map(stationName).join(', ')} ngày ${lotteryDate.value.split('-').reverse().join('/')}.`
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
  lotteryEditing.value = true
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
      boardEdit[c.station] = true
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
  lotteryEditing.value = true
  if (lrOcrPreviewUrl.value) URL.revokeObjectURL(lrOcrPreviewUrl.value)
  lrOcrPreviewUrl.value = ''
  lrOcrError.value = ''
}
</script>

<template>
  <div class="page" :class="{ 'board-mode': region !== 'mb' }">
    <h1 class="page-title">Nhập kết quả</h1>
    <p class="page-subtitle">
      Nhập kết quả xổ số (Miền Bắc, Miền Trung, Miền Nam) rồi bấm "Lưu kết quả". Kết quả đã lưu chỉ hiển thị; bấm "Sửa" để chỉnh. Điểm ra của khách được tính tự động ở tab Tính điểm.
    </p>

    <div class="card lottery-card">
      <div class="lottery-head">
        <h3 style="margin: 0">Kết quả xổ số {{ stationLabelOf }}</h3>
        <div class="date-nav">
          <button type="button" class="btn btn-ghost btn-sm" aria-label="Ngày trước" title="Ngày trước" @click="shiftDay(-1)">‹</button>
          <AppDatePicker v-model="lotteryDate" class="lottery-date" />
          <button type="button" class="btn btn-ghost btn-sm" aria-label="Ngày sau" title="Ngày sau" @click="shiftDay(1)">›</button>
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

        <ul v-if="mcWarnings.length" class="mc-warnings">
          <li v-for="(w, i) in mcWarnings" :key="i">{{ w }}</li>
        </ul>
      </div>

      <div v-if="lotteryLoading" class="page-subtitle">Đang tải...</div>
      <template v-else>
        <div v-if="lotteryError" class="alert alert-error">{{ lotteryError }}</div>
        <div v-if="lotterySaveMsg" class="alert alert-success">{{ lotterySaveMsg }}</div>

        <div v-if="region !== 'mb'" class="board-wrap">
          <p v-if="!boardStations.length" class="page-subtitle">Ngày này không có đài nào của miền này.</p>
          <table v-else class="board" :style="{ '--cols': boardStations.length }">
            <thead>
              <tr>
                <th class="board-tier">Giải</th>
                <th v-for="st in boardStations" :key="st" :class="{ saved: boardSaved[st] }">
                  {{ stationName(st) }}
                  <span v-if="boardSaved[st]" class="board-saved">đã lưu</span>
                </th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="p in boardTiers" :key="p.tier" :class="{ 'board-top': p.tier === 'dacBiet' || p.tier === 'giaiTam' }">
                <th class="board-tier">{{ p.label }}</th>
                <td v-for="st in boardStations" :key="st">
                  <div class="board-cell">
                    <template v-if="board[st]">
                      <input
                        v-if="singleTiers.includes(p.tier)"
                        v-model="board[st][p.tier]"
                        :readonly="boardLocked(st)"
                        :maxlength="p.digits"
                        :placeholder="'0'.repeat(p.digits)"
                        :class="{ bad: cellBad(st, p, board[st][p.tier]), big: p.tier === 'dacBiet' }"
                        inputmode="numeric"
                        :aria-label="`${p.label} ${stationName(st)}`"
                      />
                      <input
                        v-for="(v, k) in board[st][p.tier]"
                        v-else
                        :key="k"
                        v-model="board[st][p.tier][k]"
                        :readonly="boardLocked(st)"
                        :maxlength="p.digits"
                        :placeholder="'0'.repeat(p.digits)"
                        :class="{ bad: cellBad(st, p, v) }"
                        inputmode="numeric"
                        :aria-label="`${p.label} ${stationName(st)} số ${k + 1}`"
                      />
                    </template>
                  </div>
                </td>
              </tr>
            </tbody>
            <tfoot>
              <tr>
                <th class="board-tier"></th>
                <td v-for="st in boardStations" :key="st">
                  <button v-if="boardLocked(st)" type="button" class="btn btn-secondary btn-sm" @click="boardEdit[st] = true">Sửa</button>
                  <button v-if="boardSaved[st]" type="button" class="btn btn-danger btn-sm" :disabled="boardDeleting === st" @click="deleteBoardColumn(st)">
                    {{ boardDeleting === st ? 'Đang xoá...' : 'Xoá kết quả' }}
                  </button>
                </td>
              </tr>
            </tfoot>
          </table>
          <div class="lottery-actions">
            <button type="button" class="btn btn-ghost btn-sm" @click="clearLotteryForm">Xoá form</button>
            <button type="button" class="btn btn-primary" :disabled="lotterySaving || !boardStations.length" @click="saveLottery">
              {{ lotterySaving ? 'Đang lưu...' : 'Lưu kết quả' }}
            </button>
          </div>
        </div>

        <button
          v-if="region === 'mb'"
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

        <div v-if="region === 'mb'" id="lottery-grid" class="lottery-grid" :class="{ collapsed: !gridOpen, readonly: lotteryReadOnly }">
          <div v-for="p in structure" :key="p.tier" class="tier-row">
            <label>{{ p.label }}<span class="tier-count">{{ p.count }} ô · {{ p.digits }} số</span></label>
            <input v-if="singleTiers.includes(p.tier)" v-model="lotteryForm[p.tier]" :readonly="lotteryReadOnly" :maxlength="p.digits" :placeholder="'0'.repeat(p.digits)" :class="`num${p.digits}`" inputmode="numeric" autocomplete="off" />
            <div v-else class="tier-inputs">
              <input
                v-for="(v, k) in lotteryForm[p.tier]"
                :key="k"
                v-model="lotteryForm[p.tier][k]"
                :readonly="lotteryReadOnly"
                :maxlength="p.digits"
                :placeholder="'0'.repeat(p.digits)"
                :class="`num${p.digits}`"
                inputmode="numeric"
                autocomplete="off"
              />
            </div>
          </div>
        </div>

        <div v-if="region === 'mb'" class="lottery-actions">
          <button
            v-if="hasSavedLottery"
            type="button"
            class="btn btn-danger btn-sm"
            :disabled="lotteryDeleting"
            @click="deleteLottery"
          >
            {{ lotteryDeleting ? 'Đang xoá...' : 'Xoá kết quả này' }}
          </button>
          <button v-if="lotteryReadOnly" type="button" class="btn btn-secondary btn-sm" @click="lotteryEditing = true">Sửa</button>
          <button type="button" class="btn btn-ghost btn-sm" @click="clearLotteryForm">Xoá form</button>
          <button type="button" class="btn btn-primary" :disabled="lotterySaving || lotteryReadOnly" @click="saveLottery">
            {{ lotterySaving ? 'Đang lưu...' : 'Lưu kết quả' }}
          </button>
        </div>
      </template>
    </div>

  </div>
</template>

<style scoped>
.lottery-card {
  margin-bottom: 16px;
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
.board-wrap {
  overflow-x: auto;
}
.board {
  width: 100%;
  max-width: 960px;
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
    grid-column: 1 / -1;
    grid-row: auto;
    max-width: 1100px;
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
</style>
