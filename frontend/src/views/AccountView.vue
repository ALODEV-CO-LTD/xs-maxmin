<!--
  Profile + account management: change password, second-password,
  wipe-password, customer codes (share to make friends), and a destructive
  "delete my data" action.

  API: GET/PATCH /me (edit own name/username), POST /me/password, POST /me/second-password,
       POST /me/wipe-password, GET/POST /me/customer-codes,
       DELETE /me/customer-codes/:id, POST /me/delete-data
-->
<script setup>
import { showConfirm } from '../confirm'
import { computed, onMounted, reactive, ref } from 'vue'
import { api } from '../api'
import { useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'
import { useCallStore } from '../stores/call'
import AppIcon from '../components/AppIcon.vue'
import PrivacySettings from '../components/PrivacySettings.vue'
import RecoveryCodePanel from '../components/RecoveryCodePanel.vue'

const auth = useAuthStore()
const router = useRouter()
const call = useCallStore()

// Logout lives here on phones/tablets (the header button is hidden below 860px).
async function logoutNow() {
  if (!(await showConfirm({ title: 'Đăng xuất', message: 'Bạn có chắc muốn đăng xuất?', confirmText: 'Đăng xuất' }))) return
  call.disconnect()
  auth.logout()
  router.push('/login')
}

const loading = ref(true)
const loadError = ref('')

const user = computed(() => auth.user)

async function loadMe() {
  loading.value = true
  loadError.value = ''
  try {
    await auth.fetchMe()
  } catch (err) {
    loadError.value = err.message || 'Không tải được thông tin tài khoản'
  } finally {
    loading.value = false
  }
}
onMounted(loadMe)

// --- Edit own profile (name + username) ---
const editingProfile = ref(false)
const profileForm = reactive({ name: '', username: '', currentPassword: '' })
const profileError = ref('')
const profileSuccess = ref('')
const profileSaving = ref(false)
const usernameChanged = computed(() => profileForm.username.trim() !== (user.value?.username || ''))

function startEditProfile() {
  profileForm.name = user.value?.name || ''
  profileForm.username = user.value?.username || ''
  profileForm.currentPassword = ''
  profileError.value = ''
  profileSuccess.value = ''
  editingProfile.value = true
}

function cancelEditProfile() {
  editingProfile.value = false
  profileError.value = ''
}

async function saveProfile() {
  profileError.value = ''
  profileSuccess.value = ''
  const name = profileForm.name.trim()
  const username = profileForm.username.trim()
  if (!name) {
    profileError.value = 'Vui lòng nhập tên hiển thị'
    return
  }
  if (username.length < 3) {
    profileError.value = 'Tên đăng nhập phải có ít nhất 3 ký tự'
    return
  }
  if (usernameChanged.value && !profileForm.currentPassword) {
    profileError.value = 'Nhập mật khẩu hiện tại để đổi tên đăng nhập'
    return
  }
  profileSaving.value = true
  try {
    const payload = { name, username }
    if (usernameChanged.value) payload.currentPassword = profileForm.currentPassword
    const me = await api.patch('/me', payload)
    auth.user = me
    editingProfile.value = false
    profileSuccess.value = 'Đã cập nhật thông tin tài khoản'
  } catch (err) {
    profileError.value = err.message || 'Không cập nhật được thông tin'
  } finally {
    profileSaving.value = false
  }
}

// --- Change primary password ---
const pwForm = reactive({ currentPassword: '', newPassword: '', confirmPassword: '' })
const pwError = ref('')
const pwSuccess = ref('')
const pwSubmitting = ref(false)

async function submitPasswordChange() {
  pwError.value = ''
  pwSuccess.value = ''
  if (!pwForm.currentPassword || !pwForm.newPassword) {
    pwError.value = 'Vui lòng nhập đầy đủ thông tin'
    return
  }
  if (pwForm.newPassword !== pwForm.confirmPassword) {
    pwError.value = 'Mật khẩu mới nhập lại không khớp'
    return
  }
  pwSubmitting.value = true
  try {
    await api.post('/me/password', {
      currentPassword: pwForm.currentPassword,
      newPassword: pwForm.newPassword,
    })
    pwSuccess.value = 'Đã đổi mật khẩu thành công'
    pwForm.currentPassword = ''
    pwForm.newPassword = ''
    pwForm.confirmPassword = ''
  } catch (err) {
    pwError.value = err.message || 'Không đổi được mật khẩu'
  } finally {
    pwSubmitting.value = false
  }
}

// --- Second password ---
const secondForm = reactive({ currentPassword: '', secondPassword: '' })
const secondError = ref('')
const secondSuccess = ref('')
const secondSubmitting = ref(false)

async function submitSecondPassword() {
  secondError.value = ''
  secondSuccess.value = ''
  if (!secondForm.currentPassword || !secondForm.secondPassword) {
    secondError.value = 'Vui lòng nhập đầy đủ thông tin'
    return
  }
  secondSubmitting.value = true
  try {
    await api.post('/me/second-password', {
      currentPassword: secondForm.currentPassword,
      secondPassword: secondForm.secondPassword,
    })
    secondSuccess.value = 'Đã cập nhật mật khẩu lớp hai'
    secondForm.currentPassword = ''
    secondForm.secondPassword = ''
    await auth.fetchMe()
  } catch (err) {
    secondError.value = err.message || 'Không cập nhật được mật khẩu lớp hai'
  } finally {
    secondSubmitting.value = false
  }
}

// --- Wipe password ---
const wipeForm = reactive({ currentPassword: '', wipePassword: '' })
const wipeError = ref('')
const wipeSuccess = ref('')
const wipeSubmitting = ref(false)

async function submitWipePassword() {
  wipeError.value = ''
  wipeSuccess.value = ''
  if (!wipeForm.currentPassword || !wipeForm.wipePassword) {
    wipeError.value = 'Vui lòng nhập đầy đủ thông tin'
    return
  }
  const verb = user.value?.hasWipePassword ? 'đổi' : 'đặt'
  if (!(await showConfirm({
    title: `Xác nhận ${verb} mật khẩu`,
    message: `Xác nhận ${verb} mật khẩu xoá dữ liệu? Nếu bạn đăng nhập bằng mật khẩu này, hệ thống sẽ hỏi xác nhận xoá toàn bộ dữ liệu.`,
    confirmText: 'Xác nhận',
  }))) {
    return
  }
  wipeSubmitting.value = true
  try {
    await api.post('/me/wipe-password', {
      currentPassword: wipeForm.currentPassword,
      wipePassword: wipeForm.wipePassword,
    })
    wipeSuccess.value = `Đã ${verb} mật khẩu xoá dữ liệu`
    wipeForm.currentPassword = ''
    wipeForm.wipePassword = ''
    await auth.fetchMe()
  } catch (err) {
    wipeError.value = err.message || 'Không cập nhật được mật khẩu xoá dữ liệu'
  } finally {
    wipeSubmitting.value = false
  }
}

// --- Customer codes ---
const codes = ref([])
const codesLoading = ref(true)
const codesError = ref('')
const generatingCode = ref(false)

async function loadCodes() {
  codesLoading.value = true
  codesError.value = ''
  try {
    const res = await api.get('/me/customer-codes')
    codes.value = res.codes
  } catch (err) {
    codesError.value = err.message || 'Không tải được danh sách mã ID'
  } finally {
    codesLoading.value = false
  }
}
onMounted(loadCodes)

async function generateCode() {
  generatingCode.value = true
  codesError.value = ''
  try {
    const code = await api.post('/me/customer-codes')
    codes.value.unshift(code)
  } catch (err) {
    codesError.value = err.message || 'Không tạo được mã ID'
  } finally {
    generatingCode.value = false
  }
}

async function deleteCode(code) {
  if (!(await showConfirm({
    title: 'Xoá mã ID',
    message: `Xoá mã ID "${code.code}"? Người khác sẽ không thể dùng mã này để kết bạn với bạn nữa.`,
    confirmText: 'Xoá',
    danger: true,
  }))) return
  try {
    await api.del(`/me/customer-codes/${code.id}`)
    codes.value = codes.value.filter((c) => c.id !== code.id)
  } catch (err) {
    alert(err.message || 'Không xoá được mã ID')
  }
}

async function copyCode(code) {
  try {
    await navigator.clipboard.writeText(code)
  } catch {
    /* clipboard unavailable - user can still select the text manually */
  }
}

// --- Delete all data ---
const deleteError = ref('')
const deleteSuccess = ref('')
const deleting = ref(false)

async function deleteAllData() {
  if (!(await showConfirm({
    title: 'Xoá toàn bộ dữ liệu',
    message: 'CẢNH BÁO: Thao tác này sẽ xoá toàn bộ số liệu, tin nhắn phản hồi và lịch sử giao dịch của bạn. Tài khoản và gói dịch vụ vẫn giữ nguyên. Bạn có chắc chắn muốn tiếp tục?',
    confirmText: 'Xoá dữ liệu',
    danger: true,
  }))) {
    return
  }
  const password = prompt('Nhập mật khẩu đăng nhập để xác nhận xoá dữ liệu:')
  if (!password) return
  deleteError.value = ''
  deleteSuccess.value = ''
  deleting.value = true
  try {
    await api.post('/me/delete-data', { password })
    deleteSuccess.value = 'Đã xoá toàn bộ dữ liệu của bạn.'
  } catch (err) {
    deleteError.value = err.message || 'Không xoá được dữ liệu'
  } finally {
    deleting.value = false
  }
}
</script>

<template>
  <div class="page">
    <h1 class="page-title">Tài khoản</h1>
    <p class="page-subtitle">Thông tin cá nhân và bảo mật.</p>

    <div v-if="loading" class="card">Đang tải...</div>
    <div v-else-if="loadError" class="alert alert-error">{{ loadError }}</div>
    <template v-else>
      <div class="account-top">
      <div class="card profile-card">
        <div class="card-head">
          <h3 style="margin-top: 0">Thông tin cá nhân</h3>
          <button v-if="!editingProfile" type="button" class="btn btn-secondary btn-sm" @click="startEditProfile">
            Sửa
          </button>
        </div>
        <div v-if="profileSuccess" class="alert alert-success">{{ profileSuccess }}</div>
        <form v-if="editingProfile" class="profile-form" @submit.prevent="saveProfile">
          <div v-if="profileError" class="alert alert-error">{{ profileError }}</div>
          <div class="field">
            <label for="profile-name">Tên</label>
            <div class="input-wrap"><input id="profile-name" v-model="profileForm.name" type="text" autocomplete="name" /></div>
          </div>
          <div class="field">
            <label for="profile-username">Tên đăng nhập</label>
            <div class="input-wrap"><input id="profile-username" v-model="profileForm.username" type="text" autocomplete="username" /></div>
          </div>
          <div v-if="usernameChanged" class="field">
            <label for="profile-current-password">Mật khẩu hiện tại</label>
            <div class="input-wrap">
              <input id="profile-current-password" v-model="profileForm.currentPassword" type="password" autocomplete="current-password" />
            </div>
          </div>
          <div class="profile-actions">
            <button type="submit" class="btn btn-primary btn-sm" :disabled="profileSaving">
              {{ profileSaving ? 'Đang lưu...' : 'Lưu' }}
            </button>
            <button type="button" class="btn btn-secondary btn-sm" :disabled="profileSaving" @click="cancelEditProfile">Huỷ</button>
          </div>
        </form>
        <template v-else>
        <div class="bank-row"><span>Tên</span><strong>{{ user?.name }}</strong></div>
        <div class="bank-row"><span>Tên đăng nhập</span><strong>{{ user?.username }}</strong></div>
        </template>
        <template v-if="!auth.isAdmin && user?.package">
          <div class="bank-row">
            <span>Gói dịch vụ</span>
            <span class="pkg-value">
              <strong>{{ user.package.label }}</strong>
              <span class="chip" :class="user.package.isActive ? 'chip-accent' : 'chip-danger'">
                {{ user.package.isActive ? 'Đang hoạt động' : 'Hết hạn' }}
              </span>
            </span>
          </div>
          <div class="bank-row">
            <span>Hạn mức nhập</span>
            <strong v-if="user.stats?.total >= 999999999">Không giới hạn số lượng nhập</strong>
            <strong v-else-if="user.stats">Đã dùng {{ user.stats.used }} / {{ user.stats.total }}</strong>
          </div>
          <div class="bank-row">
            <span>Hết hạn</span>
            <strong>{{ user.package.expiresAt ? new Date(user.package.expiresAt).toLocaleDateString('vi-VN') : '-' }}</strong>
          </div>
        </template>
        <div class="bank-row">
          <span>Mật khẩu lớp hai</span>
          <span class="chip" :class="user?.hasSecondPassword ? 'chip-accent' : ''">
            {{ user?.hasSecondPassword ? 'Đã bật' : 'Chưa đặt' }}
          </span>
        </div>
        <div class="bank-row">
          <span>Mật khẩu xoá dữ liệu</span>
          <span class="chip" :class="user?.hasWipePassword ? 'chip-accent' : ''">
            {{ user?.hasWipePassword ? 'Đã bật' : 'Chưa đặt' }}
          </span>
        </div>
        <button type="button" class="btn btn-secondary logout-btn" @click="logoutNow">
          <AppIcon name="log-out" /> Đăng xuất
        </button>
      </div>

      <!-- Customer codes -->
      <div class="card">
        <h3 style="margin-top: 0">Mã ID kết bạn</h3>
        <p class="page-subtitle" style="margin-bottom: 12px">
          Tạo mã và gửi cho người khác để họ kết bạn với bạn.
        </p>
        <div v-if="codesError" class="alert alert-error">{{ codesError }}</div>
        <button class="btn btn-secondary" @click="generateCode" :disabled="generatingCode">
          {{ generatingCode ? 'Đang tạo...' : '+ Tạo mã mới' }}
        </button>
        <div v-if="codesLoading" style="margin-top: 12px">Đang tải...</div>
        <div v-else-if="codes.length === 0" class="page-subtitle" style="margin-top: 12px; margin-bottom: 0">
          Chưa có mã nào.
        </div>
        <div v-else class="code-list">
          <div v-for="c in codes" :key="c.id" class="code-item">
            <code class="code-value">{{ c.code }}</code>
            <div class="code-actions">
              <button class="btn btn-ghost btn-sm" @click="copyCode(c.code)">Sao chép</button>
              <button class="btn btn-ghost btn-sm" @click="deleteCode(c)">Xoá</button>
            </div>
          </div>
        </div>
      </div>

      </div>

      <div class="security-grid">
      <!-- Change password -->
      <form class="card sec-card sec-password" @submit.prevent="submitPasswordChange">
        <h3 style="margin-top: 0">Đổi mật khẩu đăng nhập</h3>
        <div v-if="pwError" class="alert alert-error">{{ pwError }}</div>
        <div v-if="pwSuccess" class="alert alert-success">{{ pwSuccess }}</div>
        <div class="field">
          <label>Mật khẩu hiện tại</label>
          <div class="input-wrap"><input v-model="pwForm.currentPassword" type="password" /></div>
        </div>
        <div class="field">
          <label>Mật khẩu mới (tối thiểu 6 ký tự)</label>
          <div class="input-wrap"><input v-model="pwForm.newPassword" type="password" /></div>
        </div>
        <div class="field">
          <label>Nhập lại mật khẩu mới</label>
          <div class="input-wrap"><input v-model="pwForm.confirmPassword" type="password" /></div>
        </div>
        <button type="submit" class="btn btn-primary sec-submit" :disabled="pwSubmitting">
          {{ pwSubmitting ? 'Đang lưu...' : 'Đổi mật khẩu' }}
        </button>
      </form>

      <!-- Second password -->
      <form class="card sec-card sec-second" @submit.prevent="submitSecondPassword">
        <h3 style="margin-top: 0">Mật khẩu lớp hai</h3>
        <p class="page-subtitle" style="margin-bottom: 12px">
          Lớp bảo mật thứ hai khi đăng nhập. {{ user?.hasSecondPassword ? 'Chỉ có thể đổi, không thể tắt.' : '' }}
        </p>
        <div v-if="secondError" class="alert alert-error">{{ secondError }}</div>
        <div v-if="secondSuccess" class="alert alert-success">{{ secondSuccess }}</div>
        <div class="field">
          <label>Mật khẩu hiện tại</label>
          <div class="input-wrap"><input v-model="secondForm.currentPassword" type="password" /></div>
        </div>
        <div class="field">
          <label>Mật khẩu lớp hai mới (tối thiểu 4 ký tự)</label>
          <div class="input-wrap"><input v-model="secondForm.secondPassword" type="password" /></div>
        </div>
        <button type="submit" class="btn btn-secondary sec-submit" :disabled="secondSubmitting">
          {{ secondSubmitting ? 'Đang lưu...' : user?.hasSecondPassword ? 'Đổi mật khẩu lớp hai' : 'Đặt mật khẩu lớp hai' }}
        </button>
      </form>

      <!-- Wipe password -->
      <form class="card sec-card sec-wipe" @submit.prevent="submitWipePassword">
        <h3 style="margin-top: 0">Mật khẩu xoá dữ liệu</h3>
        <p class="page-subtitle" style="margin-bottom: 12px">
          Nếu bạn đăng nhập bằng mật khẩu này thay vì mật khẩu chính, hệ thống sẽ hỏi xác nhận xoá toàn bộ dữ liệu thay vì đăng nhập bình thường. {{ user?.hasWipePassword ? 'Chỉ có thể đổi, không thể tắt.' : 'Tuỳ chọn, bỏ trống nếu không cần.' }}
        </p>
        <div v-if="wipeError" class="alert alert-error">{{ wipeError }}</div>
        <div v-if="wipeSuccess" class="alert alert-success">{{ wipeSuccess }}</div>
        <div class="field">
          <label>Mật khẩu hiện tại</label>
          <div class="input-wrap"><input v-model="wipeForm.currentPassword" type="password" /></div>
        </div>
        <div class="field">
          <label>Mật khẩu xoá dữ liệu (tối thiểu 4 ký tự)</label>
          <div class="input-wrap"><input v-model="wipeForm.wipePassword" type="password" /></div>
        </div>
        <button type="submit" class="btn btn-secondary sec-submit" :disabled="wipeSubmitting">
          {{ wipeSubmitting ? 'Đang lưu...' : user?.hasWipePassword ? 'Đổi mật khẩu xoá dữ liệu' : 'Đặt mật khẩu xoá dữ liệu' }}
        </button>
      </form>
      </div>

      <!-- Mã khôi phục + quyền riêng tư (components/RecoveryCodePanel, PrivacySettings) -->
      <div class="account-top">
        <RecoveryCodePanel v-if="!auth.isAdmin" />
        <PrivacySettings />
      </div>

      <!-- Delete data -->
      <div class="card danger-card">
        <h3 style="margin-top: 0; color: var(--danger-text)">Xoá toàn bộ dữ liệu</h3>
        <p class="page-subtitle" style="margin-bottom: 12px">
          Xoá toàn bộ số liệu đã nhập, tin nhắn phản hồi và lịch sử giao dịch. Tài khoản và gói dịch vụ của bạn vẫn giữ nguyên. Không thể hoàn tác.
        </p>
        <div v-if="deleteError" class="alert alert-error">{{ deleteError }}</div>
        <div v-if="deleteSuccess" class="alert alert-success">{{ deleteSuccess }}</div>
        <button class="btn btn-danger" @click="deleteAllData" :disabled="deleting">
          {{ deleting ? 'Đang xoá...' : 'Xoá toàn bộ dữ liệu' }}
        </button>
      </div>
    </template>
  </div>
</template>

<style scoped>
/* Layout: info + friend codes side by side, then the three security forms,
   then the danger zone. Section order is unchanged. */
.page {
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

.page .card {
  padding: 20px;
  border-radius: 14px;
}
.page .card h3 {
  margin-bottom: 12px !important;
  font-size: 17px;
}
.page .card .page-subtitle {
  font-size: 14px;
  line-height: 1.5;
  margin-bottom: 12px !important;
}

.account-top,
.security-grid {
  display: grid;
  gap: 16px;
  margin-bottom: 16px;
  align-items: start;
}
.account-top {
  grid-template-columns: repeat(2, minmax(0, 1fr));
}
.security-grid {
  grid-template-columns: repeat(3, minmax(0, 1fr));
  align-items: stretch;
}
.page .account-top > .card,
.page .security-grid > .card {
  margin-bottom: 0;
}

/* ---- Info card ---- */
.bank-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 8px 0;
  border-bottom: 1px solid var(--border);
  font-size: 14px;
}
.bank-row:last-child {
  border-bottom: none;
  padding-bottom: 0;
}
.bank-row span:first-child {
  color: var(--muted);
}

.card-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
}
.profile-form {
  max-width: 420px;
}
.profile-form .field {
  margin-bottom: 12px;
}
.profile-form .field input {
  height: 44px;
  padding: 0 14px;
  font-size: 15px;
  border-radius: 10px;
}
.profile-actions {
  display: flex;
  gap: 8px;
  margin-top: 4px;
}
.profile-actions .btn {
  min-height: 40px;
  padding: 0 18px;
  font-size: 14px;
  border-radius: 10px;
}

