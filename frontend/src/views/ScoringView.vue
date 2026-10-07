<!--
  Tính điểm: own tab, separate from "Nhập kết quả" (ResultsView, which
  owns the lottery-draw-entry form + manual per-entry typing of "Điểm ra").
  This page is fully automatic - no input box, no save button. It shows ONE
  customer's numbers grouped by DAY (newest first, newest day open, older
  days collapsed), with per-day and per-range totals. For each number of an
  OPEN day:

  - looks up the saved lottery result (ResultsView) for THAT entry's own
    entryDate (cached per date);
  - if there isn't one yet, shows "Chưa có kết quả" and stops there -
    nothing is written;
  - if there is, compares the last N digits (configurable per bet type -
    2 for "đề"/"lô", 3 for "3 càng", 4 for "bao lô 4", ... - see
    /scoring-settings) of the entry's bet number(s) against the same count
    of trailing digits of the prize tiers this bet type is configured to
    check, multiplies by the configured payout rate on a match (0 if no
    match), and PATCHes that number to `data_entries.result` - but only when
    it differs from what is already saved (no redundant writes).
    Days are calculated when they are opened, so a long history costs
    nothing until you look at it.

  Also: "Ẩn số liệu" mask (figures show as •••• until the password is
  re-entered, see stores/mask.js), "Xóa số liệu" (bulk delete) and
  "Đặt lịch xóa" (scheduled / repeating delete) - all password protected.

  API: GET /lottery-results?date=, GET /me/scoring-settings, GET /me/entries,
       GET /me/customers, PATCH /me/entries/:id with only `{ result }`,
       POST /me/verify-password, POST /me/entries/bulk-delete,
       /me/deletion-schedules (inside DeletionSchedules.vue).
-->
<script setup>
import AppSelect from '../components/AppSelect.vue'
import AppIcon from '../components/AppIcon.vue'
import AppDatePicker from '../components/AppDatePicker.vue'
import MaskedValue from '../components/MaskedValue.vue'
import ModalDialog from '../components/ModalDialog.vue'
import PasswordPromptDialog from '../components/PasswordPromptDialog.vue'
import DeleteDataDialog from '../components/DeleteDataDialog.vue'
import DeletionSchedules from '../components/DeletionSchedules.vue'
import { onMounted, onBeforeUnmount, computed, reactive, ref, watch } from 'vue'
import { api } from '../api'
import { loadAllEntries } from '../offline'
import { betTypeLabel } from '../betTypes'
import { localDateString } from '../dates'
import { mask } from '../stores/mask'

const entries = ref([])
const loading = ref(true)
const loadError = ref('')
// Must pick ONE customer before anything shows - this page is a
// per-customer workspace (like Nhập số), not a browse-everyone list; that
// belongs on Khách hàng. Sourced from the same roster EntriesView reads.
const selectedCustomer = ref('')
const customers = ref([])
async function loadCustomers() {
  try {
    const { customers: list } = await api.get('/me/customers')
    customers.value = list
  } catch (_) {
    // Leave empty - the select will just show none.
  }
}
const onlyMissing = ref(false)

function formatNumber(n) {
  return new Intl.NumberFormat('vi-VN').format(n)
}

function toNumber(str) {
  if (!str) return 0
  const cleaned = String(str).replace(/[^\d.-]/g, '')
  const n = parseFloat(cleaned)
  return Number.isFinite(n) ? n : 0
}

async function load() {
  loading.value = true
  loadError.value = ''
  try {
    // every page; no local pending edits (records are PATCHed straight to the server here)
    const list = await loadAllEntries({ overlay: false })
    entries.value = list.entries
  } catch (err) {
    loadError.value = err.message || 'Không tải được số liệu'
  } finally {
    loading.value = false
  }
}

// ---- Date helpers ---------------------------------------------------------

const WEEKDAYS = ['Chủ nhật', 'Thứ hai', 'Thứ ba', 'Thứ tư', 'Thứ năm', 'Thứ sáu', 'Thứ bảy']
function dayLabel(iso) {
  const [y, m, d] = iso.split('-').map(Number)
  const wd = WEEKDAYS[new Date(y, m - 1, d).getDay()]
  return { date: `${String(d).padStart(2, '0')}/${String(m).padStart(2, '0')}/${y}`, weekday: wd }
}
function daysAgo(n) {
  const d = new Date()
  d.setDate(d.getDate() - n)
  return localDateString(d)
}

// ---- Date filter: quick chips + From/To ----------------------------------

