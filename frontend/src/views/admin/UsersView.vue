<!--
  /admin/users - searchable subscriber table + detail panel.
  API: GET /admin/users?q=  (list, registration-only fields)
       GET /admin/users/:id (detail, same shape)
       PATCH /admin/users/:id { locked }  (lock/unlock login)
       DELETE /admin/users/:id  (permanently removes account + their data)
-->
<script setup>
import AppButton from '../../components/AppButton.vue'
import { showConfirm } from '../../confirm'
import { ref, onMounted, watch } from 'vue'
import { api, ApiError } from '../../api'
import AppIcon from '../../components/AppIcon.vue'
import AdminRecoveryRequests from '../../components/AdminRecoveryRequests.vue'
import { useAuthStore } from '../../stores/auth'

const auth = useAuthStore()

const q = ref('')
const loading = ref(false)
const error = ref('')
const total = ref(0)
const subscribers = ref([])

const selected = ref(null)
const detailLoading = ref(false)
const detailError = ref('')
const actionBusy = ref(false)
const actionError = ref('')
const confirmDelete = ref(false)

const showResetPassword = ref(false)
const newPassword = ref('')
const lastSetPassword = ref('')
const lastRecoveryCode = ref('') // shown once, right after a reset / re-issue
const supportNote = ref('')
const copied = ref('')

// Random password that passes the server policy (8+ chars, not a common/sequential one).
function generatePassword() {
  const letters = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ'
  const digits = '23456789'
  const all = letters + digits
  const buf = new Uint32Array(10)
  crypto.getRandomValues(buf)
  const chars = [...buf].map((n, i) => (i === 3 || i === 7 ? digits[n % digits.length] : all[n % all.length]))
  newPassword.value = chars.join('')
}
async function copyText(text, key) {
  try {
    await navigator.clipboard.writeText(text)
    copied.value = key
    setTimeout(() => (copied.value = ''), 2000)
  } catch {
    /* clipboard blocked - the value is on screen to copy by hand */
  }
}

// Recovery support without changing the password: re-issue the code / lift lockouts.
async function supportAction(kind) {
  if (!selected.value) return
  actionBusy.value = true
  actionError.value = ''
  supportNote.value = ''
  try {
    const body = kind === 'code' ? { reissueRecoveryCode: true } : { clearLockouts: true }
    const updated = await api.patch(`/admin/users/${selected.value.id}`, body)
    if (updated.recoveryCode) lastRecoveryCode.value = updated.recoveryCode
    supportNote.value = kind === 'code' ? 'Đã cấp mã khôi phục mới (mã cũ không còn dùng được).' : 'Đã gỡ mọi khoá đăng nhập/xác thực/khôi phục của tài khoản.'
    selected.value = { ...selected.value, ...updated }
  } catch (err) {
    actionError.value = err instanceof ApiError ? err.message : 'Không thể thực hiện'
  } finally {
    actionBusy.value = false
  }
}

let searchTimer = null

async function loadList() {
  loading.value = true
  error.value = ''
  try {
    const res = await api.get(`/admin/users${q.value ? `?q=${encodeURIComponent(q.value)}` : ''}`)
    total.value = res.total
    subscribers.value = res.subscribers
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không thể tải danh sách'
  } finally {
    loading.value = false
  }
}

watch(q, () => {
  clearTimeout(searchTimer)
  searchTimer = setTimeout(loadList, 300)
})

// Active device sessions of the opened user (admin can revoke them).
const userSessions = ref([])
const sessionsError = ref('')

async function loadUserSessions(id) {
  sessionsError.value = ''
  if (!auth.can('users.lock')) return
  try {
    userSessions.value = (await api.get(`/admin/users/${id}/sessions`)).sessions || []
  } catch (err) {
    userSessions.value = []
    sessionsError.value = err instanceof ApiError ? err.message : 'Không thể tải danh sách thiết bị'
  }
}

