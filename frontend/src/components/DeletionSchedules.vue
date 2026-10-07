<!--
  "Lịch xoá dữ liệu": schedule the automatic removal of your saved entries
  (one customer or everyone, optionally a date range - or repeating, keeping
  the newest N days) and see/cancel every pending schedule, including the
  auto-delete rules set on friend conversations (see ChatRetentionPanel).
  Shared by the Tài khoản page (a card) and the Tính điểm page (inside a
  dialog, `embedded`). Before anything is saved the server returns a preview
  (what is deleted, first run time, how many entries a run now would remove)
  that is shown in a confirm dialog; nothing is created without it.
  API: GET/POST /me/deletion-schedules, DELETE /me/deletion-schedules/:id,
       GET /me/customers
  A repeating schedule never carries dateFrom/dateTo (the server refuses it).
-->
<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { api } from '../api'
import { showConfirm } from '../confirm'
import AppSelect from './AppSelect.vue'
import AppDatePicker from './AppDatePicker.vue'
import PasswordInput from './PasswordInput.vue'

const props = defineProps({
  // pre-selected customer name ('' = all customers)
  customerName: { type: String, default: '' },
  // no outer card / heading (used inside a dialog)
  embedded: { type: Boolean, default: false },
})
const emit = defineEmits(['changed'])

const schedules = ref([])
const customers = ref([])
const loading = ref(true)
const error = ref('')
const success = ref('')
const saving = ref(false)
const form = reactive({
  customerName: props.customerName,
  dateFrom: '',
  dateTo: '',
  repeat: 'none', // none | 1w | 10d | 1m | custom
  customN: 2,
  customUnit: 'day',
  keepDays: 0,
  runAt: '',
  password: '',
})
let runAtTouched = false

const TTL_TEXT = { 3600: '1 giờ', 86400: '1 ngày', 604800: '7 ngày', 2592000: '30 ngày' }
const UNIT_TEXT = { day: 'ngày', week: 'tuần', month: 'tháng' }

function fmt(iso) {
  return iso ? new Date(iso).toLocaleString('vi-VN') : ''
}

function repeatText(r) {
  return r ? `${r.every} ${UNIT_TEXT[r.unit] || r.unit}` : ''
}

// The chosen repeat as the API's { every, unit } (null = one-off).
const repeatValue = computed(() => {
  switch (form.repeat) {
    case '1w':
      return { every: 1, unit: 'week' }
    case '10d':
      return { every: 10, unit: 'day' }
    case '1m':
      return { every: 1, unit: 'month' }
    case 'custom':
      return { every: Math.trunc(Number(form.customN)) || 0, unit: form.customUnit }
    default:
      return null
  }
})

function addCycle(date, r) {
  const d = new Date(date)
  if (!r) d.setDate(d.getDate() + 1)
  else if (r.unit === 'day') d.setDate(d.getDate() + r.every)
  else if (r.unit === 'week') d.setDate(d.getDate() + 7 * r.every)
  else d.setMonth(d.getMonth() + r.every)
  return d
}