const PRESETS = [
  { key: 'today', label: 'Hôm nay' },
  { key: '7', label: '7 ngày' },
  { key: '30', label: '30 ngày' },
  { key: 'all', label: 'Tất cả' },
]
const preset = ref('all')
const dateFrom = ref('')
const dateTo = ref('')
function setPreset(key) {
  preset.value = key
  if (key === 'today') [dateFrom.value, dateTo.value] = [daysAgo(0), daysAgo(0)]
  else if (key === '7') [dateFrom.value, dateTo.value] = [daysAgo(6), daysAgo(0)]
  else if (key === '30') [dateFrom.value, dateTo.value] = [daysAgo(29), daysAgo(0)]
  else [dateFrom.value, dateTo.value] = ['', '']
}
function onRangeInput() {
  preset.value = ''
}

const PAGE_DAYS = 10
const shownDays = ref(PAGE_DAYS)
watch([selectedCustomer, dateFrom, dateTo, onlyMissing], () => {
  shownDays.value = PAGE_DAYS
})

// ---- Grouping by day -------------------------------------------------------

const lotteryCache = reactive({}) // date -> result | null, avoids refetching the same day twice
// entry.id -> { state: 'computing'|'no-lottery'|'saved'|'error', value, error }
const resultStatus = reactive({})

const rangeEntries = computed(() => {
  if (!selectedCustomer.value) return []
  return entries.value.filter((e) => {
    if (e.customerName !== selectedCustomer.value) return false
    if (dateFrom.value && e.entryDate < dateFrom.value) return false
    if (dateTo.value && e.entryDate > dateTo.value) return false
    return true
  })
})

// 'yes' | 'no' | undefined (not looked up yet)
function lotteryState(date) {
  if (!(date in lotteryCache)) return undefined
  return lotteryCache[date] ? 'yes' : 'no'
}

// Collapsed days are summed from an in-memory calculation (no request, no
// save); only opened days are written back to the server.
function entryOut(e) {
  const st = resultStatus[e.id]
  if (st?.state === 'saved') return st.value
  const lr = lotteryCache[e.entryDate]
  return lr ? scoreEntry(e, lr) : toNumber(e.result)
}

// Every day in range, newest first, with its figures. `settled` = a lottery
// result exists, only then is "Điểm ra" / profit meaningful.
const allDays = computed(() => {
  const map = new Map()
  for (const e of rangeEntries.value) {
    if (!map.has(e.entryDate)) map.set(e.entryDate, [])
    map.get(e.entryDate).push(e)
  }
  return [...map.keys()]
    .sort((a, b) => (a < b ? 1 : a > b ? -1 : 0))
    .map((date) => {
      const list = map.get(date)
      const lot = lotteryState(date)
      let totalIn = 0
      let totalOut = 0
      for (const e of list) {
        totalIn += toNumber(e.score)
        totalOut += entryOut(e)
      }
      return { date, entries: list, lottery: lot, settled: lot === 'yes', totalIn, totalOut, profit: totalOut - totalIn }
    })
})

// `onlyMissing` = only days that have no lottery result yet.
const days = computed(() => (onlyMissing.value ? allDays.value.filter((d) => d.lottery === 'no') : allDays.value))
const visibleDays = computed(() => days.value.slice(0, shownDays.value))
const hiddenDayCount = computed(() => Math.max(0, days.value.length - shownDays.value))

const totals = computed(() => {
  let rows = 0
  let totalIn = 0
  let settledIn = 0
  let settledOut = 0
  for (const d of days.value) {
    rows += d.entries.length
    totalIn += d.totalIn
    if (d.settled) {
      settledIn += d.totalIn
      settledOut += d.totalOut
    }
  }
  return { days: days.value.length, rows, totalIn, settledOut, profit: settledOut - settledIn, hasSettled: days.value.some((d) => d.settled) }
})

// ---- Open / collapse day cards ---------------------------------------------

const openState = reactive({}) // date -> bool; undefined = default (newest day open)
function isOpen(date) {
  if (date in openState) return openState[date]
  return days.value.length > 0 && days.value[0].date === date
}
function toggleDay(date) {
  openState[date] = !isOpen(date)
}

// ---- Tính điểm ra tự động (tự tính, chỉ lưu khi khác) ------------------------

const autoCalcRunning = ref(0)
const autoCalcError = ref('')
// type key ('de', 'lo', ...) -> { rate, tiers }, from this account's own
// config (see /scoring-settings - `tiers` is which of the 8 prize groups
// count as a match for that type, e.g. đề only checks "dacBiet" by
// default). Default matches the backend's built-in fallback so the page
// still works even if that call fails.
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
    // Keep the fallback rates if this fails - non-fatal, calc still works.
  }
}

