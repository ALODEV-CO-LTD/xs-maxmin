<!--
  Cấu hình tính điểm, one editor for both places:
    scope="default"   the account-wide settings (Khách hàng > nút Cấu hình tính điểm mặc định)
                      GET/PUT /me/scoring-settings
    scope="customer"  one customer's own settings (Khách hàng > Xem chi tiết); props: customer, accountRates
                      PATCH /me/customers/:id { scoringRates }
  Rates differ by REGION (Miền Bắc 27 numbers a day, Miền Nam / Miền Trung 18 with a prize eight), so the editor has a tab
  per region. Stored in one map: `type` = every region, `type@mb|mt|mn` = that region only (wins over `type`). A row you
  do not change keeps following the general value; changing it in a region tab makes it a region-only value.
  Each bet type has: tỉ lệ ăn, số cuối so khớp, giải đối chiếu, cách tính tiền (điểm × giá 1 điểm, hoặc theo tiền).
  Customer scope additionally: a type can be removed for that customer in that region (it can be restored), and the
  customer can have types of their own.
  Emits: saved(map)
-->
<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { api, ApiError } from '../api'
import { showConfirm } from '../confirm'
import { betTypeLabel, PRIZE_TIERS } from '../betTypes'
import { baseKey, DEFAULT_RATES, isRegionalKey, pointValueOf, regionKey, sameConfig, typesIn, unitOf } from '../scoringConfig'
import { REGION_IDS } from '../lotteryStations'
import AppSelect from './AppSelect.vue'
import AddBetTypeDialog from './AddBetTypeDialog.vue'

const props = defineProps({
  scope: { type: String, default: 'default' }, // 'default' | 'customer'
  customer: { type: Object, default: null }, // { id, name, scoringRates } (customer scope)
  accountRates: { type: Object, default: () => ({}) }, // the account-wide map (customer scope: the fallback)
})
const emit = defineEmits(['saved'])

const isCustomer = computed(() => props.scope === 'customer')
const REGION_NAMES = { mb: 'Miền Bắc', mt: 'Miền Trung', mn: 'Miền Nam' }
const region = ref('mb')
const loading = ref(true)
const saving = ref(false)
const error = ref('')
const notice = ref('')
const addOpen = ref(false)
const digitOptions = [1, 2, 3, 4, 5]

// The map being edited: the account-wide one (default scope) or this customer's overrides (customer scope).
const work = reactive({})
let initial = ''
// Customer scope: the account-wide map (the fallback), always the current one. Default scope: unused.
const base = computed(() => (isCustomer.value ? props.accountRates : DEFAULT_RATES))

const clone = (c) => ({ rate: c.rate, tiers: [...c.tiers], digits: c.digits || 2, ...(c.unit ? { unit: c.unit } : {}), ...(c.pointValue != null ? { pointValue: c.pointValue } : {}) })
// `setInitial` false = just replace what is on screen (reset): the saved state stays the baseline for "changed?".
function load(map, setInitial = true) {
  for (const k of Object.keys(work)) delete work[k]
  for (const [k, v] of Object.entries(map || {})) work[k] = v.disabled ? { disabled: true } : clone(v)
  if (setInitial) initial = JSON.stringify(sorted(work))
}
const sorted = (o) => Object.fromEntries(Object.entries(o).sort(([a], [b]) => a.localeCompare(b)).map(([k, v]) => [k, v.disabled ? v : { ...v, tiers: [...v.tiers].sort() }]))

async function init() {
  loading.value = true
  error.value = ''
  try {
    if (isCustomer.value) {
      load(props.customer?.scoringRates || {})
    } else {
      const { rates } = await api.get('/me/scoring-settings')
      load(rates && Object.keys(rates).length ? rates : DEFAULT_RATES)
    }
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không tải được cấu hình'
  } finally {
    loading.value = false
    buildRows()
  }
}
onMounted(init)
watch(() => props.customer?.id, init)
watch(() => props.accountRates, () => !loading.value && buildRows())

// ---- rows of the active region ---------------------------------------------------------------------------------------
const rows = reactive([]) // { type, rate, digits, tiers, unit, pointValue, off, custom }

