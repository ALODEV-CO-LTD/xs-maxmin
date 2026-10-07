<!--
  Tính điểm: own tab, separate from "Nhập kết quả" (ResultsView, which
  owns the lottery-draw-entry form + manual per-entry typing of "Điểm ra").
  This page is fully automatic and READ-ONLY - no input box, no save
  button. For each of the selected customer's numbers:

  - looks up the saved lottery result (ResultsView) for THAT entry's own
    entryDate (entries can span different days);
  - if there isn't one yet, shows "Chưa có kết quả" and stops there -
    nothing is written;
  - if there is, compares the last N digits (configurable per bet type -
    2 for "đề"/"lô", 3 for "3 càng", 4 for "bao lô 4", ... - see
    /scoring-settings) of the entry's bet number(s) against the same count
    of trailing digits of the prize tiers this bet type is configured to
    check, multiplies by the
    configured payout rate on a match (0 if no match), and PATCHes that
    number straight to `data_entries.result` - no manual "Lưu" step, this
    page's whole point is "the machine computes and returns the result".
    Recomputes (and re-saves) every time the page loads/customer changes,
    so it always reflects the current lottery result + rate config even
    if either changed after the first calculation.

  API: GET /lottery-results, GET /me/scoring-settings, GET /me/entries,
       GET /me/customers, PATCH /me/entries/:id with only `{ result }`.
-->
<script setup>
import AppSelect from '../components/AppSelect.vue'
import AppIcon from '../components/AppIcon.vue'
import { onMounted, computed, reactive, ref, watch } from 'vue'
import { api } from '../api'
import { loadAllEntries } from '../offline'
import { betTypeLabel } from '../betTypes'

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

// Only this one customer's entries - nothing shows until one is picked.
// `onlyMissing` here means "chưa tính được điểm ra" (still 'no-lottery'),
// not "chưa lưu" (there's nothing to save/miss anymore).
const filtered = computed(() => {
  if (!selectedCustomer.value) return []
  return entries.value.filter((e) => {
    if (e.customerName !== selectedCustomer.value) return false
    if (onlyMissing.value && resultStatus[e.id]?.state !== 'no-lottery') return false
    return true
  })
})

// ---- Tính điểm ra tự động (tự tính, tự lưu) ----------------------------

const lotteryCache = reactive({}) // date -> result | null, avoids refetching the same day twice
const autoCalcRunning = ref(false)
const autoCalcError = ref('')
// entry.id -> { state: 'computing'|'no-lottery'|'saved'|'error', value, error }
const resultStatus = reactive({})
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

async function computeOne(entry) {
  resultStatus[entry.id] = { state: 'computing', value: null }
  const lr = await fetchLotteryFor(entry.entryDate)
  if (!lr) {
    resultStatus[entry.id] = { state: 'no-lottery', value: null }
    return
  }
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
  const value = matches > 0 ? score * config.rate * matches : 0
  try {
    const updated = await api.patch(`/me/entries/${entry.id}`, { result: String(value) })
    const idx = entries.value.findIndex((e) => e.id === entry.id)
    if (idx !== -1) entries.value[idx] = updated
    resultStatus[entry.id] = { state: 'saved', value }
  } catch (err) {
    resultStatus[entry.id] = { state: 'error', value, error: err.message || 'Không lưu được' }
  }
}

async function computeAll() {
  autoCalcError.value = ''
  autoCalcRunning.value = true
  try {
    for (const entry of filtered.value) {
      await computeOne(entry)
    }
  } catch (err) {
    autoCalcError.value = err.message || 'Có lỗi khi tính điểm ra'
  } finally {
    autoCalcRunning.value = false
  }
}

// Compute (and save) automatically as soon as a customer's numbers are on
// screen - this page has no manual step at all.
onMounted(async () => {
  await Promise.all([load(), loadRates(), loadCustomers()])
  if (selectedCustomer.value) await computeAll()
})

watch(selectedCustomer, () => {
  if (selectedCustomer.value) computeAll()
})
</script>