function configFor(betType) {
  const key = betType || 'de'
  return rates.value[key] ?? rates.value.de
}

function rateFor(betType) {
  return configFor(betType)?.rate ?? 70
}

function digitsFor(betType) {
  return configFor(betType)?.digits ?? 2
}

function normDigits(str, count) {
  const digits = String(str || '').replace(/\D/g, '')
  if (!digits) return ''
  return digits.slice(-count).padStart(count, '0')
}

// Only the numbers from the tiers this bet type is configured to check
// (e.g. đề -> just "dacBiet"), not always all 27 - see PUT
// /me/scoring-settings.
function numbersForTiers(r, tiers) {
  const byTier = {
    dacBiet: [r.dacBiet],
    giaiNhat: [r.giaiNhat],
    giaiNhi: r.giaiNhi,
    giaiBa: r.giaiBa,
    giaiTu: r.giaiTu,
    giaiNam: r.giaiNam,
    giaiSau: r.giaiSau,
    giaiBay: r.giaiBay,
  }
  return tiers.flatMap((t) => byTier[t] || [])
}

async function fetchLotteryFor(date) {
  if (date in lotteryCache) return lotteryCache[date]
  try {
    const { result } = await api.get(`/lottery-results?date=${date}`)
    lotteryCache[date] = result
    return result
  } catch (_) {
    lotteryCache[date] = null
    return null
  }
}

// Pure calculation (no network): points out for one entry against a day's result.
function scoreEntry(entry, lr) {
  const config = configFor(entry.betType)
  const digits = config.digits || 2
  const trailing = numbersForTiers(lr, config.tiers).map((n) => n.slice(-digits))
  const bets = (entry.value || '')
    .split(/[,;\s]+/)
    .map((v) => normDigits(v, digits))
    .filter(Boolean)
  let matches = 0
  for (const b of bets) matches += trailing.filter((x) => x === b).length
  const score = toNumber(entry.score)
  return matches > 0 ? score * config.rate * matches : 0
}

async function computeOne(entry) {
  resultStatus[entry.id] = { state: 'computing', value: null }
  const lr = await fetchLotteryFor(entry.entryDate)
  if (!lr) {
    resultStatus[entry.id] = { state: 'no-lottery', value: null }
    return
  }
  const value = scoreEntry(entry, lr)
  // Already saved with the same figure -> nothing to write.
  if (entry.result !== null && entry.result !== undefined && entry.result !== '' && toNumber(entry.result) === value) {
    resultStatus[entry.id] = { state: 'saved', value }
    return
  }
  try {
    const updated = await api.patch(`/me/entries/${entry.id}`, { result: String(value) })
    const idx = entries.value.findIndex((e) => e.id === entry.id)
    if (idx !== -1) entries.value[idx] = updated
    resultStatus[entry.id] = { state: 'saved', value }
  } catch (err) {
    resultStatus[entry.id] = { state: 'error', value, error: err.message || 'Không lưu được' }
  }
}

// customer|date|version keys of days already calculated; bumping `calcVersion`
// ("Tính lại") forgets them all.
const calculated = new Set()
const calcVersion = ref(0)

async function computeDay(day) {
  const key = `${selectedCustomer.value}|${day.date}|${calcVersion.value}`
  if (calculated.has(key)) return
  calculated.add(key)
  autoCalcRunning.value++
  try {
    for (const entry of day.entries) await computeOne(entry)
  } catch (err) {
    autoCalcError.value = err.message || 'Có lỗi khi tính điểm ra'
  } finally {
    autoCalcRunning.value--
  }
}

// Calculate every day that is open and on screen (and any that gets opened).
watch(
  () => visibleDays.value.filter((d) => isOpen(d.date)).map((d) => d.date).join('|') + `#${selectedCustomer.value}#${calcVersion.value}`,
  () => {
    for (const d of visibleDays.value) if (isOpen(d.date)) computeDay(d)
  },
  { immediate: true },
)

// Look the lottery result up for the days we show (and, for the "only days
// without a result" filter + the range totals, for every day in range) so the
// status badges are right even on collapsed cards. Cached per date.
let prefetchToken = 0
async function prefetchLottery() {
  const token = ++prefetchToken
  const dates = allDays.value.map((d) => d.date).filter((d) => !(d in lotteryCache))
  const queue = [...dates]
  const worker = async () => {
    while (queue.length && token === prefetchToken) await fetchLotteryFor(queue.shift())
  }
  await Promise.all([worker(), worker(), worker(), worker()])
}
watch(
  () => allDays.value.map((d) => d.date).join('|') + `#${calcVersion.value}`,
  () => prefetchLottery(),
  { immediate: true },
)