async function revokeUserSession(sid) {
  sessionsError.value = ''
  try {
    if (sid) await api.del(`/admin/users/${selected.value.id}/sessions/${sid}`)
    else await api.del(`/admin/users/${selected.value.id}/sessions`)
    await loadUserSessions(selected.value.id)
  } catch (err) {
    sessionsError.value = err instanceof ApiError ? err.message : 'Không thể thu hồi phiên'
  }
}

async function openUser(id) {
  selected.value = id
  userSessions.value = []
  detailLoading.value = true
  detailError.value = ''
  actionError.value = ''
  confirmDelete.value = false
  try {
    const detail = await api.get(`/admin/users/${id}`)
    selected.value = detail
    loadUserSessions(id)
  } catch (err) {
    detailError.value = err instanceof ApiError ? err.message : 'Không thể tải chi tiết'
    selected.value = null
  } finally {
    detailLoading.value = false
  }
}

function closeDetail() {
  selected.value = null
  confirmDelete.value = false
  actionError.value = ''
  showResetPassword.value = false
  newPassword.value = ''
  lastSetPassword.value = ''
  lastRecoveryCode.value = ''
  supportNote.value = ''
}

async function resetPassword() {
  if (!selected.value || !newPassword.value.trim()) return
  actionBusy.value = true
  actionError.value = ''
  try {
    const updated = await api.patch(`/admin/users/${selected.value.id}`, {
      newPassword: newPassword.value.trim(),
    })
    lastSetPassword.value = newPassword.value.trim()
    lastRecoveryCode.value = updated.recoveryCode || ''
    supportNote.value = ''
    newPassword.value = ''
    showResetPassword.value = false
    selected.value = { ...selected.value, ...updated }
  } catch (err) {
    actionError.value = err instanceof ApiError ? err.message : 'Không thể đặt lại mật khẩu'
  } finally {
    actionBusy.value = false
  }
}

async function toggleLock() {
  if (!selected.value) return
  const locking = !selected.value.accountLocked
  if (!(await showConfirm({
    title: locking ? 'Khoá tài khoản' : 'Mở khoá tài khoản',
    message: locking
      ? `Khoá tài khoản "${selected.value.name}"? Khách hàng sẽ không đăng nhập được.`
      : `Mở khoá tài khoản "${selected.value.name}"?`,
    confirmText: locking ? 'Khoá' : 'Mở khoá',
    danger: locking,
  }))) return
  actionBusy.value = true
  actionError.value = ''
  try {
    const nextLocked = !selected.value.accountLocked
    const updated = await api.patch(`/admin/users/${selected.value.id}`, { locked: nextLocked })
    selected.value = updated
    const idx = subscribers.value.findIndex((s) => s.id === updated.id)
    if (idx !== -1) subscribers.value[idx] = { ...subscribers.value[idx], ...updated }
  } catch (err) {
    actionError.value = err instanceof ApiError ? err.message : 'Không thể cập nhật'
  } finally {
    actionBusy.value = false
  }
}

async function deleteUser() {
  if (!selected.value) return
  if (!(await showConfirm({
    title: 'Xoá tài khoản',
    message: 'Xoá vĩnh viễn tài khoản này và toàn bộ dữ liệu liên quan?',
    confirmText: 'Xoá',
    danger: true,
  }))) return
  actionBusy.value = true
  actionError.value = ''
  try {
    await api.del(`/admin/users/${selected.value.id}`)
    subscribers.value = subscribers.value.filter((s) => s.id !== selected.value.id)
    total.value = subscribers.value.length
    closeDetail()
  } catch (err) {
    actionError.value = err instanceof ApiError ? err.message : 'Không thể xoá tài khoản'
  } finally {
    actionBusy.value = false
  }
}

onMounted(loadList)
</script>

