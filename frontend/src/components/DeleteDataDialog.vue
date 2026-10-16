<!--
  "Xóa số liệu": delete saved entries now - one customer or everyone, an
  optional date range, optionally keeping the newest N days. Shows how many
  entries would go (dry run, no password) and needs the account password.
  API: POST /me/entries/bulk-delete
       { customerName, dateFrom, dateTo, keepDays, dryRun, password, allDataConfirmed }
       -> { count } (dryRun) | { deleted }.  403 wrong password, 429 locked out.
  Emits `deleted` (with the number removed) and `close`.
-->
<script setup>
import { computed, ref, watch } from 'vue'
import { api } from '../api'
import ModalDialog from './ModalDialog.vue'
import AppButton from './AppButton.vue'
import PasswordInput from './PasswordInput.vue'
import AppSelect from './AppSelect.vue'
import AppDatePicker from './AppDatePicker.vue'

const props = defineProps({
  open: { type: Boolean, default: false },
  customerName: { type: String, default: '' }, // customer currently selected on the page
  dateFrom: { type: String, default: '' }, // range currently viewed
  dateTo: { type: String, default: '' },
  singleDay: { type: String, default: '' }, // set when opened from a day card
})
const emit = defineEmits(['deleted', 'close'])

const scope = ref('customer') // 'customer' | 'all'
const from = ref('')
const to = ref('')
const keepDays = ref(0)
const password = ref('')
const allConfirmed = ref(false)
const count = ref(null)
const error = ref('')
const busy = ref(false)

watch(
  () => props.open,
  (o) => {
    if (!o) return
    scope.value = props.customerName ? 'customer' : 'all'
    from.value = props.singleDay || props.dateFrom
    to.value = props.singleDay || props.dateTo
    keepDays.value = 0
    password.value = ''
    allConfirmed.value = false
    error.value = ''
    busy.value = false
    refreshCount()
  },
)

const keep = computed(() => Math.max(0, Math.trunc(Number(keepDays.value) || 0)))
const hasLimit = computed(() => scope.value === 'customer' || from.value || to.value || keep.value > 0)

function body(extra) {
  return {
    customerName: scope.value === 'customer' ? props.customerName : null,
    dateFrom: from.value || null,
    dateTo: to.value || null,
    keepDays: keep.value,
    ...(hasLimit.value ? {} : { allDataConfirmed: true }),
    ...extra,
  }
}

let seq = 0
let timer = null
function refreshCount() {
  clearTimeout(timer)
  timer = setTimeout(async () => {
    const mine = ++seq
    count.value = null
    try {
      const r = await api.post('/me/entries/bulk-delete', body({ dryRun: true }))
      if (mine === seq) count.value = r.count
    } catch (err) {
      if (mine === seq) error.value = err.message || 'Không đếm được số liệu sẽ bị xoá'
    }
  }, 200)
}
watch([scope, from, to, keepDays], () => {
  if (props.open) {
    error.value = ''
    refreshCount()
  }
})

const vn = (d) => (d ? d.split('-').reverse().join('/') : '...')
const scopeText = computed(() => {
  const who = scope.value === 'customer' ? `khách "${props.customerName}"` : 'TẤT CẢ khách'
  const range = from.value || to.value ? from.value && from.value === to.value ? `ngày ${vn(from.value)}` : `ngày ${vn(from.value)} đến ${vn(to.value)}` : 'mọi ngày'
  return `${who}, ${range}${keep.value ? `, giữ lại ${keep.value} ngày gần nhất` : ''}`
})