function recalc() {
  calculated.clear()
  for (const k of Object.keys(lotteryCache)) delete lotteryCache[k]
  calcVersion.value++
}

// ---- Ẩn số liệu ---------------------------------------------------------------

const masked = mask.masked
const maskEnabled = computed(() => mask.state.enabled)
const promptOpen = ref(false)
const promptPurpose = ref('reveal') // 'reveal' | 'disable'
function toggleMask() {
  if (!mask.state.enabled) mask.enable()
  else openPrompt('disable')
}
function openPrompt(purpose) {
  promptPurpose.value = purpose
  promptOpen.value = true
}
function onVerified() {
  promptOpen.value = false
  if (promptPurpose.value === 'disable') mask.disable()
  else mask.reveal()
}

// ---- Xóa số liệu / Đặt lịch xóa -----------------------------------------------

const deleteOpen = ref(false)
const deleteDay = ref('')
const scheduleOpen = ref(false)
const notice = ref('')
function openDelete(date = '') {
  deleteDay.value = date
  deleteOpen.value = true
}
async function onDeleted(n) {
  deleteOpen.value = false
  notice.value = `Đã xóa ${n} số liệu.`
  calculated.clear()
  await load()
}

onMounted(async () => {
  mask.attach()
  await Promise.all([load(), loadRates(), loadCustomers()])
})
onBeforeUnmount(() => mask.detach())
</script>