// What applies to (type, region) when NO region-only value is stored: used as the baseline a row is compared with.
function inherited(type) {
  if (!isCustomer.value) return work[type]
  const own = work[type]
  if (own && !own.disabled) return own
  return base.value[regionKey(type, region.value)] ?? base.value[type]
}
function stored(type) {
  const regional = work[regionKey(type, region.value)]
  return regional && !regional.disabled ? regional : inherited(type) // a `disabled` marker carries no values
}

// A type made for this region only (no value that applies to every region).
const isRegionType = (type) => !work[type] && !(isCustomer.value && base.value[type])
// Where a row's value is written when it has nothing to inherit from.
const writeKey = (r) => (r.regionType ? regionKey(r.type, region.value) : r.type)

const typeKeys = computed(() => {
  const keys = new Set(typesIn(work, region.value))
  if (isCustomer.value) for (const k of typesIn(base.value, region.value)) keys.add(k)
  // generic `type@region` keys of types that no longer exist are ignored
  return [...keys]
})

function buildRows() {
  rows.splice(0)
  for (const type of typeKeys.value) {
    const offHere = isCustomer.value && (work[type]?.disabled || work[regionKey(type, region.value)]?.disabled)
    const cfg = stored(type) || DEFAULT_RATES.de
    rows.push({
      type,
      rate: String(cfg.rate),
      digits: cfg.digits || 2,
      tiers: [...cfg.tiers],
      unit: unitOf(type, cfg),
      pointValue: String(pointValueOf(cfg)),
      off: !!offHere,
      custom: isCustomer.value && !base.value[type] && !base.value[regionKey(type, region.value)],
      regionType: isRegionType(type),
    })
  }
}

const cfgOf = (r) => ({
  rate: Number(r.rate),
  tiers: [...r.tiers],
  digits: Number(r.digits) || 2,
  unit: r.unit,
  pointValue: Math.max(0, Number(r.pointValue) || 0),
})

// Writes the rows of the active region back into `work`: a row that differs from what it would inherit becomes a
// region-only value, one that equals it drops its region-only value.
function commitRows() {
  for (const r of rows) {
    if (r.off) continue
    const key = regionKey(r.type, region.value)
    const cfg = cfgOf(r)
    const baseCfg = inherited(r.type)
    if (!baseCfg) {
      work[writeKey(r)] = cfg // a type without a general value gets one (region-only types keep theirs in their region)
    } else if (sameConfig(cfg, baseCfg, r.type)) {
      delete work[key]
    } else {
      work[key] = cfg
    }
  }
}

function switchRegion(id) {
  const problem = validate()
  if (problem) {
    error.value = problem
    return
  }
  error.value = ''
  commitRows()
  region.value = id
  buildRows()
}

// A row counts as region-only as soon as it differs from what it would inherit (live, before saving) or already is.
const differs = (r) => {
  const baseCfg = inherited(r.type)
  return !!baseCfg && !sameConfig(cfgOf(r), baseCfg, r.type)
}
const tag = (r) => {
  if (r.off) return 'Đã bỏ'
  if (r.regionType) return isCustomer.value ? 'Riêng khách · chỉ miền này' : 'Chỉ miền này'
  if (isRegionOnly(r)) return isCustomer.value ? 'Riêng khách · miền này' : 'Riêng miền này'
  if (isCustomer.value) {
    if (work[r.type] && !work[r.type].disabled) return r.custom ? 'Chỉ khách này' : 'Riêng khách'
    return base.value[regionKey(r.type, region.value)] ? 'Mặc định (riêng miền)' : 'Mặc định'
  }
  return 'Chung các miền'
}
const isRegionOnly = (r) => !r.off && !r.regionType && (!!work[regionKey(r.type, region.value)] || differs(r))
const isInherited = (r) => !r.off && !isRegionOnly(r)

function resetRow(r) {
  delete work[regionKey(r.type, region.value)]
  buildRows()
}
function toggleTier(r, key) {
  const i = r.tiers.indexOf(key)
  if (i === -1) r.tiers.push(key)
  else r.tiers.splice(i, 1)
}