<template>
  <div class="page">
    <h1 class="page-title">Quản lý khách hàng</h1>
    <p class="page-subtitle">Tổng cộng {{ total }} khách hàng</p>

    <AdminRecoveryRequests v-if="auth.can('users.recovery')" />

    <div class="field search-field">
      <div class="input-wrap">
        <AppIcon name="search" class="search-icon" />
        <input v-model="q" type="text" placeholder="Tìm theo tên..." aria-label="Tìm theo tên" />
      </div>
    </div>

    <div v-if="error" class="alert alert-error">{{ error }}</div>

    <div class="card table-card">
      <table class="table users-table stack-table">
        <thead>
          <tr>
            <th>Khách hàng</th>
            <th>Tài khoản</th>
            <th>Gói</th>
            <th>Hết hạn</th>
            <th>Trạng thái</th>
            <th class="col-action">Chi tiết</th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="loading">
            <td colspan="6">Đang tải...</td>
          </tr>
          <tr v-else-if="subscribers.length === 0">
            <td colspan="6">Không có khách hàng nào</td>
          </tr>
          <tr
            v-for="s in subscribers"
            :key="s.id"
            class="row-click"
            @click="openUser(s.id)"
          >
            <td data-label="Khách hàng">{{ s.name }}</td>
            <td data-label="Tài khoản">{{ s.username }}</td>
            <td data-label="Gói">{{ s.package.label }}</td>
            <td data-label="Hết hạn">{{ s.package.expiresAt ? new Date(s.package.expiresAt).toLocaleDateString('vi-VN') : '-' }}</td>
            <td data-label="Trạng thái">
              <div class="status-cell">
                <span class="chip" :class="s.status === 'active' ? 'chip-accent' : 'chip-warning'">
                  {{ s.status === 'active' ? 'Hoạt động' : 'Hết hạn' }}
                </span>
                <span v-if="s.accountLocked" class="chip chip-danger">Đã khoá</span>
              </div>
            </td>
            <td class="col-action" data-label="Chi tiết">
              <button type="button" class="btn btn-secondary btn-sm detail-btn" @click.stop="openUser(s.id)">
                Xem chi tiết
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Detail panel -->
    <div v-if="selected" class="overlay" @click.self="closeDetail">
      <div class="card detail-panel" role="dialog" aria-modal="true" aria-labelledby="detail-title">
        <div v-if="detailLoading">Đang tải chi tiết...</div>
        <div v-else-if="detailError" class="alert alert-error">{{ detailError }}</div>
        <div v-else>
          <div class="modal-head">
            <div class="modal-title-wrap">
              <h2 id="detail-title" class="modal-title">{{ selected.name }}</h2>
              <p class="modal-username">@{{ selected.username }}</p>
            </div>
            <button class="modal-close" aria-label="Đóng" title="Đóng" @click="closeDetail">
              <AppIcon name="x" />
            </button>
          </div>

          <div class="modal-chips">
            <span class="chip" :class="selected.status === 'active' ? 'chip-accent' : 'chip-warning'">
              {{ selected.status === 'active' ? 'Gói hoạt động' : 'Gói hết hạn' }}
            </span>
            <span class="chip" :class="selected.accountLocked ? 'chip-danger' : 'chip-accent'">
              {{ selected.accountLocked ? 'Tài khoản đã khoá' : 'Tài khoản đang mở' }}
            </span>
          </div>

          <div class="info-card">
            <p class="info-row"><strong>Gói:</strong> <span>{{ selected.package.label }}</span></p>
            <p class="info-row">
              <strong>Hết hạn:</strong>
              <span>{{ selected.package.expiresAt ? new Date(selected.package.expiresAt).toLocaleString('vi-VN') : '-' }}</span>
            </p>
          </div>

          <div v-if="auth.can('users.lock')" class="info-card">
            <p class="info-row">
              <strong>Thiết bị đang đăng nhập ({{ userSessions.length }})</strong>
              <AppButton variant="secondary" size="sm" v-if="userSessions.length > 0" @click="revokeUserSession(null)">Thu hồi tất cả</AppButton>
            </p>
            <div v-if="sessionsError" class="alert alert-error">{{ sessionsError }}</div>
            <p v-for="s in userSessions" :key="s.id" class="info-row">
              <span>
                {{ s.deviceLabel }} · IP {{ s.ip || '-' }}<br />
                <small>Gần nhất: {{ s.lastSeen ? new Date(s.lastSeen).toLocaleString('vi-VN') : '-' }}</small>
              </span>
              <AppButton variant="secondary" size="sm" @click="revokeUserSession(s.id)">Thu hồi</AppButton>
            </p>
          </div>

          <div v-if="actionError" class="alert alert-error">{{ actionError }}</div>
          <div v-if="supportNote" class="alert alert-success">{{ supportNote }}</div>
          <div v-if="lastSetPassword || lastRecoveryCode" class="alert alert-success recovery-result">
            <p v-if="lastSetPassword">
              Mật khẩu mới: <strong>{{ lastSetPassword }}</strong>
              <AppButton variant="ghost" size="sm" @click="copyText(lastSetPassword, 'pw')">{{ copied === 'pw' ? 'Đã chép' : 'Chép' }}</AppButton>
            </p>
            <p v-if="lastRecoveryCode">
              Mã khôi phục mới: <strong>{{ lastRecoveryCode }}</strong>
              <AppButton variant="ghost" size="sm" @click="copyText(lastRecoveryCode, 'rc')">{{ copied === 'rc' ? 'Đã chép' : 'Chép' }}</AppButton>
            </p>
            <p class="recovery-hint">
              Gửi cho khách hàng qua kênh riêng ngay bây giờ: hai giá trị này không xem lại được. Mọi thiết bị của
              khách đã bị đăng xuất, các khoá đăng nhập đã được gỡ và mã khôi phục cũ không còn dùng được.
            </p>
          </div>

          <!-- Mật khẩu gốc được mã hoá một chiều nên không thể xem lại - đây
               là cách duy nhất để admin biết/đặt lại mật khẩu đăng nhập. -->
          <div v-if="showResetPassword" class="reset-box">
            <label class="reset-label" for="new-password">Mật khẩu mới cho tài khoản này</label>
            <div class="reset-row">
              <input id="new-password" v-model="newPassword" type="text" placeholder="Mật khẩu mới" autocomplete="off" />
              <AppButton variant="secondary" size="sm" :disabled="actionBusy"  @click="generatePassword">Tạo ngẫu nhiên</AppButton>
              <AppButton variant="primary" size="sm" :disabled="actionBusy || !newPassword.trim()" @click="resetPassword">Lưu</AppButton>
              <AppButton variant="ghost" size="sm" :disabled="actionBusy" @click="showResetPassword = false; newPassword = ''">Huỷ</AppButton>
            </div>
          </div>

          <div class="modal-actions">
            <div class="actions-main">
            <AppButton variant="secondary" v-if="auth.can('users.lock')" :disabled="actionBusy" @click="toggleLock">
{{ selected.accountLocked ? 'Mở khoá tài khoản' : 'Khoá tài khoản' }}
</AppButton>

            <AppButton variant="secondary" v-if="!showResetPassword && auth.can('users.recovery')" :disabled="actionBusy" @click="showResetPassword = true; lastSetPassword = ''">Đặt lại mật khẩu</AppButton>
            <AppButton variant="secondary" v-if="auth.can('users.recovery')" :disabled="actionBusy" @click="supportAction('code')">Cấp lại mã khôi phục</AppButton>
            <AppButton variant="secondary" v-if="auth.can('users.recovery')" :disabled="actionBusy" @click="supportAction('unlock')">Gỡ khoá đăng nhập</AppButton>
            </div>

            <div v-if="auth.can('users.delete')" class="actions-danger">
            <AppButton variant="danger" :disabled="actionBusy" @click="deleteUser">Xoá tài khoản</AppButton>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.page {
  --ctl-border: var(--input-border);
  --ctl-border-hover: var(--input-border-hover);
  max-width: var(--page-max);
  padding: 32px 24px 96px;
}
.page-title {
  font-size: 28px;
  line-height: 1.2;
  margin-bottom: 8px;
}
.page-subtitle {
  font-size: 15px;
}