<template>
  <div class="page">
    <h1 class="page-title">Tính điểm</h1>
    <p class="page-subtitle">
      Điểm ra được máy tự động tính và lưu, theo kết quả xổ số đã nhập ở trang
      <RouterLink :to="{ name: 'results' }" class="tap-link">Nhập kết quả</RouterLink>. Đổi tỉ lệ ăn ở trang
      <RouterLink :to="{ name: 'scoring-settings' }" class="tap-link">Cấu hình tính điểm</RouterLink>.
    </p>

    <div class="toolbar card">
      <div class="toolbar-mask">
        <button
          type="button"
          class="mask-switch"
          role="switch"
          :aria-checked="maskEnabled"
          :class="{ on: maskEnabled }"
          @click="toggleMask"
        >
          <AppIcon :name="maskEnabled ? 'eye-off' : 'eye'" />
          Ẩn số liệu
          <span class="mask-state">{{ maskEnabled ? 'Bật' : 'Tắt' }}</span>
        </button>
        <button v-if="maskEnabled && masked" type="button" class="btn btn-secondary btn-sm" @click="openPrompt('reveal')">
          <AppIcon name="eye" /> Hiện
        </button>
        <button v-else-if="maskEnabled" type="button" class="btn btn-secondary btn-sm" @click="mask.cover()">
          <AppIcon name="eye-off" /> Che lại
        </button>
      </div>
      <div class="toolbar-actions">
        <button type="button" class="btn btn-secondary btn-sm" @click="openDelete('')">Xóa số liệu</button>
        <button type="button" class="btn btn-secondary btn-sm" @click="scheduleOpen = true">Đặt lịch xóa</button>
      </div>
    </div>

    <div v-if="autoCalcError" class="alert alert-error">{{ autoCalcError }}</div>
    <div v-if="notice" class="alert alert-success" role="status">{{ notice }}</div>

    <div v-if="loading" class="card">Đang tải...</div>
    <div v-else-if="loadError" class="alert alert-error">{{ loadError }}</div>
    <template v-else>
      <div class="filters card">
        <div class="field filter-customer">
          <label>Khách hàng</label>
          <div class="input-wrap">
            <AppSelect v-model="selectedCustomer">
              <option value="">-- Chọn khách hàng --</option>
              <option v-for="c in customers" :key="c.id" :value="c.name">{{ c.name }}</option>
            </AppSelect>
          </div>
        </div>
        <div class="filter-range">
          <div class="range-chips" role="group" aria-label="Lọc nhanh theo ngày">
            <button
              v-for="p in PRESETS"
              :key="p.key"
              type="button"
              class="range-chip"
              :class="{ on: preset === p.key }"
              :aria-pressed="preset === p.key"
              @click="setPreset(p.key)"
            >
              {{ p.label }}
            </button>
          </div>
          <div class="range-dates">
            <div class="field">
              <label>Từ ngày</label>
              <AppDatePicker v-model="dateFrom" @change="onRangeInput" />
            </div>
            <div class="field">
              <label>Đến ngày</label>
              <AppDatePicker v-model="dateTo" @change="onRangeInput" />
            </div>
          </div>
        </div>
        <label class="check-field">
          <input type="checkbox" v-model="onlyMissing" />
          Chỉ hiện số liệu chưa có kết quả xổ số
        </label>
        <button
          type="button"
          class="btn btn-secondary btn-sm"
          :disabled="autoCalcRunning > 0 || !selectedCustomer"
          @click="recalc"
        >
          {{ autoCalcRunning > 0 ? 'Đang tính...' : '↻ Tính lại' }}
        </button>
      </div>

      <div v-if="!selectedCustomer" class="card empty-state">
        <AppIcon name="users" class="empty-icon" />
        <p>Chọn khách hàng ở trên để xem điểm ra của họ.</p>
      </div>
      <div v-else-if="days.length === 0" class="card empty-state">
        {{
          onlyMissing
            ? 'Không có ngày nào thiếu kết quả xổ số trong khoảng này. Bỏ chọn ô lọc để xem toàn bộ lịch sử.'
            : rangeEntries.length === 0 && entries.some((e) => e.customerName === selectedCustomer)
              ? 'Không có số liệu nào trong khoảng ngày này. Chọn "Tất cả" để xem lịch sử.'
              : 'Khách hàng này chưa có số liệu nào.'
        }}
      </div>

      <template v-else>
        <div class="card totals" aria-label="Tổng khoảng đang chọn">
          <div class="totals-head">
            <strong>Tổng · {{ selectedCustomer }}</strong>
            <span class="page-subtitle">{{ totals.days }} ngày · {{ totals.rows }} số</span>
          </div>
          <div class="totals-grid">
            <div class="cell">
              <span class="cell-label">Tổng điểm vào</span>
              <span class="cell-value"><MaskedValue :text="formatNumber(totals.totalIn)" /></span>
            </div>
            <div class="cell">
              <span class="cell-label">Tổng điểm ra</span>
              <span class="cell-value"><MaskedValue :text="formatNumber(totals.settledOut)" /></span>
            </div>
            <div class="cell">
              <span class="cell-label">Lợi nhuận</span>
              <span class="cell-value" :class="!masked && totals.profit > 0 ? 'pos' : !masked && totals.profit < 0 ? 'neg' : ''">
                <MaskedValue :text="(totals.profit > 0 ? '+' : '') + formatNumber(totals.profit)" />
              </span>
            </div>
          </div>
          <p class="totals-note">Điểm ra và lợi nhuận chỉ tính các ngày đã có kết quả xổ số.</p>
        </div>

        <div class="day-list">
          <section v-for="day in visibleDays" :key="day.date" class="card day-card" :class="{ open: isOpen(day.date) }">
            <div class="day-head">
              <button
                type="button"
                class="day-toggle"
                :aria-expanded="isOpen(day.date)"
                :aria-controls="`day-${day.date}`"
                @click="toggleDay(day.date)"
              >
                <div class="day-title">
                  <AppIcon name="chevron-down" class="day-chevron" />
                  <strong>{{ dayLabel(day.date).date }}</strong>
                  <span class="day-weekday">{{ dayLabel(day.date).weekday }}</span>
                  <span class="chip count-chip">{{ day.entries.length }} dòng</span>
                </div>
                <div class="day-figures">
                  <div class="cell">
                    <span class="cell-label">Điểm vào</span>
                    <span class="cell-value"><MaskedValue :text="formatNumber(day.totalIn)" /></span>
                  </div>
                  <div class="cell">
                    <span class="cell-label">Điểm ra</span>
                    <span class="cell-value">
                      <template v-if="day.settled"><MaskedValue :text="formatNumber(day.totalOut)" /></template>
                      <template v-else>-</template>
                    </span>
                  </div>
                  <div class="cell">
                    <span class="cell-label">Lợi nhuận</span>
                    <span class="cell-value" :class="day.settled && !masked ? (day.profit > 0 ? 'pos' : day.profit < 0 ? 'neg' : '') : ''">
                      <template v-if="day.settled">
                        <MaskedValue :text="(day.profit > 0 ? '+' : '') + formatNumber(day.profit)" />
                      </template>
                      <template v-else>-</template>
                    </span>
                  </div>
                </div>
              </button>
              <div class="day-meta">
                <span v-if="day.lottery === 'yes'" class="chip chip-ok">Đã có kết quả xổ số</span>
                <template v-else-if="day.lottery === 'no'">
                  <span class="chip chip-warn">Chưa có kết quả xổ số</span>
                  <RouterLink :to="{ name: 'results', query: { date: day.date } }" class="tap-link meta-link">Nhập kết quả</RouterLink>
                </template>
                <span v-else class="chip">Đang kiểm tra...</span>
                <button type="button" class="btn btn-ghost btn-sm day-del" @click="openDelete(day.date)">Xóa ngày này</button>
              </div>
            </div>

            <div v-if="isOpen(day.date)" :id="`day-${day.date}`" class="result-list">
              <div v-for="entry in day.entries" :key="entry.id" class="result-row">
                <div class="result-row-top">
                  <span class="chip">{{ betTypeLabel(entry.betType || 'de') }} × {{ rateFor(entry.betType) }}</span>
                  <span class="chip">{{ digitsFor(entry.betType) }} số cuối</span>
                  <span
                    v-if="resultStatus[entry.id]?.state === 'saved' && !masked"
                    class="chip"
                    :class="resultStatus[entry.id].value > 0 ? 'chip-accent' : ''"
                  >
                    <AppIcon v-if="resultStatus[entry.id].value > 0" name="check" />
                    {{ resultStatus[entry.id].value > 0 ? 'Trúng' : 'Không trúng' }}
                  </span>
                </div>
                <div class="result-cells">
                  <div class="cell">
                    <span class="cell-label">Số</span>
                    <span class="cell-value cell-number"><MaskedValue :text="entry.value" /></span>
                  </div>
                  <div class="cell">
                    <span class="cell-label">Điểm vào</span>
                    <span class="cell-value">
                      <MaskedValue :text="entry.score ? formatNumber(Number(entry.score) || entry.score) : '-'" />
                    </span>
                  </div>
                  <div class="cell">
                    <span class="cell-label">Điểm ra</span>
                    <template v-if="resultStatus[entry.id]?.state === 'computing'">
                      <span class="cell-value cell-pending">Đang tính...</span>
                    </template>
                    <template v-else-if="resultStatus[entry.id]?.state === 'no-lottery'">
                      <span class="cell-value cell-pending">Chưa có kết quả</span>
                    </template>
                    <template v-else-if="resultStatus[entry.id]?.state === 'error'">
                      <span class="cell-value cell-error">{{ resultStatus[entry.id].error }}</span>
                    </template>
                    <template v-else-if="resultStatus[entry.id]?.state === 'saved'">
                      <span class="cell-value" :class="!masked && resultStatus[entry.id].value > 0 ? 'cell-win' : ''">
                        <MaskedValue :text="formatNumber(resultStatus[entry.id].value)" />
                      </span>
                    </template>
                    <template v-else>
                      <span class="cell-value cell-pending">
                        <template v-if="entry.result"><MaskedValue :text="formatNumber(Number(entry.result) || 0)" /></template>
                        <template v-else>Chưa có kết quả</template>
                      </span>
                    </template>
                  </div>
                </div>
              </div>
            </div>
          </section>
        </div>

        <button v-if="hiddenDayCount > 0" type="button" class="btn btn-secondary more-btn" @click="shownDays += PAGE_DAYS">
          Xem thêm ngày cũ ({{ Math.min(PAGE_DAYS, hiddenDayCount) }} / còn {{ hiddenDayCount }} ngày)
        </button>
      </template>
    </template>

    <PasswordPromptDialog
      :open="promptOpen"
      :title="promptPurpose === 'disable' ? 'Tắt ẩn số liệu' : 'Hiện số liệu'"
      :description="
        promptPurpose === 'disable'
          ? 'Nhập mật khẩu đăng nhập để tắt chế độ ẩn số liệu.'
          : 'Nhập mật khẩu đăng nhập để xem số liệu. Số liệu sẽ tự ẩn lại sau 5 phút.'
      "
      @verified="onVerified"
      @close="promptOpen = false"
    />
    <DeleteDataDialog
      :open="deleteOpen"
      :customer-name="selectedCustomer"
      :date-from="dateFrom"
      :date-to="dateTo"
      :single-day="deleteDay"
      @deleted="onDeleted"
      @close="deleteOpen = false"
    />
    <ModalDialog :open="scheduleOpen" title="Đặt lịch xóa" wide @close="scheduleOpen = false">
      <DeletionSchedules embedded :customer-name="selectedCustomer" />
      <template #footer>
        <button type="button" class="btn btn-secondary" @click="scheduleOpen = false">Đóng</button>
      </template>
    </ModalDialog>
  </div>