async function removeRow(r) {
  if (r.regionType) {
    const okRegion = await showConfirm({
      title: 'Xoá loại đánh',
      message: `Xoá loại "${betTypeLabel(r.type)}" của ${REGION_NAMES[region.value]}${isCustomer.value ? ` (${props.customer.name})` : ''}? Số liệu đã nhập với loại này vẫn được giữ và tính theo cấu hình mặc định. Bấm Lưu để áp dụng.`,
      confirmText: 'Xoá',
      danger: true,
    })
    if (!okRegion) return
    commitRows()
    delete work[regionKey(r.type, region.value)]
    buildRows()
    return
  }
  const every = !isCustomer.value || r.custom
  const ok = await showConfirm({
    title: 'Xoá loại đánh',
    message: every
      ? `Xoá loại "${betTypeLabel(r.type)}"${isCustomer.value ? ` của ${props.customer.name}` : ' khỏi mọi miền'}? Số liệu đã nhập với loại này vẫn được giữ và tính theo cấu hình mặc định. Bấm Lưu để áp dụng.`
      : `Bỏ loại "${betTypeLabel(r.type)}" của ${props.customer.name} ở ${REGION_NAMES[region.value]}? Các miền khác và các khách khác vẫn giữ; bạn có thể khôi phục lại ở đây. Bấm Lưu để áp dụng.`,
    confirmText: every ? 'Xoá' : 'Bỏ',
    danger: true,
  })
  if (!ok) return
  commitRows()
  if (every) {
    for (const k of Object.keys(work)) if (baseKey(k) === r.type) delete work[k]
  } else {
    work[regionKey(r.type, region.value)] = { disabled: true }
  }
  buildRows()
}
function restoreRow(r) {
  commitRows()
  if (work[r.type]?.disabled) delete work[r.type]
  delete work[regionKey(r.type, region.value)]
  buildRows()
}

function onAdd(p) {
  commitRows()
  if (typeKeys.value.includes(p.key)) return
  work[regionKey(p.key, region.value)] = { rate: p.rate, tiers: [...p.tiers], digits: p.digits, unit: p.unit, pointValue: p.pointValue }
  addOpen.value = false
  buildRows()
}

// ---- save --------------------------------------------------------------------------------------------------------------
function validate() {
  for (const r of rows) {
    if (r.off) continue
    const n = Number(r.rate)
    if (!Number.isFinite(n) || n <= 0) return `Tỉ lệ của "${betTypeLabel(r.type)}" không hợp lệ`
    if (r.tiers.length === 0) return `"${betTypeLabel(r.type)}" cần chọn ít nhất một giải để đối chiếu`
  }
  return ''
}

const dirty = computed(() => {
  // include the rows currently on screen
  const copy = JSON.parse(JSON.stringify(work))
  for (const r of rows) {
    if (r.off) continue
    const key = regionKey(r.type, region.value)
    const cfg = cfgOf(r)
    const baseCfg = inherited(r.type)
    if (!baseCfg) copy[writeKey(r)] = cfg
    else if (sameConfig(cfg, baseCfg, r.type)) delete copy[key]
    else copy[key] = cfg
  }
  return JSON.stringify(sorted(copy)) !== initial
})

async function save() {
  error.value = ''
  notice.value = ''
  const problem = validate()
  if (problem) {
    error.value = problem
    return
  }
  commitRows()
  const map = JSON.parse(JSON.stringify(work))
  if (!isCustomer.value && !Object.keys(map).length) {
    error.value = 'Cần ít nhất một loại đánh'
    return
  }
  saving.value = true
  try {
    if (isCustomer.value) {
      const res = await api.patch(`/me/customers/${props.customer.id}`, { scoringRates: Object.keys(map).length ? map : null })
      load(res.scoringRates || {})
      notice.value = res.scoringRates ? `Đã lưu cấu hình riêng cho ${props.customer.name}` : `${props.customer.name} đang dùng cấu hình mặc định`
      emit('saved', res.scoringRates || null)
    } else {
      const res = await api.put('/me/scoring-settings', { rates: map })
      load(res.rates)
      notice.value = 'Đã lưu cấu hình mặc định'
      emit('saved', res.rates)
    }
    buildRows()
  } catch (err) {
    error.value = err instanceof ApiError ? (err.status === 0 ? 'Mất kết nối tới máy chủ, chưa lưu được.' : err.message) : 'Không lưu được cấu hình'
  } finally {
    saving.value = false
  }
}

function resetAll() {
  if (isCustomer.value) load({}, false)
  else load(DEFAULT_RATES, false)
  buildRows()
}

const overrideCount = computed(() => Object.keys(work).filter((k) => isRegionalKey(k) || work[k]?.disabled || (isCustomer.value && !base.value[k])).length)
const regionHasOverride = (id) => Object.keys(work).some((k) => k.endsWith(`@${id}`))
const regions = REGION_IDS

