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
import { baseKey, DEFAULT_RATES, isRegionalKey, pointValueOf, regionKey, sameConfig, typesOf, unitOf } from '../scoringConfig'
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

const typeKeys = computed(() => {
  const keys = new Set(typesOf(work))
  if (isCustomer.value) for (const k of typesOf(base.value)) keys.add(k)
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
      custom: isCustomer.value && !base.value[type],
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
      work[r.type] = cfg // a type without a general value gets one
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
  if (isRegionOnly(r)) return isCustomer.value ? 'Riêng khách · miền này' : 'Riêng miền này'
  if (isCustomer.value) {
    if (work[r.type] && !work[r.type].disabled) return r.custom ? 'Chỉ khách này' : 'Riêng khách'
    return base.value[regionKey(r.type, region.value)] ? 'Mặc định (riêng miền)' : 'Mặc định'
  }
  return 'Chung các miền'
}
const isRegionOnly = (r) => !r.off && (!!work[regionKey(r.type, region.value)] || differs(r))
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
const tierChoices = computed(() => PRIZE_TIERS.filter((t) => t.key !== 'giaiTam' || region.value !== 'mb'))

async function removeRow(r) {
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
  if (Object.keys(work).some((k) => baseKey(k) === p.key)) return
  work[p.key] = { rate: p.rate, tiers: [...p.tiers], digits: p.digits, unit: p.unit, pointValue: p.pointValue }
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
    if (!baseCfg) copy[r.type] = cfg
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
  if (!isCustomer.value && !typesOf(map).length) {
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
        Mỗi miền có thể có tỉ lệ khác nhau: chọn miền rồi sửa. Dòng không đổi sẽ theo giá trị chung của các miền.
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
        <button type="button" class="btn btn-primary btn-sm" @click="addOpen = true">+ Thêm loại đánh</button>
      </div>

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
          <label v-if="r.unit === 'point'">1 điểm =<input v-model="r.pointValue" type="number" min="0" step="any" class="wide" /> đ</label>
        </div>
        <div v-if="!r.off" class="sce-tiers">
          <label v-for="t in tierChoices" :key="t.key" class="sce-tier">
            <input type="checkbox" :checked="r.tiers.includes(t.key)" @change="toggleTier(r, t.key)" /> {{ t.label }}
          </label>
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
.sce-hint {
  margin: 0 0 10px;
  font-size: 13px;
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
  margin-bottom: 10px;
}
.sce-tabs {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}
.sce-tab {
  position: relative;
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
.sce-tab.on {
  color: #fff;
  background: var(--primary);
  border-color: var(--primary);
}
.sce-dot {
  display: inline-block;
  width: 7px;
  height: 7px;
  margin-left: 6px;
  vertical-align: middle;
  background: currentColor;
  border-radius: 50%;
  opacity: 0.8;
}
.sce-row {
  display: grid;
  grid-template-columns: minmax(180px, 1fr) auto;
  gap: 4px 14px;
  align-items: center;
  margin-bottom: 8px;
  padding: 9px 12px;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 10px;
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
  gap: 2px 8px;
  font-size: 15px;
}
.sce-actions {
  display: inline-flex;
  margin-left: auto;
}
.sce-actions .btn {
  min-height: 26px;
  padding: 0 9px;
  font-size: 13px;
}
.sce-del {
  color: var(--danger-text);
}
.sce-muted {
  font-size: 13px;
  color: var(--muted);
}
.sce-tag {
  padding: 0 8px;
  font-size: 12px;
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
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 4px 14px;
}
.sce-fields label {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 13px;
  color: var(--muted);
  white-space: nowrap;
}
.sce-fields input {
  width: 70px;
  height: 32px;
  padding: 0 8px;
  font: inherit;
  font-size: 14px;
  text-align: center;
  color: var(--text-primary);
  background: var(--card);
  border: 1px solid var(--input-border);
  border-radius: 8px;
}
.sce-fields input.wide {
  width: 96px;
}
.sce-tiers {
  grid-column: 1 / -1;
  display: flex;
  flex-wrap: wrap;
  gap: 4px 14px;
}
.sce-tier {
  display: flex;
  align-items: center;
  gap: 5px;
  font-size: 13.5px;
  color: var(--text-primary);
  white-space: nowrap;
}
.sce-foot {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: flex-end;
  gap: 8px 10px;
  margin-top: 10px;
}
.sce-foot .sce-muted {
  flex: 1;
}
@media (max-width: 600px) {
  .sce-row {
    grid-template-columns: 1fr;
  }
}
</style>