</template>

<style scoped>
.page-subtitle a {
  color: var(--text-secondary);
  font-weight: 500;
  text-decoration: underline;
  text-underline-offset: 3px;
  text-decoration-color: color-mix(in srgb, var(--text-secondary) 50%, transparent);
}
.page-subtitle a:hover {
  color: var(--link);
  text-decoration-color: currentColor;
}

/* ---- Top toolbar: mask switch + delete actions ---- */
.toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: 10px 16px;
  margin-bottom: 16px;
  padding: 12px 16px;
  border-radius: 14px;
}
.toolbar-mask,
.toolbar-actions {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 8px;
}
.mask-switch {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  min-height: 44px;
  padding: 0 14px;
  font-size: 14px;
  font-weight: 700;
  color: var(--text-primary);
  background: var(--surface);
  border: 1px solid var(--input-border);
  border-radius: 10px;
  cursor: pointer;
}
.mask-switch.on {
  color: var(--on-primary);
  background: var(--primary);
  border-color: var(--primary);
}
.mask-state {
  padding: 1px 8px;
  font-size: 12px;
  background: color-mix(in srgb, currentColor 18%, transparent);
  border-radius: 999px;
}
.toolbar .btn,
.more-btn,
.day-del {
  min-height: 44px;
  padding: 0 16px;
  font-size: 14px;
  border-radius: 10px;
}
.toolbar .btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
}