/* ---- Search ---- */
.search-field {
  max-width: 400px;
  margin-bottom: 24px;
}
.search-field .search-icon {
  position: absolute;
  left: 14px;
  width: 20px;
  height: 20px;
  color: var(--muted);
  pointer-events: none;
  transition: color 0.15s ease;
}
.search-field .input-wrap:focus-within .search-icon {
  color: var(--focus);
}
.search-field input {
  height: 44px;
  padding: 0 16px 0 44px;
  font-size: 15px;
  border-radius: 10px;
  border: 1px solid var(--ctl-border);
  background: var(--surface-2);
  color: var(--text);
  transition: border-color 0.15s ease, box-shadow 0.15s ease;
}
.search-field input::placeholder {
  color: var(--muted);
  opacity: 1;
}
.search-field input:hover {
  border-color: var(--ctl-border-hover);
}
.search-field input:focus {
  outline: none;
  border-color: var(--focus);
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--focus) 35%, transparent);
}

/* ---- Table ---- */
.page > .alert {
  font-size: 15px;
  border-radius: 12px;
}
.table-card {
  padding: 0;
  overflow-x: auto;
  border-radius: 14px;
}
.users-table {
  font-size: 15px;
  min-width: 760px;
}
.users-table th {
  padding: 14px 20px;
  font-size: 14px;
  font-weight: 700;
  letter-spacing: 0.05em;
  background: var(--surface-2);
  white-space: nowrap;
}
.users-table td {
  padding: 16px 20px;
  vertical-align: middle;
}
.users-table td:first-child {
  font-weight: 700;
}
.users-table td:nth-child(2) {
  color: var(--muted);
}
.users-table tbody tr {
  transition: background 0.12s ease;
}
.users-table tbody tr.row-click {
  cursor: pointer;
}
.users-table tbody tr.row-click:hover {
  background: color-mix(in srgb, var(--accent) 10%, transparent);
}
.users-table tbody tr:only-child td[colspan] {
  padding: 32px 20px;
  text-align: center;
  color: var(--muted);
}
.status-cell {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 8px;
}
.users-table .chip {
  font-size: 14px;
  padding: 4px 12px;
  white-space: nowrap;
}

