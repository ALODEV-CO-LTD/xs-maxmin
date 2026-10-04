<!--
  /scoring-settings - per betting type (đề, lô, and any other type this
  account adds), owned by the logged-in account itself - NOT an admin-only
  setting, since each account (each "đại lý") runs its own customers and
  may use different rules. Two things per type:
    - "Tỉ lệ ăn": payout multiple.
    - "Đối chiếu với": which of the 8 prize groups in a lottery result
      count as a match for this type (e.g. đề traditionally only checks
      "Đặc biệt"; lô checks all of them). Read by ScoringView's auto-calc.
  EntriesView's "Loại đánh" picker just reads the type keys.

  Also configurable per type: how many trailing digits to compare between
  the customer's bet number and each prize-tier number (2 for "đề"/"lô",
  3 for "3 càng", 4 for "bao lô 4", ...) - read by ScoringView's auto-calc,
  which used to always hard-code 2 regardless of type.

  API: GET  /me/scoring-settings -> { rates: {typeKey: {rate, tiers, digits}}, availableTiers, digitRange }
       PUT  /me/scoring-settings body { rates: {typeKey: {rate, tiers, digits}} }
-->
<script setup>
import AppSelect from '../components/AppSelect.vue'
import { ref, watch, onMounted } from 'vue'
import { api, ApiError } from '../api'
import { betTypeLabel, PRIZE_TIERS } from '../betTypes'

const defaultRates = {
  de: { rate: 70, tiers: ['dacBiet'], digits: 2 },
  lo: { rate: 20, tiers: PRIZE_TIERS.map((t) => t.key), digits: 2 },
}

// Fallback if /me/scoring-settings hasn't returned digitRange yet.
const digitRange = ref([1, 5])
const digitOptions = () => {
  const [min, max] = digitRange.value
  const opts = []
  for (let d = min; d <= max; d++) opts.push(d)
  return opts
}

const loading = ref(true)
const error = ref('')
const saved = ref(false)
const saving = ref(false)

const rows = ref([])
const newKey = ref('')
const newRate = ref('')

// Adding a type (or editing a rate/tier) only changes `rows` locally - it
// has NOT reached the backend (and so won't show up on Nhập số/Tính điểm)
// until "Lưu cài đặt" is clicked. This tracks that gap so leaving it
// unsaved is obvious instead of silently losing the change.
const dirty = ref(false)
let savedSnapshot = ''
function markSaved() {
  savedSnapshot = JSON.stringify(rows.value)
  dirty.value = false
}
watch(
  rows,
  () => {
    dirty.value = JSON.stringify(rows.value) !== savedSnapshot
    if (dirty.value) saved.value = false
  },
  { deep: true }
)

function toRows(map) {
  return Object.entries(map).map(([key, cfg]) => ({
    key,
    rate: String(cfg.rate),
    tiers: [...cfg.tiers],
    digits: cfg.digits ?? 2,
  }))
}

async function load() {
  loading.value = true
  error.value = ''
  saved.value = false
  try {
    const { rates, digitRange: range } = await api.get('/me/scoring-settings')
    if (Array.isArray(range) && range.length === 2) digitRange.value = range
    rows.value = toRows(rates && Object.keys(rates).length ? rates : defaultRates)
    markSaved()
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không thể tải cài đặt'
  } finally {
    loading.value = false
  }
}

function addRow() {
  // <input type="number"> makes Vue's v-model hold a Number (or '' when
  // empty), never a string - so this must NOT call .trim() on newRate.
  const key = newKey.value.trim().toLowerCase().replace(/\s+/g, '-')
  const rate = newRate.value
  if (!key || rate === '' || rate === null || !Number.isFinite(Number(rate))) return
  if (rows.value.some((r) => r.key === key)) {
    error.value = `Loại "${key}" đã tồn tại`
    return
  }
  error.value = ''
  // New custom types default to checking every tier - the safer, more
  // inclusive starting point (matches "lô"-style comparison); the user can
  // narrow it down (e.g. to just "Đặc biệt" for a đề-style type).
  rows.value.push({ key, rate: String(rate), tiers: PRIZE_TIERS.map((t) => t.key), digits: 2 })
  newKey.value = ''
  newRate.value = ''
}

function removeRow(key) {
  rows.value = rows.value.filter((r) => r.key !== key)
}

function toggleTier(row, tierKey) {
  const idx = row.tiers.indexOf(tierKey)
  if (idx === -1) row.tiers.push(tierKey)
  else row.tiers.splice(idx, 1)
}