/* ---- Filters ---- */
.filters {
  display: flex;
  justify-content: flex-start;
  align-items: flex-end;
  flex-wrap: wrap;
  gap: 12px 24px;
  margin-bottom: 16px;
  padding: 16px 20px;
  border-radius: 14px;
}
.filter-customer {
  flex: 0 1 320px;
  min-width: 220px;
  margin: 0;
}
.filter-customer label,
.range-dates label {
  font-size: 14px;
  font-weight: 700;
  color: var(--text-primary);
  margin-bottom: 6px;
}
.filter-range {
  display: flex;
  flex-direction: column;
  gap: 10px;
  flex: 1 1 340px;
}
.range-chips {
  display: flex;
  justify-content: flex-start;
  align-self: flex-start;
  flex-wrap: wrap;
  gap: 8px;
}
.range-chip {
  min-height: 44px;
  padding: 0 16px;
  font-size: 14px;
  font-weight: 600;
  color: var(--text-primary);
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 999px;
  cursor: pointer;
}
.range-chip.on {
  color: var(--on-primary);
  background: var(--primary);
  border-color: var(--primary);
}
.range-dates {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
}
.range-dates .field {
  margin: 0;
}
.check-field {
  display: flex;
  align-items: center;
  gap: 10px;
  min-height: 44px;
  font-size: 14px;
  color: var(--text);
  cursor: pointer;
}
.check-field input {
  width: 18px;
  height: 18px;
  accent-color: var(--primary);
}
.filters .btn {
  min-height: 44px;
  padding: 0 18px;
  font-size: 14px;
  border-radius: 10px;
}

/* ---- Empty state ---- */
.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 12px;
  min-height: 160px;
  padding: 32px 24px;
  background: var(--surface);
  border: 1px dashed var(--input-border);
  border-radius: 14px;
  color: var(--text-secondary);
  font-size: 15px;
  text-align: center;
}
.empty-state p {
  margin: 0;
}
.empty-icon {
  width: 32px;
  height: 32px;
  color: var(--text-secondary);
  opacity: 0.7;
}

/* ---- Range totals ---- */
.totals {
  margin-bottom: 16px;
  padding: 16px 20px;
  border-radius: 14px;
  border-color: color-mix(in srgb, var(--primary) 45%, var(--border));
}
.totals-head {
  display: flex;
  align-items: baseline;
  flex-wrap: wrap;
  gap: 4px 12px;
  margin-bottom: 10px;
}
.totals-head strong {
  font-size: 17px;
}
.totals-head .page-subtitle,
.totals-note {
  margin: 0;
  font-size: 14px;
  color: var(--text-secondary);
}
.totals-note {
  margin-top: 10px;
}
.totals-grid,
.day-figures {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 12px;
}