.users-table .col-action {
  width: 1%;
  white-space: nowrap;
  text-align: center;
}
.users-table .detail-btn {
  min-height: 36px;
  padding: 0 14px;
  font-size: 14px;
  font-weight: 700;
  border-radius: 10px;
  color: var(--text);
  background: var(--surface-2);
  border: 1px solid var(--ctl-border);
}
.users-table .detail-btn:hover {
  background: var(--accent-soft);
  border-color: var(--ctl-border-hover);
}
.users-table .detail-btn:focus-visible {
  outline: 3px solid color-mix(in srgb, var(--focus) 60%, transparent);
  outline-offset: 2px;
}

/* ---- Modal ---- */
.overlay {
  position: fixed;
  inset: 0;
  display: flex;
  padding: 24px 16px;
  background: var(--overlay);
  z-index: 50;
  overflow-y: auto;
}

.detail-panel {
  width: 100%;
  max-width: 520px;
  margin: auto; /* centres vertically + horizontally, scrolls when taller than viewport */
  padding: 24px;
  border-radius: 16px;
  border: 1px solid color-mix(in srgb, var(--muted) 45%, var(--card));
  box-shadow: var(--shadow-lg);
}

.modal-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
  margin-bottom: 16px;
}
.modal-title-wrap {
  min-width: 0;
}
.modal-title {
  margin: 0 0 4px;
  font-size: 24px;
  line-height: 1.25;
  overflow-wrap: anywhere;
}
.modal-username {
  margin: 0;
  font-size: 15px;
  color: color-mix(in srgb, var(--text) 75%, var(--card));
  overflow-wrap: anywhere;
}
.modal-close {
  flex: none;
  width: 40px;
  height: 40px;
  margin: -4px -4px 0 0;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 0;
  font-size: 26px;
  color: var(--text);
  background: var(--surface-2);
  border: 1px solid var(--ctl-border-hover);
  border-radius: 10px;
  cursor: pointer;
  transition: color 0.15s ease, background 0.15s ease, border-color 0.15s ease;
}
.modal-close:hover {
  background: var(--accent-soft);
  border-color: var(--text);
}
.modal-close:focus-visible {
  outline: 3px solid color-mix(in srgb, var(--focus) 60%, transparent);
  outline-offset: 2px;
}