async function submit() {
  if (busy.value) return
  error.value = ''
  if (!hasLimit.value && !allConfirmed.value) return (error.value = 'Hãy tích ô xác nhận xoá toàn bộ số liệu')
  if (!password.value) return (error.value = 'Nhập mật khẩu đăng nhập để xác nhận')
  busy.value = true
  try {
    const r = await api.post('/me/entries/bulk-delete', body({ password: password.value }))
    password.value = ''
    emit('deleted', r.deleted)
  } catch (err) {
    error.value = err.message || 'Không xoá được số liệu'
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <ModalDialog :open="open" title="Xóa số liệu" description="Chọn phạm vi cần xóa. Số liệu đã xóa không thể khôi phục." @close="emit('close')">
    <form id="del-data-form" @submit.prevent="submit">
      <div class="field">
        <label>Phạm vi</label>
        <AppSelect v-model="scope">
          <option v-if="customerName" value="customer">Khách đang chọn: {{ customerName }}</option>
          <option value="all">Tất cả khách hàng</option>
        </AppSelect>
      </div>
      <div class="dd-chips" v-if="singleDay">
        <button type="button" class="dd-chip" :class="{ on: from === singleDay && to === singleDay }" @click="from = to = singleDay">
          Chỉ ngày này
        </button>
        <button type="button" class="dd-chip" :class="{ on: from === dateFrom && to === dateTo && !(from === singleDay && to === singleDay) }" @click="(from = dateFrom), (to = dateTo)">
          Khoảng đang xem
        </button>
      </div>
      <div class="dd-dates">
        <div class="field">
          <label>Từ ngày</label>
          <AppDatePicker v-model="from" />
        </div>
        <div class="field">
          <label>Đến ngày</label>
          <AppDatePicker v-model="to" />
        </div>
      </div>
      <div class="field">
        <label for="dd-keep">Giữ lại N ngày gần nhất (tuỳ chọn)</label>
        <input id="dd-keep" v-model.number="keepDays" type="number" min="0" max="3650" inputmode="numeric" />
      </div>

      <div class="dd-count" :class="{ zero: count === 0 }" aria-live="polite">
        <template v-if="count === null">Đang đếm số liệu...</template>
        <template v-else>Sẽ xóa <strong>{{ count }}</strong> số liệu của {{ scopeText }}. Không thể khôi phục.</template>
      </div>

      <label v-if="!hasLimit" class="dd-check">
        <input v-model="allConfirmed" type="checkbox" />
        Tôi hiểu: xóa TOÀN BỘ số liệu của tất cả khách hàng
      </label>

      <div class="field">
        <label for="dd-password">Mật khẩu đăng nhập</label>
        <PasswordInput id="dd-password" v-model="password" data-autofocus autocomplete="current-password" :disabled="busy" />
      </div>
      <div v-if="error" class="alert alert-error" role="alert" style="margin: 0">{{ error }}</div>
    </form>
    <template #footer>
      <AppButton variant="ghost" :disabled="busy" @click="emit('close')">Huỷ</AppButton>
      <AppButton variant="danger" type="submit" form="del-data-form" :loading="busy" :disabled="count === 0">{{ busy ? 'Đang xóa...' : 'Xóa' }}</AppButton>
    </template>
  </ModalDialog>
</template>

<style scoped>
.dd-dates {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
}
.dd-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin: -4px 0 12px;
}
.dd-chip {
  min-height: 44px;
  padding: 0 14px;
  font-size: 14px;
  font-weight: 600;
  color: var(--text-primary);
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 999px;
  cursor: pointer;
}
.dd-chip.on {
  color: var(--on-primary);
  background: var(--primary);
  border-color: var(--primary);
}
.dd-count {
  margin-bottom: 16px;
  padding: 10px 12px;
  font-size: 14px;
  line-height: 1.5;
  color: var(--danger-text);
  background: var(--danger-soft);
  border-radius: 10px;
  overflow-wrap: anywhere;
}
.dd-count.zero {
  color: var(--text-secondary);
  background: var(--surface);
}
.dd-check {
  display: flex;
  align-items: center;
  gap: 10px;
  min-height: 44px;
  margin-bottom: 12px;
  font-size: 14px;
}
.dd-check input {
  width: 18px;
  height: 18px;
  accent-color: var(--danger-strong);
}
@media (max-width: 480px) {
  .dd-dates {
    grid-template-columns: 1fr;
  }
}
</style>