async function save() {
  error.value = ''
  saved.value = false
  if (rows.value.length === 0) {
    error.value = 'Cần ít nhất một loại đánh'
    return
  }
  const map = {}
  for (const r of rows.value) {
    const n = Number(r.rate)
    if (!r.key.trim() || !Number.isFinite(n) || n <= 0) {
      error.value = `Tỉ lệ của "${r.key || '(trống)'}" không hợp lệ`
      return
    }
    if (r.tiers.length === 0) {
      error.value = `"${betTypeLabel(r.key)}" cần chọn ít nhất một giải để đối chiếu`
      return
    }
    map[r.key.trim()] = { rate: n, tiers: r.tiers, digits: Number(r.digits) || 2 }
  }
  saving.value = true
  try {
    const { rates } = await api.put('/me/scoring-settings', { rates: map })
    rows.value = toRows(rates)
    markSaved()
    saved.value = true
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không thể lưu cài đặt'
  } finally {
    saving.value = false
  }
}

function resetDefaultLocally() {
  rows.value = toRows(defaultRates)
}

onMounted(load)
</script>

<template>
  <div class="page">
    <h1 class="page-title">Cấu hình tính điểm</h1>
    <p class="page-subtitle">
      Cho từng loại đánh của riêng tài khoản bạn: tỉ lệ ăn và đối chiếu với những giải nào trong kết quả xổ số. Điểm
      ra = điểm vào × tỉ lệ, mỗi lần số khách đánh khớp 2 số cuối với một số ở các giải đã chọn.
    </p>

    <div v-if="error" class="alert alert-error">{{ error }}</div>
    <div v-if="saved" class="alert alert-success">Đã lưu cài đặt</div>
    <div v-if="!loading && dirty" class="alert alert-warning">
      Bạn có thay đổi chưa lưu. Bấm "Lưu cài đặt" bên dưới để áp dụng ở trang Nhập số/Tính điểm.
    </div>
    <div v-if="loading">Đang tải...</div>

    <template v-else>
      <div class="card table-wrap" style="padding: 0">
        <table class="table type-table stack-table">
          <colgroup>
            <col class="col-type" />
            <col class="col-rate" />
            <col class="col-digits" />
            <col />
            <col class="col-action" />
          </colgroup>
          <thead>
            <tr>
              <th>Loại đánh</th>
              <th>Tỉ lệ ăn</th>
              <th>So khớp</th>
              <th>Đối chiếu với</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in rows" :key="row.key">
              <td class="type-cell" data-label="Loại đánh">{{ betTypeLabel(row.key) }} <span class="page-subtitle">({{ row.key }})</span></td>
              <td data-label="Tỉ lệ ăn">
                <input v-model="row.rate" type="number" min="1" class="rate-input" />
              </td>
              <td data-label="So khớp">
                <AppSelect v-model.number="row.digits" class="digits-select">
                  <option v-for="d in digitOptions()" :key="d" :value="d">{{ d }} số cuối</option>
                </AppSelect>
              </td>
              <td data-label="Đối chiếu với">
                <div class="tier-grid">
                  <label v-for="tier in PRIZE_TIERS" :key="tier.key" class="tier-check">
                    <input
                      type="checkbox"
                      :checked="row.tiers.includes(tier.key)"
                      @change="toggleTier(row, tier.key)"
                    />
                    {{ tier.label }}
                  </label>
                </div>
              </td>
              <td>
                <button type="button" class="btn btn-ghost btn-sm btn-remove" @click="removeRow(row.key)">Xoá</button>
              </td>
            </tr>
            <tr class="new-row">
              <td data-label="Loại đánh"><input v-model="newKey" type="text" placeholder="mã loại mới, vd: xien2" class="new-key-input" /></td>
              <td data-label="Tỉ lệ ăn"><input v-model="newRate" type="number" min="1" placeholder="tỉ lệ" class="rate-input" /></td>
              <td data-label="So khớp" class="page-subtitle">2 số cuối</td>
              <td data-label="Đối chiếu với" class="page-subtitle">Mặc định: đối chiếu tất cả các giải</td>
              <td>
                <button type="button" class="btn btn-secondary btn-sm" @click="addRow">+ Thêm</button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="action-bar">
        <button type="button" class="btn btn-secondary btn-sm" :disabled="saving" @click="resetDefaultLocally">
          Đặt lại mặc định (Đề: Đặc biệt × 70, Lô: tất cả × 20)
        </button>
        <button type="button" class="btn btn-primary" :disabled="saving" @click="save">
          {{ saving ? 'Đang lưu...' : 'Lưu cài đặt' }}
        </button>
      </div>
    </template>
  </div>
</template>

