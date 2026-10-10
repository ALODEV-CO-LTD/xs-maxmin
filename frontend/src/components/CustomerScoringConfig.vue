<!--
  Per-customer scoring config (shown inside Tính điểm). Every bet type of the account is listed
  with the values THIS customer is scored by: the account-wide setting unless the customer has
  their own. Only the rows that differ from the account-wide setting are stored, so the others
  keep following it when the default changes.
  Props: customer { id, name, scoringRates }, accountRates { typeKey: {rate, tiers, digits} },
         digitOptions [1..5]
  Emits: saved(ratesOrNull)   (the customer's new override map, null = none)
  API:   PATCH /me/customers/:id { scoringRates }
-->
<script setup>
import { computed, reactive, ref, watch } from 'vue'
import { api, ApiError } from '../api'
import { betTypeLabel, PRIZE_TIERS } from '../betTypes'
import { sameConfig } from '../scoringConfig'
import AppSelect from './AppSelect.vue'

const props = defineProps({
  customer: { type: Object, required: true },
  accountRates: { type: Object, required: true },
  digitOptions: { type: Array, default: () => [1, 2, 3, 4, 5] },
})
const emit = defineEmits(['saved'])

const rows = reactive([]) // { key, rate, digits, tiers }
const saving = ref(false)
const error = ref('')
const notice = ref('')

const clone = (c) => ({ rate: String(c.rate), digits: c.digits || 2, tiers: [...c.tiers] })

function build() {
  rows.splice(0)
  const own = props.customer.scoringRates || {}
  const keys = [...new Set([...Object.keys(props.accountRates), ...Object.keys(own)])]
  for (const key of keys) rows.push({ key, ...clone(own[key] || props.accountRates[key]) })
  error.value = ''
}
watch(() => [props.customer.id, props.customer.scoringRates, props.accountRates], build, { immediate: true, deep: true })

const isDefault = (r) => !!props.accountRates[r.key] && sameConfig({ ...r, rate: Number(r.rate) }, props.accountRates[r.key])
const overrideCount = computed(() => rows.filter((r) => !isDefault(r)).length)
const dirty = computed(() => {
  const own = props.customer.scoringRates || {}
  return rows.some((r) => {
    const stored = own[r.key] || props.accountRates[r.key]
    return !stored || !sameConfig({ ...r, rate: Number(r.rate) }, stored)
  })
})

function toggleTier(row, key) {
  const i = row.tiers.indexOf(key)
  if (i === -1) row.tiers.push(key)
  else row.tiers.splice(i, 1)
}
function resetRow(row) {
  const d = props.accountRates[row.key]
  if (d) Object.assign(row, clone(d))
}
function resetAll() {
  for (const r of rows) resetRow(r)
}

async function save() {
  error.value = ''
  notice.value = ''
  const map = {}
  for (const r of rows) {
    const n = Number(r.rate)
    if (!Number.isFinite(n) || n <= 0) {
      error.value = `Tỉ lệ của "${betTypeLabel(r.key)}" không hợp lệ`
      return
    }
    if (r.tiers.length === 0) {
      error.value = `"${betTypeLabel(r.key)}" cần chọn ít nhất một giải để đối chiếu`
      return
    }
    const cfg = { rate: n, tiers: [...r.tiers], digits: Number(r.digits) || 2 }
    if (!sameConfig(cfg, props.accountRates[r.key])) map[r.key] = cfg
  }
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

    <div v-for="r in rows" :key="r.key" class="csc-row" :class="{ own: !isDefault(r) }">
      <div class="csc-head">
        <strong>{{ betTypeLabel(r.key) }}</strong> <span class="muted">({{ r.key }})</span>
        <span class="csc-tag" :class="{ own: !isDefault(r) }">{{ isDefault(r) ? 'Mặc định' : 'Riêng' }}</span>
        <button v-if="!isDefault(r) && accountRates[r.key]" type="button" class="btn btn-ghost btn-sm" @click="resetRow(r)">Theo mặc định</button>
      </div>
      <div class="csc-fields">
        <label>Tỉ lệ ăn<input v-model="r.rate" type="number" min="1" step="any" /></label>
        <label>So khớp
          <AppSelect v-model.number="r.digits">
            <option v-for="d in digitOptions" :key="d" :value="d">{{ d }} số cuối</option>
          </AppSelect>
        </label>
      </div>
      <div class="csc-tiers">
        <label v-for="t in PRIZE_TIERS" :key="t.key" class="csc-tier">
          <input type="checkbox" :checked="r.tiers.includes(t.key)" @change="toggleTier(r, t.key)" /> {{ t.label }}
        </label>
      </div>
    </div>

    <div class="csc-actions">
      <span class="muted">{{ overrideCount ? `${overrideCount} loại có cấu hình riêng` : 'Đang dùng cấu hình mặc định' }}</span>
      <button type="button" class="btn btn-ghost btn-sm" :disabled="saving || !overrideCount" @click="resetAll">Đặt lại tất cả theo mặc định</button>
      <button type="button" class="btn btn-primary btn-sm" :disabled="saving || !dirty" @click="save">{{ saving ? 'Đang lưu...' : 'Lưu cấu hình khách này' }}</button>
    </div>
  </div>
</template>

<style scoped>
.csc-hint {
  margin: 0 0 10px;
  font-size: 13px;
  color: var(--muted);
}
.csc-row {
  margin-bottom: 10px;
  padding: 10px 12px;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 10px;
}
.csc-row.own {
  border-color: var(--primary);
}
.csc-head {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 6px 8px;
  margin-bottom: 8px;
}
.muted {
  color: var(--muted);
  font-size: 13px;
}
.csc-tag {
  padding: 1px 8px;
  font-size: 12px;
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
  flex-wrap: wrap;
  gap: 10px 16px;
  margin-bottom: 8px;
}
.csc-fields label {
  display: flex;
  flex-direction: column;
  gap: 3px;
  font-size: 13px;
  color: var(--muted);
}
.csc-fields input {
  width: 90px;
  height: 36px;
  padding: 0 8px;
  font: inherit;
  text-align: center;
  color: var(--text-primary);
  background: var(--card);
  border: 1px solid var(--input-border);
  border-radius: 8px;
}
.csc-tiers {
  display: flex;
  flex-wrap: wrap;
  gap: 4px 12px;
}
.csc-tier {
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 13px;
  color: var(--text-primary);
  white-space: nowrap;
}
.csc-actions {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: flex-end;
  gap: 8px;
}
.csc-actions .muted {
  flex: 1;
}
</style>