<template>
  <div class="page">
    <h1 class="page-title">Tính điểm</h1>
    <p class="page-subtitle">
      Điểm ra được máy tự động tính và lưu, theo kết quả xổ số đã nhập ở trang
      <RouterLink :to="{ name: 'results' }" class="tap-link">Nhập kết quả</RouterLink>. Đổi tỉ lệ ăn ở trang
      <RouterLink :to="{ name: 'scoring-settings' }" class="tap-link">Cấu hình tính điểm</RouterLink>.
    </p>

    <div v-if="autoCalcError" class="alert alert-error">{{ autoCalcError }}</div>

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
        <label class="check-field">
          <input type="checkbox" v-model="onlyMissing" />
          Chỉ hiện số liệu chưa có kết quả xổ số
        </label>
        <button
          type="button"
          class="btn btn-secondary btn-sm"
          :disabled="autoCalcRunning || !selectedCustomer"
          @click="computeAll"
        >
          {{ autoCalcRunning ? 'Đang tính...' : '↻ Tính lại' }}
        </button>
      </div>

      <div v-if="!selectedCustomer" class="card empty-state">
        <AppIcon name="users" class="empty-icon" />
        <p>Chọn khách hàng ở trên để xem điểm ra của họ.</p>
      </div>
      <div v-else-if="filtered.length === 0" class="card empty-state">
        {{ onlyMissing ? 'Không còn số liệu nào thiếu kết quả xổ số.' : 'Khách hàng này chưa có số liệu nào.' }}
      </div>

      <div v-else class="card customer-group">
        <div class="customer-group-head">
          <strong>{{ selectedCustomer }}</strong>
          <span class="page-subtitle">{{ filtered.length }} số</span>
        </div>

        <div class="result-list">
          <div v-for="entry in filtered" :key="entry.id" class="result-row">
            <div class="result-row-top">
              <span class="chip">{{ betTypeLabel(entry.betType || 'de') }} × {{ rateFor(entry.betType) }}</span>
              <span class="chip">{{ digitsFor(entry.betType) }} số cuối</span>
              <span class="chip">{{ entry.entryDate }}</span>
              <span
                v-if="resultStatus[entry.id]?.state === 'saved'"
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
                <span class="cell-value cell-number">{{ entry.value }}</span>
              </div>
              <div class="cell">
                <span class="cell-label">Điểm vào</span>
                <span class="cell-value">{{ entry.score ? formatNumber(Number(entry.score) || entry.score) : '-' }}</span>
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
                  <span class="cell-value" :class="resultStatus[entry.id].value > 0 ? 'cell-win' : ''">
                    {{ formatNumber(resultStatus[entry.id].value) }}
                  </span>
                </template>
                <template v-else>
                  <span class="cell-value cell-pending">{{ entry.result ? formatNumber(Number(entry.result) || 0) : 'Chưa có kết quả' }}</span>
                </template>
              </div>
            </div>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>

<style scoped>
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
.result-cells {
  display: flex;
  gap: 20px;
  flex-wrap: wrap;
}
.cell {
  display: flex;
  flex-direction: column;
  gap: 1px;
  min-width: 60px;
}
.cell-label {
  font-size: 14px;
  color: var(--muted);
}
.cell-value {
  font-size: 14px;
  font-weight: 700;
  color: var(--text);
}
.cell-number {
  color: var(--accent-strong);
}
.cell-win {
  color: var(--accent-strong);
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
/* ---- Toolbar: customer select (primary) + checkbox + recalc, one compact row ---- */
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

.filters {
  justify-content: flex-start;
  align-items: flex-end;
  gap: 12px 24px;
  padding: 16px 20px;
  border-radius: 14px;
}
.filter-customer {
  flex: 0 1 320px;
  min-width: 220px;
  margin: 0;
}
.filter-customer label {
  font-size: 14px;
  font-weight: 700;
  color: var(--text-primary);
  margin-bottom: 6px;
}
.filter-customer select {
  height: 44px;
  padding: 0 14px;
  font-size: 15px;
  border-radius: 10px;
  border: 1px solid var(--input-border);
  cursor: pointer;
}
.filter-customer select:hover {
  border-color: var(--input-border-hover);
}
.filter-customer select:focus {
  outline: none;
  border-color: var(--primary);
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--primary) 35%, transparent);
}
.check-field {
  min-height: 44px;
  gap: 10px;
  font-size: 14px;
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

.cell-label {
  font-size: 14px;
}

@media (max-width: 640px) {
  .filters {
    align-items: stretch;
    padding: 16px;
  }
  .filter-customer {
    flex: 1 1 100%;
  }
}
/* ---- Results: compact 2-column item grid ---- */
.customer-group {
  padding: 16px 20px 20px;
  border-radius: 14px;
}
.customer-group-head {
  align-items: baseline;
  margin-bottom: 12px;
  padding-bottom: 12px;
}
.customer-group-head strong {
  font-size: 17px;
}
.customer-group-head .page-subtitle {
  margin: 0;
  font-size: 14px;
}

.result-list {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 12px;
}
.result-row,
.result-row:last-child {
  display: flex;
  flex-direction: column;
  gap: 10px;
  padding: 12px 14px;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 12px;
}
.result-row-top {
  gap: 6px;
  margin: 0;
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
.cell {
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
  overflow-wrap: anywhere;
}
/* Số and Điểm ra carry the weight */
.cell-number,
.result-cells .cell:last-child .cell-value {
  font-size: 20px;
  font-weight: 800;
  line-height: 1.2;
}
.cell-number {
  color: var(--text-primary);
}
.cell-win {
  color: var(--success-text);
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
  }
  .customer-group {
    padding: 16px;
  }
}
</style>