<style scoped>
.table-wrap {
  overflow-x: auto;
}
.type-table td {
  vertical-align: middle;
}
.type-cell {
  white-space: nowrap;
  font-weight: 700;
}
.rate-input {
  width: 64px;
  padding: 5px 6px;
  border: 1.5px solid var(--border);
  border-radius: var(--radius-sm);
  background: var(--bg);
  color: var(--text);
  font-size: 13px;
  text-align: center;
}
.rate-input:focus {
  outline: none;
  border-color: var(--accent);
}
.digits-select {
  padding: 5px 6px;
  border: 1.5px solid var(--border);
  border-radius: var(--radius-sm);
  background: var(--bg);
  color: var(--text);
  font-size: 13px;
  white-space: nowrap;
}
.digits-select:focus {
  outline: none;
  border-color: var(--accent);
}
.tier-grid {
  display: flex;
  flex-wrap: wrap;
  gap: 4px 10px;
  min-width: 260px;
}
.tier-check {
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 12px;
  color: var(--text);
  white-space: nowrap;
}
.tier-check input {
  width: 14px;
  height: 14px;
}
.new-key-input {
  min-width: 140px;
  padding: 6px 10px;
  border: 1.5px solid var(--border);
  border-radius: var(--radius-sm);
  background: var(--bg);
  color: var(--text);
  font-size: 13px;
}
.new-key-input:focus {
  outline: none;
  border-color: var(--accent);
}
/* ---- Table: column widths, readable inputs, clear hierarchy ---- */
.table-wrap {
  border-radius: 14px;
}
.type-table {
  min-width: 940px;
}
.col-type {
  width: 170px;
}
.col-rate {
  width: 120px;
}
.col-digits {
  width: 150px;
}
.col-action {
  width: 120px;
}
.type-table th {
  padding: 12px 16px;
  font-size: 13px;
  background: var(--surface);
  white-space: nowrap;
}
.type-table td {
  padding: 12px 16px;
}
.type-table tbody tr:not(.new-row):hover {
  background: color-mix(in srgb, var(--primary) 6%, transparent);
}
.type-cell {
  font-size: 15px;
}
.type-cell .page-subtitle {
  margin: 0;
  font-size: 13px;
  font-weight: 500;
  color: var(--text-secondary);
}

.rate-input,
.digits-select,
.new-key-input {
  height: 40px;
  padding: 0 12px;
  font-size: 15px;
  border: 1px solid var(--input-border);
  border-radius: 10px;
  background: var(--surface);
}
.rate-input {
  width: 88px;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
}
.digits-select {
  width: 100%;
  cursor: pointer;
}
.new-key-input {
  width: 100%;
  min-width: 140px;
}
.rate-input:hover,
.digits-select:hover,
.new-key-input:hover {
  border-color: var(--input-border-hover);
}
.rate-input:focus,
.digits-select:focus,
.new-key-input:focus {
  outline: none;
  border-color: var(--primary);
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--primary) 35%, transparent);
}

/* "Đối chiếu với": compact wrapping grid of checkboxes */
.tier-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(116px, 1fr));
  gap: 8px 12px;
  min-width: 0;
}
.tier-check {
  gap: 8px;
  min-height: 28px;
  font-size: 14px;
  cursor: pointer;
}
.tier-check input {
  width: 16px;
  height: 16px;
  flex: none;
  accent-color: var(--primary);
}

/* "Thêm mới" row is visually its own band */
.new-row td {
  background: var(--surface);
  border-top: 1px dashed var(--input-border);
}
.new-row .page-subtitle {
  margin: 0;
  font-size: 14px;
  color: var(--text-secondary);
}

/* Buttons: light destructive "Xoá", secondary "+ Thêm" */
.type-table .btn-sm {
  min-height: 36px;
  padding: 0 14px;
  font-size: 14px;
  font-weight: 600;
  border-radius: 10px;
  white-space: nowrap;
}
.btn-remove {
  color: var(--danger-text);
  border-color: transparent;
}
.btn-remove:hover:not(:disabled) {
  background: var(--danger-soft);
}

/* Compact action bar (reset + save), right-aligned under the table */
.action-bar {
  display: flex;
  flex-wrap: wrap;
  justify-content: flex-end;
  align-items: center;
  gap: 8px;
  margin-top: 16px;
}
.action-bar .btn {
  min-height: 40px;
  padding: 0 18px;
  font-size: 14px;
  font-weight: 600;
  border-radius: 10px;
}

@media (max-width: 640px) {
  .action-bar {
    justify-content: stretch;
  }
  .action-bar .btn {
    flex: 1 1 100%;
  }
}

/* The So khớp dropdown is an AppSelect: its wrapper only sets size; the
   trigger inside draws the control, so no frame on the wrapper itself. */
.digits-select,
.digits-select:hover {
  padding: 0;
  border: 0;
  background: transparent;
  border-radius: 0;
  box-shadow: none;
}

@media (max-width: 640px) {
  /* stacked rows: the checkbox grid takes its own full-width block under the label */
  .type-table td:has(.tier-grid) {
    flex-direction: column;
    align-items: stretch;
  }
  .type-table td:has(.tier-grid)::before {
    margin-bottom: 4px;
  }
  .type-table .digits-select,
  .type-table .new-key-input {
    width: 160px;
  }
  .type-table .new-row td {
    border-top: 0;
  }
}
</style>