function toLocalInput(d) {
  const p = (n) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`
}

// Default first run = now + one cycle, until the user types their own.
function defaultRunAt() {
  const r = repeatValue.value
  form.runAt = toLocalInput(addCycle(new Date(), r && r.every > 0 ? r : null))
}
watch(repeatValue, () => {
  if (!runAtTouched) defaultRunAt()
}, { deep: true })
watch(() => form.repeat, (r) => {
  if (r !== 'none') {
    form.dateFrom = ''
    form.dateTo = ''
  }
})
watch(() => props.customerName, (n) => {
  form.customerName = n
})

async function load() {
  loading.value = true
  try {
    const [s, c] = await Promise.all([api.get('/me/deletion-schedules'), api.get('/me/customers')])
    schedules.value = s.schedules
    customers.value = c.customers
  } catch (err) {
    error.value = err.message || 'Không tải được lịch xoá'
  } finally {
    loading.value = false
  }
}
onMounted(() => {
  defaultRunAt()
  load()
})

function describe(s) {
  if (s.kind === 'chat') {
    const what = s.chatScope === 'images' ? 'Ảnh' : 'Tin nhắn & tệp'
    return `${what} cũ hơn ${TTL_TEXT[s.ttlSeconds] || s.ttlSeconds + ' giây'} trong cuộc trò chuyện với ${s.friendName || '?'}`
  }
  const who = s.customerName ? `khách "${s.customerName}"` : 'mọi khách'
  const range = s.dateFrom || s.dateTo ? `, ngày ${s.dateFrom || '...'} đến ${s.dateTo || '...'}` : ', mọi ngày'
  const keep = s.keepDays > 0 ? `, giữ lại ${s.keepDays} ngày gần nhất` : ''
  return `Số liệu đã nhập của ${who}${range}${keep}`
}

function statusText(s) {
  if (s.status === 'done') return `Đã xoá ${s.deletedCount} mục lúc ${fmt(s.executedAt)}`
  if (s.kind === 'chat') return `Đang áp dụng từ ${fmt(s.runAt)}${s.deletedCount ? ` (đã xoá ${s.deletedCount} mục)` : ''}`
  return `Sẽ xoá lúc ${fmt(s.runAt)}`
}

async function submit() {
  error.value = ''
  success.value = ''
  if (!form.runAt) return (error.value = 'Vui lòng chọn thời điểm xoá')
  const repeat = repeatValue.value
  if (form.repeat === 'custom' && (!repeat.every || repeat.every < 1 || repeat.every > 365)) {
    return (error.value = 'Chu kỳ lặp phải từ 1 đến 365')
  }
  const keep = Math.trunc(Number(form.keepDays) || 0)
  if (keep < 0 || keep > 3650) return (error.value = 'Số ngày giữ lại phải từ 0 đến 3650')
  if (!form.password) return (error.value = 'Nhập mật khẩu đăng nhập để xác nhận')
  const body = {
    kind: 'data',
    customerName: form.customerName || undefined,
    runAt: new Date(form.runAt).toISOString(),
  }
  if (repeat) body.repeat = repeat
  else {
    body.dateFrom = form.dateFrom || undefined
    body.dateTo = form.dateTo || undefined
  }
  if (keep > 0) body.keepDays = keep
  saving.value = true
  try {
    // Step 1: the server describes exactly what would be deleted and when.
    const preview = await api.post('/me/deletion-schedules', body)
    const lines = [`CẢNH BÁO: ${preview.scopeText}`]
    if (repeat && !/lặp/i.test(preview.scopeText || '')) lines.push(`Lặp lại mỗi ${repeatText(repeat)}.`)
    lines.push(`Thời điểm xoá${repeat ? ' lần đầu' : ''}: ${fmt(preview.runAt || body.runAt)}.`)
    if (typeof preview.willDeleteNow === 'number') lines.push(`Nếu chạy ngay bây giờ sẽ xoá ${preview.willDeleteNow} số liệu.`)
    lines.push('Bạn có thể huỷ lịch trước thời điểm này.')
    const ok = await showConfirm({
      title: 'Xác nhận lịch xoá dữ liệu',
      message: lines.join('\n\n'),
      confirmText: 'Đặt lịch xoá',
      danger: true,
    })
    if (!ok) return
    // Step 2: confirmed.
    await api.post('/me/deletion-schedules', { ...body, confirm: true, password: form.password })
    form.password = ''
    success.value = 'Đã đặt lịch xoá.'
    await load()
    emit('changed')
  } catch (err) {
    error.value = err.message || 'Không đặt được lịch xoá'
  } finally {
    saving.value = false
  }
}

async function cancel(s) {
  if (!(await showConfirm({
    title: 'Huỷ lịch xoá',
    message: `Huỷ lịch này? ${describe(s)}. Dữ liệu đã bị xoá trước đó sẽ không được khôi phục.`,
    confirmText: 'Huỷ lịch',
  }))) return
  try {
    await api.del(`/me/deletion-schedules/${s.id}`)
    await load()
    emit('changed')
  } catch (err) {
    error.value = err.message || 'Không huỷ được lịch xoá'
  }
}
</script>

<template>
  <div :class="{ card: !embedded }">
    <template v-if="!embedded">
      <h3 style="margin-top: 0">Lịch xoá dữ liệu</h3>
      <p class="page-subtitle" style="margin-bottom: 12px">
        Đặt thời điểm hệ thống tự xoá số liệu đã lưu của bạn, một lần hoặc lặp lại. Bạn sẽ thấy cảnh báo về phạm vi xoá và thời điểm
        trước khi xác nhận, và có thể huỷ lịch bất cứ lúc nào trước khi chạy. Dữ liệu đã xoá không thể khôi phục.
      </p>
    </template>
    <div v-if="error" class="alert alert-error">{{ error }}</div>
    <div v-if="success" class="alert alert-success">{{ success }}</div>

    <form class="sched-form" @submit.prevent="submit">
      <div class="field">
        <label>Khách hàng</label>
        <AppSelect v-model="form.customerName">
          <option value="">Tất cả khách hàng</option>
          <option v-for="c in customers" :key="c.id" :value="c.name">{{ c.name }}</option>
        </AppSelect>
      </div>
      <div class="field">
        <label>Lặp lại</label>
        <AppSelect v-model="form.repeat">
          <option value="none">Không lặp (chỉ một lần)</option>
          <option value="1w">Mỗi 1 tuần</option>
          <option value="10d">Mỗi 10 ngày</option>
          <option value="1m">Mỗi 1 tháng</option>
          <option value="custom">Tuỳ chọn</option>
        </AppSelect>
      </div>
      <div v-if="form.repeat === 'custom'" class="sched-dates">
        <div class="field">
          <label for="sched-n">Mỗi (số)</label>
          <input id="sched-n" v-model.number="form.customN" type="number" min="1" max="365" inputmode="numeric" />
        </div>
        <div class="field">
          <label>Đơn vị</label>
          <AppSelect v-model="form.customUnit">
            <option value="day">ngày</option>
            <option value="week">tuần</option>
            <option value="month">tháng</option>
          </AppSelect>
        </div>
      </div>
      <div v-if="form.repeat === 'none'" class="sched-dates">
        <div class="field">
          <label>Từ ngày (tuỳ chọn)</label>
          <AppDatePicker v-model="form.dateFrom" />
        </div>
        <div class="field">
          <label>Đến ngày (tuỳ chọn)</label>
          <AppDatePicker v-model="form.dateTo" />
        </div>
      </div>
      <div class="field">
        <label for="sched-keep">Giữ lại N ngày gần nhất</label>
        <input id="sched-keep" v-model.number="form.keepDays" type="number" min="0" max="3650" inputmode="numeric" />
        <small v-if="form.repeat !== 'none'" class="sched-hint">Mỗi lần chạy xoá số liệu cũ hơn số ngày này (0 = xoá hết).</small>
      </div>
      <div class="field">
        <label for="sched-run-at">{{ form.repeat === 'none' ? 'Thời điểm xoá' : 'Thời điểm xoá đầu tiên' }}</label>
        <input id="sched-run-at" v-model="form.runAt" type="datetime-local" @input="runAtTouched = true" />
      </div>
      <div class="field">
        <label for="sched-password">Mật khẩu đăng nhập</label>
        <PasswordInput id="sched-password" v-model="form.password" autocomplete="current-password" />
      </div>
      <button type="submit" class="btn btn-danger" :disabled="saving">{{ saving ? 'Đang xử lý...' : 'Đặt lịch xoá' }}</button>
    </form>

    <div v-if="loading" style="margin-top: 12px">Đang tải...</div>
    <div v-else-if="schedules.length === 0" class="page-subtitle" style="margin: 12px 0 0">Chưa có lịch xoá nào.</div>
    <div v-else class="sched-list">
      <div v-for="s in schedules" :key="s.id" class="sched-item">
        <div class="sched-text">
          <strong>{{ describe(s) }}</strong>
          <span v-if="s.repeat" class="sched-status">Lặp lại mỗi {{ repeatText(s.repeat) }}</span>
          <span v-if="s.kind === 'data' && s.repeat && s.status === 'pending'" class="sched-status">
            Lần chạy kế tiếp: {{ fmt(s.nextRunAt || s.runAt) }}
          </span>
          <span v-else class="sched-status">
            {{ statusText(s) }}<template v-if="s.kind === 'chat' && !s.setByMe"> - do bạn bè đặt</template>
          </span>
          <span v-if="s.kind === 'data' && s.repeat" class="sched-status">
            Đã chạy {{ s.runCount || 0 }} lần, xoá tổng {{ s.deletedCount || 0 }} số liệu<template v-if="s.lastRunAt">
              (lần cuối {{ fmt(s.lastRunAt) }})</template>
          </span>
        </div>
        <button v-if="s.status === 'pending'" class="btn btn-ghost btn-sm" @click="cancel(s)">Huỷ lịch</button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.sched-dates {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
}
.sched-hint {
  display: block;
  margin-top: 4px;
  font-size: 14px;
  color: var(--text-secondary);
}
.sched-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
  margin-top: 16px;
}
.sched-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  padding: 8px 8px 8px 12px;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 10px;
}
.sched-text {
  display: flex;
  flex-direction: column;
  min-width: 0;
  font-size: 14px;
}
.sched-status {
  font-size: 14px;
  color: var(--text-secondary);
}
@media (max-width: 480px) {
  .sched-item {
    flex-direction: column;
    align-items: stretch;
  }
}
</style>
