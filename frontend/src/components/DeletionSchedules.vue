<!--
  "Lịch xoá dữ liệu" card on the Tài khoản page (K35/K36/S05): schedule the
  automatic removal of your saved entries (optionally one customer / a date
  range) at a chosen time, and see/cancel every pending schedule - including
  the auto-delete rules set on friend conversations (see ChatRetentionPanel).
  The server runs them from a background timer. Before anything is saved the
  server returns a warning (what is deleted + when) that is shown in a
  confirm dialog; nothing is created without that confirmation.
  API: GET/POST /me/deletion-schedules, DELETE /me/deletion-schedules/:id,
       GET /me/customers
-->
<script setup>
import { onMounted, reactive, ref } from 'vue'
import { api } from '../api'
import { showConfirm } from '../confirm'
import AppSelect from './AppSelect.vue'
import AppDatePicker from './AppDatePicker.vue'

const schedules = ref([])
const customers = ref([])
const loading = ref(true)
const error = ref('')
const success = ref('')
const saving = ref(false)
const form = reactive({ customerName: '', dateFrom: '', dateTo: '', runAt: '', password: '' })

const TTL_TEXT = { 3600: '1 giờ', 86400: '1 ngày', 604800: '7 ngày', 2592000: '30 ngày' }

function fmt(iso) {
  return iso ? new Date(iso).toLocaleString('vi-VN') : ''
}

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
onMounted(load)

function describe(s) {
  if (s.kind === 'chat') {
    const what = s.chatScope === 'images' ? 'Ảnh' : 'Tin nhắn & tệp'
    return `${what} cũ hơn ${TTL_TEXT[s.ttlSeconds] || s.ttlSeconds + ' giây'} trong cuộc trò chuyện với ${s.friendName || '?'}`
  }
  const who = s.customerName ? `khách "${s.customerName}"` : 'mọi khách'
  const range = s.dateFrom || s.dateTo ? `, ngày ${s.dateFrom || '...'} đến ${s.dateTo || '...'}` : ', mọi ngày'
  return `Số liệu đã nhập của ${who}${range}`
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
  if (!form.password) return (error.value = 'Nhập mật khẩu đăng nhập để xác nhận')
  const body = {
    kind: 'data',
    customerName: form.customerName || undefined,
    dateFrom: form.dateFrom || undefined,
    dateTo: form.dateTo || undefined,
    runAt: new Date(form.runAt).toISOString(),
  }
  saving.value = true
  try {
    // Step 1: the server describes exactly what would be deleted and when.
    const preview = await api.post('/me/deletion-schedules', body)
    const ok = await showConfirm({
      title: 'Xác nhận lịch xoá dữ liệu',
      message: `CẢNH BÁO: ${preview.scopeText}\n\nThời điểm xoá: ${fmt(preview.runAt)}. Bạn có thể huỷ lịch trước thời điểm này.`,
      confirmText: 'Đặt lịch xoá',
      danger: true,
    })
    if (!ok) return
    // Step 2: confirmed.
    await api.post('/me/deletion-schedules', { ...body, confirm: true, password: form.password })
    form.password = ''
    success.value = 'Đã đặt lịch xoá.'
    await load()
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
  } catch (err) {
    error.value = err.message || 'Không huỷ được lịch xoá'
  }
}
</script>

<template>
  <div class="card">
    <h3 style="margin-top: 0">Lịch xoá dữ liệu</h3>
    <p class="page-subtitle" style="margin-bottom: 12px">
      Đặt thời điểm hệ thống tự xoá số liệu đã lưu của bạn. Bạn sẽ thấy cảnh báo về phạm vi xoá và thời điểm trước khi xác nhận,
      và có thể huỷ lịch bất cứ lúc nào trước khi chạy. Dữ liệu đã xoá không thể khôi phục.
    </p>
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
      <div class="sched-dates">
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
        <label for="sched-run-at">Thời điểm xoá</label>
        <input id="sched-run-at" v-model="form.runAt" type="datetime-local" />
      </div>
      <div class="field">
        <label for="sched-password">Mật khẩu đăng nhập</label>
        <input id="sched-password" v-model="form.password" type="password" autocomplete="current-password" />
      </div>
      <button type="submit" class="btn btn-danger" :disabled="saving">{{ saving ? 'Đang xử lý...' : 'Đặt lịch xoá' }}</button>
    </form>

    <div v-if="loading" style="margin-top: 12px">Đang tải...</div>
    <div v-else-if="schedules.length === 0" class="page-subtitle" style="margin: 12px 0 0">Chưa có lịch xoá nào.</div>
    <div v-else class="sched-list">
      <div v-for="s in schedules" :key="s.id" class="sched-item">
        <div class="sched-text">
          <strong>{{ describe(s) }}</strong>
          <span class="sched-status">{{ statusText(s) }}<template v-if="s.kind === 'chat' && !s.setByMe"> - do bạn bè đặt</template></span>
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
  font-size: 12px;
  color: var(--text-secondary);
}
</style>