</script>

<template>
  <div class="sce">
    <div v-if="loading" class="sce-note">Đang tải...</div>
    <template v-else>
      <p class="sce-hint">
        <template v-if="isCustomer">Cấu hình dùng để tính điểm cho <strong>{{ customer.name }}</strong>. Dòng nào không đổi sẽ theo cấu hình mặc định.</template>
        <template v-else>Cấu hình mặc định dùng cho mọi khách chưa có cấu hình riêng.</template>
        Mỗi miền có thể có tỉ lệ khác nhau: chọn miền rồi sửa. Loại đánh thêm ở tab nào chỉ dùng cho miền đó.
      </p>

      <div v-if="error" class="alert alert-error">{{ error }}</div>
      <div v-if="notice" class="alert alert-success">{{ notice }}</div>

      <div class="sce-bar">
        <div class="sce-tabs" role="tablist" aria-label="Miền">
          <button
            v-for="id in regions"
            :key="id"
            type="button"
            role="tab"
            class="sce-tab"
            :class="{ on: region === id }"
            :aria-selected="region === id"
            @click="switchRegion(id)"
          >
            {{ REGION_NAMES[id] }}<span v-if="regionHasOverride(id)" class="sce-dot" title="Có cấu hình riêng cho miền này"></span>
          </button>
        </div>
        <button type="button" class="btn btn-primary btn-sm" :title="`Thêm loại đánh chỉ dùng cho ${REGION_NAMES[region]}`" @click="addOpen = true">+ Thêm loại đánh ({{ REGION_NAMES[region] }})</button>
      </div>

      <div class="sce-list">
      <div v-for="r in rows" :key="r.type" class="sce-row" :class="{ own: isRegionOnly(r), off: r.off }">
        <div class="sce-head">
          <strong>{{ betTypeLabel(r.type) }}</strong> <span class="sce-muted">({{ r.type }})</span>
          <span class="sce-tag" :class="{ own: isRegionOnly(r) }">{{ tag(r) }}</span>
          <span class="sce-actions">
            <button v-if="r.off" type="button" class="btn btn-ghost btn-sm" @click="restoreRow(r)">Khôi phục</button>
            <button v-if="isRegionOnly(r)" type="button" class="btn btn-ghost btn-sm" @click="resetRow(r)">Theo chung</button>
            <button v-if="!r.off" type="button" class="btn btn-ghost btn-sm sce-del" @click="removeRow(r)">Xoá</button>
          </span>
        </div>
        <div v-if="!r.off" class="sce-fields">
          <label>Tỉ lệ ăn<input v-model="r.rate" type="number" min="0" step="any" /></label>
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
          <!-- the slot stays (hidden) when the type is paid in money, so the row never changes height -->
          <label class="sce-pv" :class="{ ghost: r.unit !== 'point' }">1 điểm =<input v-model="r.pointValue" type="number" min="0" step="any" class="wide" :tabindex="r.unit === 'point' ? 0 : -1" /> đ</label>
        </div>
        <div v-if="!r.off" class="sce-tiers">
          <label v-for="t in PRIZE_TIERS" :key="t.key" class="sce-tier" :class="{ ghost: t.key === 'giaiTam' && region === 'mb' }">
            <input type="checkbox" :checked="r.tiers.includes(t.key)" :tabindex="t.key === 'giaiTam' && region === 'mb' ? -1 : 0" @change="toggleTier(r, t.key)" /> <span>{{ t.key === 'giaiTam' ? 'Giải tám' : t.label }}</span>
          </label>
        </div>
      </div>
      </div>

      <div class="sce-foot">
        <span class="sce-muted">{{ overrideCount ? `${overrideCount} mục riêng` : isCustomer ? 'Đang dùng cấu hình mặc định' : 'Chưa có cấu hình riêng theo miền' }}</span>
        <button type="button" class="btn btn-ghost btn-sm" :disabled="saving" @click="resetAll">{{ isCustomer ? 'Bỏ cấu hình riêng' : 'Đặt lại mặc định' }}</button>
        <button type="button" class="btn btn-primary" :disabled="saving || !dirty" @click="save">{{ saving ? 'Đang lưu...' : isCustomer ? 'Lưu cấu hình khách này' : 'Lưu cấu hình' }}</button>
      </div>
    </template>

    <AddBetTypeDialog
      :open="addOpen"
      :existing-keys="typeKeys"
      :digit-options="digitOptions"
      :tiers="PRIZE_TIERS"
      @close="addOpen = false"
      @add="onAdd"
    />
  </div>