.modal-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin-bottom: 16px;
}
.detail-panel .chip {
  font-size: 14px;
  padding: 4px 10px;
}

.info-card {
  margin-bottom: 16px;
  padding: 0 16px;
  border: 1px solid var(--border);
  border-radius: 12px;
  background: var(--surface-2);
}
.info-row {
  display: grid;
  grid-template-columns: 96px 1fr;
  gap: 16px;
  align-items: baseline;
  margin: 0;
  padding: 8px 0;
  font-size: 15px;
}
.info-row + .info-row {
  border-top: 1px solid var(--border);
}
.info-row strong {
  font-size: 14px;
  font-weight: 700;
  color: var(--muted);
}
.info-row span {
  font-weight: 700;
  overflow-wrap: anywhere;
}

.detail-panel .alert {
  font-size: 15px;
  line-height: 1.5;
  border-radius: 10px;
  margin-bottom: 16px;
}

.reset-box {
  margin: 0 0 16px;
  padding: 16px;
  border: 1px solid var(--ctl-border);
  border-radius: 12px;
  background: var(--surface-2);
}
.reset-label {
  display: block;
  margin-bottom: 8px;
  font-size: 14px;
  font-weight: 700;
  color: var(--text);
}
.reset-row {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
}
.reset-row input {
  flex: 1 1 200px;
  min-width: 0;
  height: 44px;
  padding: 0 14px;
  font-size: 15px;
  border: 1px solid var(--ctl-border);
  border-radius: 10px;
  background: var(--card);
  color: var(--text);
}
.reset-row input::placeholder {
  color: var(--muted);
  opacity: 1;
}
.reset-row input:focus {
  outline: none;
  border-color: var(--focus);
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--focus) 35%, transparent);
}

/* ---- Buttons ---- */
.detail-panel .btn {
  height: 40px;
  min-height: 40px;
  padding: 0 16px;
  font-size: 14px;
  font-weight: 700;
  border-radius: 10px;
}
.detail-panel .btn-secondary {
  background: var(--surface-2);
  color: var(--text);
  border: 1px solid var(--ctl-border);
}
.detail-panel .btn-secondary:hover:not(:disabled) {
  background: var(--accent-soft);
  border-color: var(--ctl-border-hover);
}
.detail-panel .btn:focus-visible {
  outline: 3px solid color-mix(in srgb, var(--focus) 60%, transparent);
  outline-offset: 2px;
}
.detail-panel .btn-sm {
  height: 40px;
  min-height: 40px;
  padding: 0 16px;
  font-size: 14px;
}

.modal-actions {
  display: flex;
  flex-direction: column;
  gap: 16px;
}
.actions-main {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}
/* Destructive action is separated from the routine ones to avoid mis-taps */
.actions-danger {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  padding-top: 16px;
  border-top: 1px solid var(--border);
}
.detail-panel .btn-danger {
  color: #fff;
  background: var(--danger-strong);
}
.detail-panel .btn-danger:hover:not(:disabled) {
  background: var(--danger-hover);
  filter: none;
}
.confirm-msg {
  flex: 1 1 100%;
  margin: 0 !important;
}

/* ---- Responsive ---- */
@media (max-width: 640px) {
  .page {
    padding: 24px 16px 96px;
  }
  .page-title {
    font-size: 24px;
  }
  .search-field {
    max-width: none;
  }
  .users-table th,
  .users-table td {
    padding: 12px 16px;
  }
  .detail-panel {
    padding: 20px 16px;
  }
  .info-row {
    grid-template-columns: 1fr;
    gap: 4px;
  }
  .actions-main .btn,
  .actions-danger .btn {
    flex: 1 1 100%;
  }
}
.recovery-result p {
  margin: 0 0 6px;
  overflow-wrap: anywhere;
}
.recovery-result strong {
  font-family: ui-monospace, monospace;
  letter-spacing: 0.05em;
}
.recovery-hint {
  margin: 8px 0 0;
  font-size: 13px;
}
</style>