.logout-btn {
  display: none;
  width: 100%;
  min-height: 44px;
  margin-top: 12px;
  font-size: 15px;
  font-weight: 600;
  border-radius: 10px;
}
@media (max-width: 859px) {
  .logout-btn {
    display: inline-flex;
  }
}

.pkg-value {
  display: inline-flex;
  align-items: center;
  gap: 8px;
}

/* ---- Friend codes ---- */
.code-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
  margin-top: 12px;
}
.code-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  padding: 6px 6px 6px 12px;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 10px;
}
.code-value {
  font-size: 15px;
  font-weight: 700;
  letter-spacing: 0.05em;
}
.code-actions {
  display: flex;
  gap: 4px;
}

/* ---- Security forms ---- */
.sec-card {
  display: flex;
  flex-direction: column;
  border-top: 3px solid var(--border);
}
.sec-password {
  border-top-color: var(--primary);
}
.sec-second {
  border-top-color: var(--input-border);
}
/* security setting, not a destructive action: amber accent, never red */
.sec-wipe {
  border-top-color: var(--warning);
}

.sec-card .field {
  margin-bottom: 12px;
}
.sec-card .field label {
  font-size: 14px;
  font-weight: 700;
  color: var(--text-primary);
  margin-bottom: 6px;
}
.sec-card .field input {
  height: 44px;
  padding: 0 14px;
  font-size: 15px;
  border-radius: 10px;
  border: 1px solid var(--input-border);
}
.sec-card .field input:focus {
  outline: none;
  border-color: var(--primary);
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--primary) 35%, transparent);
}
.sec-card .alert {
  font-size: 14px;
  padding: 10px 14px;
  margin-bottom: 12px;
  border-radius: 10px;
}
.sec-submit {
  align-self: flex-start;
  margin-top: auto;
  min-height: 40px;
  padding: 0 18px;
  font-size: 14px;
  font-weight: 700;
  border-radius: 10px;
}

/* ---- Danger zone ---- */
.danger-card {
  border-color: var(--danger-text);
  border-left-width: 4px;
  background: color-mix(in srgb, var(--danger) 5%, var(--card));
}
.danger-card .btn-danger {
  min-height: 40px;
  padding: 0 18px;
  font-size: 14px;
  font-weight: 700;
  border-radius: 10px;
}

.page .btn:focus-visible {
  outline: 3px solid color-mix(in srgb, var(--primary) 55%, transparent);
  outline-offset: 2px;
}

/* ---- Responsive ---- */
@media (max-width: 1100px) {
  .security-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}
@media (max-width: 720px) {
  .page {
    padding: 24px 16px 96px;
  }
  .account-top,
  .security-grid {
    grid-template-columns: 1fr;
  }
}
</style>