</template>

<style scoped>
/* Sizes are generous and FIXED: every row has the same slots (price per point and the eighth prize are hidden, not
   removed) and the list has a fixed height that scrolls, so switching region never makes the window jump. */
.sce {
  font-size: 14.5px;
}
.sce-hint {
  margin: 0 0 12px;
  font-size: 14px;
  color: var(--muted);
}
.sce-note {
  color: var(--muted);
}
.sce-bar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  margin-bottom: 12px;
}
.sce-tabs {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}
.sce-tab {
  min-height: 38px;
  min-width: 110px;
  padding: 0 16px;
  font: inherit;
  font-size: 14.5px;
  font-weight: 600;
  color: var(--muted);
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 999px;
  cursor: pointer;
}
.sce-tab.on {
  color: #fff;
  background: var(--primary);
  border-color: var(--primary);
}
.sce-dot {
  display: inline-block;
  width: 8px;
  height: 8px;
  margin-left: 7px;
  vertical-align: middle;
  background: currentColor;
  border-radius: 50%;
  opacity: 0.8;
}
.sce-list {
  height: clamp(270px, 34vh, 340px);
  overflow-y: auto;
  padding-right: 4px;
  scrollbar-gutter: stable;
}
.sce-row {
  display: grid;
  grid-template-columns: 1fr;
  gap: 8px;
  margin-bottom: 8px;
  padding: 10px 14px;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 12px;
}
.sce-row.own {
  border-color: var(--primary);
}
.sce-row.off {
  opacity: 0.6;
}
.sce-head {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 4px 10px;
  min-height: 30px;
  font-size: 16px;
}
.sce-actions {
  display: inline-flex;
  gap: 4px;
  margin-left: auto;
}
.sce-actions .btn {
  min-height: 34px;
  padding: 0 14px;
  font-size: 14.5px;
}
.sce-del {
  color: var(--danger-text);
}
.sce-muted {
  font-size: 14px;
  color: var(--muted);
}
.sce-tag {
  padding: 1px 10px;
  font-size: 13px;
  line-height: 20px;
  color: var(--muted);
  border: 1px solid var(--border);
  border-radius: 999px;
}
.sce-tag.own {
  color: var(--primary);
  border-color: var(--primary);
}
.sce-fields {
  display: grid;
  grid-template-columns: auto auto auto 1fr;
  align-items: center;
  gap: 6px 18px;
  min-height: 40px;
}
.sce-fields label {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 14.5px;
  color: var(--muted);
  white-space: nowrap;
}
.sce-fields input {
  width: 92px;
  height: 38px;
  padding: 0 8px;
  font: inherit;
  font-size: 15px;
  text-align: center;
  color: var(--text-primary);
  background: var(--card);
  border: 1px solid var(--input-border);
  border-radius: 10px;
}
.sce-fields input.wide {
  width: 120px;
}
.sce-fields :deep(select),
.sce-fields :deep(.app-select-trigger),
.sce-fields :deep(button) {
  min-height: 38px;
  font-size: 14.5px;
}
.ghost {
  visibility: hidden;
}
.sce-tiers {
  display: grid;
  grid-template-columns: repeat(9, minmax(0, 1fr));
  gap: 6px 8px;
  min-height: 28px;
}
.sce-tier {
  display: flex;
  align-items: center;
  gap: 6px;
  min-height: 28px;
  font-size: 14px;
  color: var(--text-primary);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.sce-tier input {
  width: 18px;
  height: 18px;
  margin: 0;
}
.sce-foot {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: flex-end;
  gap: 8px 12px;
  margin-top: 12px;
}
.sce-foot .btn {
  min-height: 44px;
  font-size: 15px;
}
.sce-foot .sce-muted {
  flex: 1;
}
@media (max-width: 760px) {
  .sce-fields {
    grid-template-columns: 1fr 1fr;
  }
  .sce-tiers {
    grid-template-columns: repeat(3, minmax(0, 1fr));
    min-height: 90px;
  }
  .sce-list {
    height: clamp(280px, 44vh, 440px);
  }
}
</style>
