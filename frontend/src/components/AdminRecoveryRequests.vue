<!--
  Admin queue of "nhờ Admin hỗ trợ khôi phục" requests (A06). Admin verifies the
  person outside the app, then approves: a one-time ticket (valid 24 h) is shown
  ONCE to pass on; the customer sets their own new password with it, so the
  admin never learns it. Rejecting closes the request.
  API: GET /admin/recovery-requests, POST /admin/recovery-requests/:id {action}
-->
<script setup>
import AppButton from './AppButton.vue'
import { onMounted, ref } from 'vue'
import { api, ApiError } from '../api'
import { showConfirm } from '../confirm'

const emit = defineEmits(['count'])
const requests = ref([])
const loading = ref(true)
const error = ref('')
const busyId = ref('')
const issued = ref(null) // { username, ticket, expiresAt } - shown once
const copied = ref(false)

const STATUS = { pending: 'Chờ duyệt', approved: 'Đã cấp mã', expired: 'Mã hết hạn' }
const fmt = (iso) => (iso ? new Date(iso).toLocaleString('vi-VN') : '-')

async function load() {
  error.value = ''
  try {
    const res = await api.get('/admin/recovery-requests')
    requests.value = res.requests
    emit('count', res.pending)
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không tải được yêu cầu khôi phục'
  } finally {
    loading.value = false
  }
}
onMounted(load)

async function act(r, action) {
  if (action === 'reject' && !(await showConfirm({
    title: 'Từ chối yêu cầu',
    message: `Từ chối yêu cầu khôi phục của "${r.username}"? Mã hỗ trợ đã cấp (nếu có) sẽ vô hiệu.`,
    confirmText: 'Từ chối',
    danger: true,
  }))) return
  busyId.value = r.id
  error.value = ''
  try {
    const res = await api.post(`/admin/recovery-requests/${r.id}`, { action })
    if (action === 'approve') {
      issued.value = { username: r.username, ticket: res.ticket, expiresAt: res.expiresAt }
      copied.value = false
    }
    await load()
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không xử lý được yêu cầu'
  } finally {
    busyId.value = ''
  }
}

async function copyTicket() {
  try {
    await navigator.clipboard.writeText(issued.value.ticket)
    copied.value = true
  } catch {
    /* clipboard blocked - the code is on screen to copy by hand */
  }
}
</script>

<template>
  <section v-if="loading || requests.length || issued || error" class="card rr-card" aria-label="Yêu cầu hỗ trợ khôi phục tài khoản">
    <h2 class="rr-title">Yêu cầu hỗ trợ khôi phục tài khoản</h2>
    <p class="rr-sub">
      Hãy xác minh người gửi là chủ tài khoản qua kênh riêng (số điện thoại, tin nhắn đã đăng ký...) trước khi duyệt. Khách sẽ tự đặt mật khẩu mới bằng mã hỗ trợ, Admin không biết mật khẩu.
    </p>
    <div v-if="error" class="alert alert-error">{{ error }}</div>

    <div v-if="issued" class="alert alert-success rr-issued">
      <p>
        Mã hỗ trợ cho <strong>{{ issued.username }}</strong>: <strong class="rr-code">{{ issued.ticket }}</strong>
        <AppButton variant="ghost" size="sm" @click="copyTicket">{{ copied ? 'Đã chép' : 'Chép' }}</AppButton>
      </p>
      <p class="rr-hint">
        Hạn dùng đến {{ fmt(issued.expiresAt) }}, dùng một lần. Gửi cho khách qua kênh riêng ngay bây giờ vì mã không xem lại được. Khách vào Đăng nhập, Quên mật khẩu, "Tôi đã có mã hỗ trợ từ Admin".
      </p>
      <AppButton variant="secondary" size="sm" @click="issued = null">Đã gửi, ẩn mã</AppButton>
    </div>

    <p v-if="loading">Đang tải...</p>
    <ul v-else class="rr-list">
      <li v-for="r in requests" :key="r.id" class="rr-item">
        <div class="rr-main">
          <div class="rr-name">
            {{ r.name }} <span class="rr-user">({{ r.username }})</span>
            <span class="rr-status" :class="`st-${r.status}`">{{ STATUS[r.status] || r.status }}</span>
            <span v-if="r.accountLocked" class="rr-status st-expired">Tài khoản đang khoá</span>
          </div>
          <div class="rr-meta">
            Gửi lúc {{ fmt(r.createdAt) }} · IP {{ r.ip || '-' }} · Đăng ký {{ fmt(r.registeredAt) }}
            <template v-if="r.status === 'approved'"> · Mã hết hạn {{ fmt(r.ticketExpiresAt) }}</template>
          </div>
          <div v-if="r.note" class="rr-note">Ghi chú của khách: {{ r.note }}</div>
        </div>
        <div class="rr-actions">
          <AppButton variant="primary" size="sm" :disabled="busyId === r.id" @click="act(r, 'approve')">
{{ r.status === 'pending' ? 'Duyệt, cấp mã' : 'Cấp lại mã' }}
</AppButton>
          <button type="button" class="btn btn-ghost btn-sm rr-reject" :disabled="busyId === r.id" @click="act(r, 'reject')">Từ chối</button>
        </div>
      </li>
    </ul>
  </section>
</template>

<style scoped>
.rr-card {
  margin-bottom: 16px;
  padding: 16px;
  border-radius: 12px;
}
.rr-title {
  margin: 0 0 4px;
  font-size: 16px;
}
.rr-sub,
.rr-hint {
  margin: 0 0 12px;
  font-size: 13px;
  color: var(--muted);
}
.rr-issued {
  margin-bottom: 12px;
}
.rr-issued p {
  margin: 0 0 8px;
}
.rr-code {
  letter-spacing: 0.06em;
}
.rr-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
  margin: 0;
  padding: 0;
  list-style: none;
}
.rr-item {
  display: flex;
  flex-wrap: wrap;
  justify-content: space-between;
  gap: 8px 16px;
  padding: 12px;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 10px;
}
.rr-main {
  flex: 1 1 280px;
  min-width: 0;
}
.rr-name {
  font-weight: 600;
}
.rr-user {
  font-weight: 400;
  color: var(--muted);
}
.rr-status {
  margin-left: 8px;
  padding: 2px 8px;
  font-size: 12px;
  font-weight: 600;
  border-radius: 999px;
  background: var(--card);
  border: 1px solid var(--border);
}
.st-pending {
  color: var(--danger-text);
}
.st-approved {
  color: var(--success-text);
}
.rr-meta,
.rr-note {
  margin-top: 4px;
  font-size: 13px;
  color: var(--muted);
  overflow-wrap: anywhere;
}
.rr-actions {
  display: flex;
  align-items: center;
  gap: 8px;
}
.rr-reject {
  color: var(--danger-text);
}
</style>
