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
// `embedded`: shown inside Tính điểm (hides the page title); emits `saved` after every successful save.
defineProps({ embedded: { type: Boolean, default: false } })
const emit = defineEmits(['saved'])
import AppSelect from '../components/AppSelect.vue'
import AppIcon from '../components/AppIcon.vue'
import AddBetTypeDialog from '../components/AddBetTypeDialog.vue'
import { nextTick, ref, watch, onMounted } from 'vue'
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
// "Thêm loại đánh" dialog + the row just added (briefly highlighted)
const addOpen = ref(false)
const justAdded = ref('')
let justAddedTimer = null

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

const addError = ref('')
async function onAdd(payload) {
  // Validation (name, rate, at least one prize group, no duplicate) is done by the dialog.
  if (rows.value.some((r) => r.key === payload.key)) return
  addError.value = ''
  const before = rows.value
  rows.value = [...before, { key: payload.key, rate: String(payload.rate), tiers: payload.tiers, digits: payload.digits }]
  // A new type is saved to the server RIGHT NOW, while the dialog is still open: if that
  // fails the dialog stays open with the reason (the error used to appear at the top of the
  // page, out of sight after scrolling to the new row) and nothing is added locally.
  const ok = await save()
  if (!ok) {
    rows.value = before
    addError.value = error.value || 'Không lưu được loại đánh này'
    error.value = ''
    return
  }
  addOpen.value = false
  justAdded.value = payload.key
  clearTimeout(justAddedTimer)
  justAddedTimer = setTimeout(() => (justAdded.value = ''), 6000)
  await nextTick()
  document.querySelector('tr.row-new')?.scrollIntoView({ block: 'center', behavior: 'smooth' })
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
    return false
  }
  const map = {}
  for (const r of rows.value) {
    const n = Number(r.rate)
    if (!r.key.trim() || !Number.isFinite(n) || n <= 0) {
      error.value = `Tỉ lệ của "${r.key || '(trống)'}" không hợp lệ`
      return false
    }
    if (r.tiers.length === 0) {
      error.value = `"${betTypeLabel(r.key)}" cần chọn ít nhất một giải để đối chiếu`
      return false
    }
    map[r.key.trim()] = { rate: n, tiers: r.tiers, digits: Number(r.digits) || 2 }
  }
  saving.value = true
  try {
    const { rates } = await api.put('/me/scoring-settings', { rates: map })
    rows.value = toRows(rates)
    markSaved()
    saved.value = true
    emit('saved')
    return true
  } catch (err) {
    error.value = err instanceof ApiError ? (err.status === 0 ? 'Mất kết nối tới máy chủ, chưa lưu được. Hãy thử lại.' : err.message) : 'Không thể lưu cài đặt'
    return false
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
  <div :class="embedded ? 'settings-embedded' : 'page'">
    <template v-if="!embedded">
      <h1 class="page-title">Cấu hình tính điểm</h1>
    </template>
    <p class="page-subtitle">
      {{ embedded ? 'Cấu hình mặc định, dùng cho mọi khách chưa có cấu hình riêng. ' : '' }}Cho từng loại đánh của riêng tài khoản bạn: tỉ lệ ăn và đối chiếu với những giải nào trong kết quả xổ số. Điểm
      ra = điểm vào × tỉ lệ, mỗi lần số khách đánh khớp 2 số cuối với một số ở các giải đã chọn.
    </p>

    <div v-if="error" class="alert alert-error">{{ error }}</div>
    <div v-if="saved" class="alert alert-success">Đã lưu cài đặt</div>
    <div v-if="!loading && dirty" class="alert alert-warning">
      Bạn có thay đổi chưa lưu. Bấm "Lưu cài đặt" bên dưới để áp dụng ở trang Nhập số/Tính điểm.
    </div>
    <div v-if="loading">Đang tải...</div>

    <template v-else>
      <div class="types-bar">
        <h2 class="types-title">Các loại đánh <span class="types-count">{{ rows.length }}</span></h2>
        <button type="button" class="btn btn-primary" @click="addError = ''; addOpen = true">+ Thêm loại đánh</button>
      </div>

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
            <tr v-for="row in rows" :key="row.key" :class="{ 'row-new': row.key === justAdded }">
              <td class="type-cell" data-label="Loại đánh">{{ betTypeLabel(row.key) }} <span class="page-subtitle">({{ row.key }})</span><span v-if="row.key === justAdded" class="saved-tag">Đã lưu</span></td>
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
          </tbody>
        </table>
      </div>

      <div class="action-bar">
        <button
          type="button"
          class="btn btn-ghost btn-sm reset-btn"
          :disabled="saving"
          title="Đề: Đặc biệt × 70, Lô: tất cả × 20"
          @click="resetDefaultLocally"
        >
          <AppIcon name="refresh-cw" /> Đặt lại mặc định
        </button>
        <button type="button" class="btn btn-primary" :disabled="saving" @click="save">
          {{ saving ? 'Đang lưu...' : 'Lưu cài đặt' }}
        </button>
      </div>
    </template>

    <AddBetTypeDialog
      :open="addOpen"
      :existing-keys="rows.map((r) => r.key)"
      :digit-options="digitOptions()"
      :tiers="PRIZE_TIERS"
      :busy="saving"
      :save-error="addError"
      @close="addOpen = false; addError = ''"
      @add="onAdd"
    />
  </div>
</template>

<style scoped>
.table-wrap {
  overflow-x: auto;
}
.type-table td {
  vertical-align: middle;
}
.saved-tag {
  margin-left: 8px;
  padding: 1px 8px;
  font-size: 12px;
  font-weight: 600;
  color: var(--success-text);
  border: 1px solid var(--border);
  border-radius: 999px;
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
  font-size: 14px;
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
  font-size: 14px;
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
  font-size: 14px;
  color: var(--text);
  white-space: nowrap;
}
.tier-check input {
  width: 14px;
  height: 14px;
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
  font-size: 14px;
  background: var(--surface);
  white-space: nowrap;
}
.type-table td {
  padding: 12px 16px;
}
.type-table tbody tr:hover {
  background: color-mix(in srgb, var(--primary) 6%, transparent);
}
.type-cell {
  font-size: 15px;
}
.type-cell .page-subtitle {
  margin: 0;
  font-size: 14px;
  font-weight: 500;
  color: var(--text-secondary);
}

.rate-input,
.digits-select {
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
.rate-input:hover,
.digits-select:hover {
  border-color: var(--input-border-hover);
}
.rate-input:focus,
.digits-select:focus {
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

/* Buttons: light destructive "Xoá" */
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
.reset-btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  margin-right: auto;
  color: var(--text-secondary);
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
  .type-table .digits-select {
    width: 160px;
  }
}

/* Section header above the table: title on the left, the single "Thêm loại đánh" button on the right */
.types-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin: 4px 0 12px;
}
.types-title {
  margin: 0;
  font-size: 16px;
}
.types-count {
  display: inline-block;
  min-width: 22px;
  margin-left: 6px;
  padding: 1px 8px;
  font-size: 12px;
  font-weight: 700;
  text-align: center;
  color: var(--text-secondary);
  background: var(--surface);
  border: 1px solid var(--input-border);
  border-radius: 999px;
}
.types-bar .btn {
  min-height: 40px;
  padding: 0 16px;
  font-size: 14px;
  font-weight: 600;
  border-radius: 10px;
}
/* the row that was just added flashes so it is easy to find in a long table */
.type-table tbody tr.row-new td {
  background: color-mix(in srgb, var(--primary) 14%, transparent);
  transition: background 0.4s;
}
@media (max-width: 480px) {
  .types-bar .btn {
    padding: 0 12px;
  }
}
</style>
