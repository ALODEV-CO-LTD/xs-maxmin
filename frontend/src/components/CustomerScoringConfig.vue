<!--
  Per-customer scoring config (Khách hàng > Xem chi tiết). Every bet type of the account is listed
  with the values THIS customer is scored by: the account-wide setting unless the customer has
  their own. Each type can be edited, removed for this customer (switched off; it can be restored)
  and the customer can get types of their own ("Thêm loại đánh"). Only what differs from the
  account-wide settings is stored, so the rest keeps following it when the default changes.
  Props: customer { id, name, scoringRates }, accountRates { typeKey: {rate, tiers, digits} },
         digitOptions [1..5]
  Emits: saved(ratesOrNull)   (the customer's new override map, null = none)
  API:   PATCH /me/customers/:id { scoringRates }
-->
<script setup>
import { computed, reactive, ref, watch } from 'vue'
import { api, ApiError } from '../api'
import { betTypeLabel, PRIZE_TIERS } from '../betTypes'
import { pointValueOf, sameConfig, unitOf } from '../scoringConfig'
import AppSelect from './AppSelect.vue'
import AddBetTypeDialog from './AddBetTypeDialog.vue'
import { showConfirm } from '../confirm'

const props = defineProps({
  customer: { type: Object, required: true },
  accountRates: { type: Object, required: true },
  digitOptions: { type: Array, default: () => [1, 2, 3, 4, 5] },
})
const emit = defineEmits(['saved'])

const rows = reactive([]) // { key, rate, digits, tiers, disabled, custom }  custom = only this customer has it
const addOpen = ref(false)
const saving = ref(false)
const error = ref('')
const notice = ref('')

const clone = (c, key = '') => ({ rate: String(c.rate), digits: c.digits || 2, tiers: [...c.tiers], unit: unitOf(key, c), pointValue: String(pointValueOf(c)) })

function build() {
  rows.splice(0)
  const own = props.customer.scoringRates || {}
  const keys = [...new Set([...Object.keys(props.accountRates), ...Object.keys(own)])]
  for (const key of keys) {
    const o = own[key]
    const base = props.accountRates[key]
    rows.push({
      key,
      ...clone(o && !o.disabled ? o : base || { rate: 1, tiers: ['dacBiet'], digits: 2 }, key),
      disabled: !!o?.disabled,
      custom: !base,
    })
  }
  error.value = ''
}
watch(() => [props.customer.id, props.customer.scoringRates, props.accountRates], build, { immediate: true, deep: true })

const cfgOf = (r) => ({ rate: Number(r.rate), tiers: [...r.tiers], digits: Number(r.digits) || 2, unit: r.unit, pointValue: Math.max(0, Number(r.pointValue) || 0) })
const isDefault = (r) => !r.custom && !r.disabled && sameConfig(cfgOf(r), props.accountRates[r.key], r.key)
const overrideCount = computed(() => rows.filter((r) => !isDefault(r)).length)

// What this form would store: only what differs from the account-wide settings.
function toMap() {
  const map = {}
  for (const r of rows) {
    if (r.disabled) {
      if (!r.custom) map[r.key] = { disabled: true } // a type only this customer had is simply gone
      continue
    }
    const cfg = cfgOf(r)
    if (r.custom || !sameConfig(cfg, props.accountRates[r.key], r.key)) map[r.key] = cfg
  }
  return map
}
const dirty = computed(() => JSON.stringify(sortKeys(toMap())) !== JSON.stringify(sortKeys(props.customer.scoringRates || {})))
function sortKeys(o) {
  return Object.fromEntries(
    Object.entries(o).sort(([a], [b]) => a.localeCompare(b)).map(([k, v]) => [k, v.disabled ? v : { rate: Number(v.rate), digits: v.digits, tiers: [...v.tiers].sort(), unit: unitOf(k, v), pv: unitOf(k, v) === 'point' ? pointValueOf(v) : 0 }]),
  )
}

function toggleTier(row, key) {
  const i = row.tiers.indexOf(key)
  if (i === -1) row.tiers.push(key)
  else row.tiers.splice(i, 1)
}
function resetRow(row) {
  const d = props.accountRates[row.key]
  if (d) Object.assign(row, clone(d, row.key), { disabled: false })
}
async function removeRow(row) {
  if (!(await showConfirm({
    title: 'Xoá loại đánh',
    message: `${row.custom ? 'Xoá' : 'Bỏ'} loại "${betTypeLabel(row.key)}" ${row.custom ? 'của' : 'khỏi danh sách của'} ${props.customer.name}? ${row.custom ? '' : 'Loại này vẫn còn cho các khách khác, và bạn có thể khôi phục lại ở đây. '}Số liệu đã nhập với loại này vẫn được giữ và tính theo cấu hình mặc định. Bấm Lưu để áp dụng.`,
    confirmText: row.custom ? 'Xoá' : 'Bỏ',
    danger: true,
  }))) return
  if (row.custom) rows.splice(rows.indexOf(row), 1)
  else row.disabled = true
}
function restoreRow(row) {
  row.disabled = false
}
function onAdd(p) {
  if (rows.some((r) => r.key === p.key)) return
  rows.push({ key: p.key, rate: String(p.rate), digits: p.digits, tiers: [...p.tiers], unit: p.unit, pointValue: String(p.pointValue), disabled: false, custom: true })
  addOpen.value = false
}
function resetAll() {
  for (const r of rows) resetRow(r)
}

async function save() {
  error.value = ''
  notice.value = ''
  for (const r of rows) {
    if (r.disabled) continue
    const n = Number(r.rate)
    if (!Number.isFinite(n) || n <= 0) {
      error.value = `Tỉ lệ của "${betTypeLabel(r.key)}" không hợp lệ`
      return
    }
    if (r.tiers.length === 0) {
      error.value = `"${betTypeLabel(r.key)}" cần chọn ít nhất một giải để đối chiếu`
      return
    }
  }
  const map = toMap()
  saving.value = true
  try {
    const res = await api.patch(`/me/customers/${props.customer.id}`, { scoringRates: Object.keys(map).length ? map : null })
    notice.value = Object.keys(map).length ? `Đã lưu cấu hình riêng cho ${props.customer.name}` : `${props.customer.name} đang dùng cấu hình mặc định`
    emit('saved', res.scoringRates || null)
  } catch (err) {
    error.value = err instanceof ApiError ? (err.status === 0 ? 'Mất kết nối tới máy chủ, chưa lưu được.' : err.message) : 'Không lưu được cấu hình'
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div class="csc">
    <p class="csc-hint">
      Tỉ lệ và giải đối chiếu dùng để tính điểm cho <strong>{{ customer.name }}</strong>. Dòng nào bạn không đổi sẽ theo cấu hình mặc định chung.
    </p>
    <div v-if="error" class="alert alert-error">{{ error }}</div>
    <div v-if="notice" class="alert alert-success">{{ notice }}</div>

    <div class="csc-bar">
      <button type="button" class="btn btn-primary btn-sm" @click="addOpen = true">+ Thêm loại đánh</button>
    </div>

    <div v-for="r in rows" :key="r.key" class="csc-row" :class="{ own: !isDefault(r) && !r.disabled, off: r.disabled }">
      <div class="csc-head">
        <strong>{{ betTypeLabel(r.key) }}</strong> <span class="muted">({{ r.key }})</span>
        <span class="csc-tag" :class="{ own: !isDefault(r) && !r.disabled }">{{ r.disabled ? 'Đã bỏ cho khách này' : r.custom ? 'Chỉ khách này' : isDefault(r) ? 'Mặc định' : 'Riêng' }}</span>
        <span class="csc-head-actions">
          <button v-if="r.disabled" type="button" class="btn btn-ghost btn-sm" @click="restoreRow(r)">Khôi phục</button>
          <button v-else-if="!isDefault(r) && !r.custom" type="button" class="btn btn-ghost btn-sm" @click="resetRow(r)">Theo mặc định</button>
          <button v-if="!r.disabled" type="button" class="btn btn-ghost btn-sm csc-del" @click="removeRow(r)">Xoá</button>
        </span>
      </div>
      <div v-if="!r.disabled" class="csc-fields">
        <label>Tỉ lệ<input v-model="r.rate" type="number" min="1" step="any" /></label>
        <label>So khớp
          <AppSelect v-model.number="r.digits">
            <option v-for="d in digitOptions" :key="d" :value="d">{{ d }} số cuối</option>
          </AppSelect>
        </label>
        <label>Tính theo
          <AppSelect v-model="r.unit">
            <option value="point">Điểm</option>
            <option value="money">Tiền</option>
          </AppSelect>
        </label>
        <label v-if="r.unit === 'point'">1 điểm =<input v-model="r.pointValue" type="number" min="0" step="any" style="width: 84px" /> đ</label>
      </div>
      <div v-if="!r.disabled" class="csc-tiers">
        <label v-for="t in PRIZE_TIERS" :key="t.key" class="csc-tier">
          <input type="checkbox" :checked="r.tiers.includes(t.key)" @change="toggleTier(r, t.key)" /> {{ t.label }}
        </label>
      </div>
    </div>

    <AddBetTypeDialog
      :open="addOpen"
      :existing-keys="rows.map((r) => r.key)"
      :digit-options="digitOptions"
      :tiers="PRIZE_TIERS"
      @close="addOpen = false"
      @add="onAdd"
    />

    <div class="csc-actions">
      <span class="muted">{{ overrideCount ? `${overrideCount} loại có cấu hình riêng` : 'Đang dùng cấu hình mặc định' }}</span>
      <button type="button" class="btn btn-ghost btn-sm" :disabled="saving || !overrideCount" @click="resetAll">Đặt lại tất cả theo mặc định</button>
      <button type="button" class="btn btn-primary btn-sm" :disabled="saving || !dirty" @click="save">{{ saving ? 'Đang lưu...' : 'Lưu cấu hình khách này' }}</button>
    </div>
  </div>
</template>

<style scoped>
.csc-hint {
  margin: 0 0 8px;
  font-size: 12.5px;
  color: var(--muted);
}
.csc-bar {
  display: flex;
  justify-content: flex-end;
  margin-bottom: 6px;
}
/* Compact rows: name + figures on one line, the prize groups right under in small type. */
.csc-row {
  display: grid;
  grid-template-columns: minmax(150px, 1fr) auto;
  gap: 4px 12px;
  align-items: center;
  margin-bottom: 6px;
  padding: 7px 10px;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 8px;
}
.csc-row.own {
  border-color: var(--primary);
}
.csc-row.off {
  opacity: 0.6;
}
.csc-head {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 2px 6px;
  font-size: 14px;
}
.csc-head-actions {
  display: inline-flex;
  gap: 0;
  margin-left: auto;
}
.csc-head-actions .btn {
  min-height: 24px;
  padding: 0 8px;
  font-size: 12.5px;
}
.csc-del {
  color: var(--danger-text);
}
.muted {
  color: var(--muted);
  font-size: 12.5px;
}
.csc-tag {
  padding: 0 7px;
  font-size: 11.5px;
  line-height: 18px;
  color: var(--muted);
  border: 1px solid var(--border);
  border-radius: 999px;
}
.csc-tag.own {
  color: var(--primary);
  border-color: var(--primary);
}
.csc-fields {
  display: flex;
  align-items: center;
  gap: 4px 12px;
}
.csc-fields label {
  display: flex;
  align-items: center;
  gap: 6px;
  white-space: nowrap;
  font-size: 12.5px;
  color: var(--muted);
}
.csc-fields input {
  width: 64px;
  height: 28px;
  padding: 0 6px;
  font: inherit;
  font-size: 13.5px;
  text-align: center;
  color: var(--text-primary);
  background: var(--card);
  border: 1px solid var(--input-border);
  border-radius: 6px;
}
.csc-fields :deep(.app-select),
.csc-fields :deep(select),
.csc-fields :deep(.select-trigger),
.csc-fields :deep(button) {
  min-height: 28px !important;
  height: 28px !important;
  padding-top: 0 !important;
  padding-bottom: 0 !important;
  font-size: 13px !important;
}
.csc-tiers {
  grid-column: 1 / -1;
  display: flex;
  flex-wrap: wrap;
  gap: 2px 12px;
}
.csc-tier {
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 12.5px;
  color: var(--text-primary);
  white-space: nowrap;
}
.csc-tier input {
  width: 13px;
  height: 13px;
  margin: 0;
}
.csc-actions {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: flex-end;
  gap: 6px 8px;
  margin-top: 8px;
}
.csc-actions .muted {
  flex: 1;
}
@media (max-width: 560px) {
  .csc-row {
    grid-template-columns: 1fr;
  }
}
</style>