/* ---- Day cards ---- */
.day-list {
  display: flex;
  flex-direction: column;
  gap: 12px;
}
.day-card {
  padding: 0;
  border-radius: 14px;
  overflow: hidden;
}
.day-head {
  display: flex;
  flex-direction: column;
}
.day-toggle {
  display: flex;
  flex-direction: column;
  gap: 10px;
  width: 100%;
  min-height: 44px;
  padding: 14px 20px 8px;
  font: inherit;
  color: inherit;
  text-align: left;
  background: transparent;
  border: 0;
  cursor: pointer;
}
.day-toggle:hover {
  background: color-mix(in srgb, var(--primary) 5%, transparent);
}
.day-toggle:focus-visible {
  outline: 3px solid color-mix(in srgb, var(--primary) 55%, transparent);
  outline-offset: -3px;
}
.day-title {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 4px 10px;
}
.day-title strong {
  font-size: 17px;
}
.day-weekday {
  font-size: 14px;
  color: var(--text-secondary);
}
.day-chevron {
  width: 20px;
  height: 20px;
  color: var(--text-secondary);
  transform: rotate(-90deg);
  transition: transform 0.15s ease;
}
.day-card.open .day-chevron {
  transform: none;
}
.count-chip {
  font-size: 12px;
}
.day-meta {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 6px 12px;
  padding: 0 20px 12px;
}
.meta-link {
  font-size: 14px;
  font-weight: 600;
  color: var(--link);
  text-decoration: underline;
  text-underline-offset: 3px;
}
.day-del {
  margin-left: auto;
  color: var(--danger-text);
}
.chip-ok {
  background: var(--success-soft);
  color: var(--success-text);
}
.chip-warn {
  background: var(--warning-soft);
  color: var(--warning-text);
}
.more-btn {
  display: block;
  width: 100%;
  margin-top: 16px;
}

/* ---- Figures ---- */
.cell {
  display: flex;
  flex-direction: column;
  min-width: 0;
  gap: 2px;
}
.cell-label {
  font-size: 14px;
  color: var(--text-secondary);
}
.cell-value {
  font-size: 15px;
  font-weight: 600;
  font-variant-numeric: tabular-nums;
  color: var(--text-primary);
  overflow-wrap: anywhere;
}
.cell-pending {
  color: var(--muted);
  font-weight: 600;
  font-style: italic;
}
.cell-error {
  color: var(--danger-text);
  font-weight: 600;
}
.pos,
.cell-win {
  color: var(--success-text);
}
.neg {
  color: var(--danger-text);
}

/* ---- Entries inside a day: compact 2-column item grid ---- */
.result-list {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 12px;
  padding: 8px 20px 20px;
  border-top: 1px solid var(--border);
  padding-top: 16px;
}
.result-row {
  display: flex;
  flex-direction: column;
  gap: 10px;
  padding: 12px 14px;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 12px;
}
.result-row-top {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-wrap: wrap;
}
.result-row-top .chip {
  font-size: 14px;
  padding: 3px 10px;
  background: var(--card);
  border: 1px solid var(--border);
}
/* Trúng = success; Không trúng = neutral (default chip) */
.result-row-top .chip.chip-accent {
  background: var(--success-soft);
  color: var(--success-text);
  border-color: transparent;
}
.result-cells {
  display: grid;
  grid-template-columns: 1.1fr 1fr 1.3fr;
  gap: 12px;
}
/* Số and Điểm ra carry the weight */
.cell-number,
.result-cells .cell:last-child .cell-value {
  font-size: 20px;
  font-weight: 800;
  line-height: 1.2;
}
.result-cells .cell:last-child .cell-pending,
.result-cells .cell:last-child .cell-error {
  font-size: 14px;
  font-weight: 600;
  line-height: 1.3;
}

@media (max-width: 720px) {
  .result-list {
    grid-template-columns: 1fr;
    padding: 16px 12px 16px;
  }
}
@media (max-width: 640px) {
  .filters {
    align-items: stretch;
    padding: 16px;
  }
  .filter-customer,
  .filter-range {
    flex: 1 1 100%;
  }
  .range-dates {
    gap: 8px;
  }
  .toolbar {
    padding: 12px;
  }
  .toolbar-actions,
  .toolbar-actions .btn {
    flex: 1 1 auto;
  }
  .totals {
    padding: 16px;
  }
  .day-toggle {
    padding: 14px 16px 8px;
  }
  .day-meta {
    padding: 0 16px 12px;
  }
  .totals-grid,
  .day-figures {
    gap: 8px;
  }
  .cell-value {
    font-size: 14px;
  }
}
</style>
