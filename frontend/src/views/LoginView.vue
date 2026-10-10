<!--
  /login - implements all 3 stages POST /api/auth/login can return:
    'done'                       -> store token+role, redirect to dashboard
    'second_password_required'   -> ask second password, POST /api/auth/step2
                                     (which can itself return 'done' or
                                     'wipe_confirmation_required')
    'recover' / 'recover_code'   -> "Quên mật khẩu": username + mã khôi phục +
                                     new password (POST /api/auth/recover), then
                                     the NEW code is shown once
    'wipe_confirmation_required' -> explicit destructive-confirm dialog,
                                     only then POST /api/auth/confirm-wipe
-->
<script setup>
import { onMounted, ref } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { api, ApiError } from '../api'
import { useAuthStore } from '../stores/auth'
import AuthLayout from '../components/AuthLayout.vue'
import PasswordInput from '../components/PasswordInput.vue'
import RecoveryCodeDisplay from '../components/RecoveryCodeDisplay.vue'

const router = useRouter()
const route = useRoute()
const auth = useAuthStore()

// 'credentials' | 'second_password' | 'wipe_confirm' | 'wipe_done' | 'recover' | 'recover_code'
// | 'help_request' | 'help_sent' | 'ticket'  (admin-assisted recovery, A06)
const stage = ref('credentials')
// Cursor starts in the username box.
onMounted(() => document.getElementById('username')?.focus({ preventScroll: true }))
const loading = ref(false)
const error = ref('')

const username = ref('')
const password = ref('')
const secondPassword = ref('')
const pendingToken = ref('')
const wipeToken = ref('')
const wipeAck = ref(false)

function goAfterLogin() {
  const redirect = typeof route.query.redirect === 'string' ? route.query.redirect : '/'
  router.push(redirect)
}

async function submitCredentials() {
  error.value = ''
  if (!username.value.trim() || !password.value) {
    error.value = 'Vui lòng nhập tên đăng nhập và mật khẩu'
    return
  }
  loading.value = true
  try {
    const res = await api.post('/auth/login', {
      username: username.value.trim(),
      password: password.value,
    })
    handleStage(res)
  } catch (e) {
    error.value = e instanceof ApiError ? e.message : 'Đã xảy ra lỗi, vui lòng thử lại'
  } finally {
    loading.value = false
  }
}

async function submitSecondPassword() {
  error.value = ''
  if (!secondPassword.value) {
    error.value = 'Vui lòng nhập mật khẩu lớp hai'
    return
  }
  loading.value = true
  try {
    const res = await api.post('/auth/step2', {
      pendingToken: pendingToken.value,
      password: secondPassword.value,
    })
    handleStage(res)
  } catch (e) {
    error.value = e instanceof ApiError ? e.message : 'Đã xảy ra lỗi, vui lòng thử lại'
  } finally {
    loading.value = false
  }
}

function handleStage(res) {
  // Login step 1 success is {stage:'done', token, role}; step2 success is
  // just {token, role} with no 'stage' field at all - treat either as done.
  if (res.stage === 'done' || res.token) {
    auth.login(res.token, res.role)
    goAfterLogin()
    return
  }
  if (res.stage === 'second_password_required') {
    pendingToken.value = res.pendingToken
    secondPassword.value = ''
    stage.value = 'second_password'
    return
  }
  if (res.stage === 'wipe_confirmation_required') {
    wipeToken.value = res.wipeToken
    wipeAck.value = false
    stage.value = 'wipe_confirm'
    return
  }
  error.value = 'Phản hồi không xác định từ máy chủ'
}

async function confirmWipe() {
  if (!wipeAck.value) return
  error.value = ''
  loading.value = true
  try {
    await api.post('/auth/confirm-wipe', { wipeToken: wipeToken.value })
    stage.value = 'wipe_done'
  } catch (e) {
    error.value = e instanceof ApiError ? e.message : 'Đã xảy ra lỗi, vui lòng thử lại'
  } finally {
    loading.value = false
  }
}

const recoverUsername = ref('')
const recoverCode = ref('')
const recoverNewPassword = ref('')
const recoverConfirm = ref('')
const newRecoveryCode = ref('')

function startRecover() {
  error.value = ''
  recoverUsername.value = username.value.trim()
  recoverCode.value = ''
  recoverNewPassword.value = ''
  recoverConfirm.value = ''
  stage.value = 'recover'
}

async function submitRecover() {
  error.value = ''
  if (!recoverUsername.value.trim() || !recoverCode.value.trim()) {
    error.value = 'Vui lòng nhập tên đăng nhập và mã khôi phục'
    return
  }
  if (!recoverNewPassword.value) {
    error.value = 'Vui lòng nhập mật khẩu mới'
    return
  }
  if (recoverNewPassword.value !== recoverConfirm.value) {
    error.value = 'Mật khẩu nhập lại không khớp'
    return
  }
  loading.value = true
  try {
    const res = await api.post('/auth/recover', {
      username: recoverUsername.value.trim(),
      recoveryCode: recoverCode.value.trim(),
      newPassword: recoverNewPassword.value,
    })
    newRecoveryCode.value = res.recoveryCode
    recoverCode.value = ''
    recoverNewPassword.value = ''
    recoverConfirm.value = ''
    stage.value = 'recover_code'
  } catch (e) {
    error.value = e instanceof ApiError ? e.message : 'Đã xảy ra lỗi, vui lòng thử lại'
  } finally {
    loading.value = false
  }
}

// ---- Admin-assisted recovery (A06): lost the recovery code too ----
const helpNote = ref('')
const helpMessage = ref('')
const ticketCode = ref('')

function startHelp() {
  error.value = ''
  recoverUsername.value = recoverUsername.value || username.value.trim()
  helpNote.value = ''
  stage.value = 'help_request'
}

async function submitHelp() {
  error.value = ''
  if (!recoverUsername.value.trim()) {
    error.value = 'Vui lòng nhập tên đăng nhập'
    return
  }
  loading.value = true
  try {
    const res = await api.post('/auth/recovery-request', {
      username: recoverUsername.value.trim(),
      note: helpNote.value.trim(),
    })
    helpMessage.value = res.message
    stage.value = 'help_sent'
  } catch (e) {
    error.value = e instanceof ApiError ? e.message : 'Đã xảy ra lỗi, vui lòng thử lại'
  } finally {
    loading.value = false
  }
}

function startTicket() {
  error.value = ''
  recoverUsername.value = recoverUsername.value || username.value.trim()
  ticketCode.value = ''
  recoverNewPassword.value = ''
  recoverConfirm.value = ''
  stage.value = 'ticket'
}

async function submitTicket() {
  error.value = ''
  if (!recoverUsername.value.trim() || !ticketCode.value.trim()) {
    error.value = 'Vui lòng nhập tên đăng nhập và mã hỗ trợ'
    return
  }
  if (!recoverNewPassword.value) {
    error.value = 'Vui lòng nhập mật khẩu mới'
    return
  }
  if (recoverNewPassword.value !== recoverConfirm.value) {
    error.value = 'Mật khẩu nhập lại không khớp'
    return
  }
  loading.value = true
  try {
    const res = await api.post('/auth/recover-with-ticket', {
      username: recoverUsername.value.trim(),
      ticket: ticketCode.value.trim(),
      newPassword: recoverNewPassword.value,
    })
    newRecoveryCode.value = res.recoveryCode
    ticketCode.value = ''
    recoverNewPassword.value = ''
    recoverConfirm.value = ''
    stage.value = 'recover_code'
  } catch (e) {
    error.value = e instanceof ApiError ? e.message : 'Đã xảy ra lỗi, vui lòng thử lại'
  } finally {
    loading.value = false
  }
}

function recoverDone() {
  newRecoveryCode.value = ''
  backToCredentials()
}

function backToCredentials() {
  stage.value = 'credentials'
  password.value = ''
  secondPassword.value = ''
  error.value = ''
}
</script>

<template>
  <AuthLayout
    mode="login"
    :show-tabs="stage === 'credentials'"
    :title="stage === 'credentials' ? 'Chào mừng trở lại' : stage === 'second_password' ? 'Xác minh tài khoản' : stage === 'recover' ? 'Khôi phục mật khẩu' : stage === 'help_request' || stage === 'help_sent' ? 'Nhờ Admin hỗ trợ' : stage === 'ticket' ? 'Nhập mã hỗ trợ' : stage === 'recover_code' ? 'Lưu mã khôi phục mới' : stage === 'wipe_confirm' ? 'Xác nhận xoá dữ liệu' : 'Hoàn tất'"
    subtitle="Dữ liệu của bạn, trong tầm kiểm soát"
  >
    <form v-if="stage === 'credentials'" @submit.prevent="submitCredentials">
      <div v-if="error" class="alert alert-error" role="alert">{{ error }}</div>

      <div class="field">
        <label for="username">Tên đăng nhập</label>
        <div class="input-wrap">
          <input
            id="username"
            v-model="username"
            type="text"
            autocomplete="username"
            placeholder="Nhập tên đăng nhập"
            :disabled="loading"
            :aria-invalid="!!error"
          />
        </div>
      </div>

      <div class="field">
        <label for="password">Mật khẩu</label>
        <PasswordInput
          id="password"
          v-model="password"
          autocomplete="current-password"
          placeholder="Nhập mật khẩu"
          :disabled="loading"
          :aria-invalid="!!error"
        />
      </div>

      <div class="auth-link-row"><button type="button" class="auth-link-button" @click="startRecover">Quên mật khẩu?</button></div>

      <button type="submit" class="btn btn-primary btn-block" :disabled="loading" :aria-busy="loading">
        {{ loading ? 'Đang xử lý...' : 'Đăng nhập' }}
      </button>

    </form>

    <form v-else-if="stage === 'second_password'" @submit.prevent="submitSecondPassword">
      <div v-if="error" class="alert alert-error" role="alert">{{ error }}</div>
      <p class="auth-stage-description">Nhập mật khẩu lớp hai để tiếp tục.</p>

      <div class="field">
        <label for="second-password">Mật khẩu lớp hai</label>
        <PasswordInput
          id="second-password"
          v-model="secondPassword"
          autocomplete="off"
          placeholder="Nhập mật khẩu lớp hai"
          :disabled="loading"
          :aria-invalid="!!error"
        />
      </div>

      <button type="submit" class="btn btn-primary btn-block" :disabled="loading" :aria-busy="loading">
        {{ loading ? 'Đang xử lý...' : 'Xác nhận' }}
      </button>
      <button type="button" class="btn btn-ghost btn-block" @click="backToCredentials">Quay lại</button>
    </form>

    <form v-else-if="stage === 'recover'" @submit.prevent="submitRecover">
      <div v-if="error" class="alert alert-error" role="alert">{{ error }}</div>
      <p class="auth-stage-description">
        Nhập tên đăng nhập và mã khôi phục để đặt mật khẩu mới. Sau khi đặt lại, bạn sẽ nhận một mã khôi phục mới (mã cũ
        không dùng được nữa).
      </p>
      <div class="field">
        <label for="rec-username">Tên đăng nhập</label>
        <div class="input-wrap">
          <input id="rec-username" v-model="recoverUsername" type="text" autocomplete="username" :disabled="loading" />
        </div>
      </div>
      <div class="field">
        <label for="rec-code">Mã khôi phục</label>
        <div class="input-wrap">
          <input id="rec-code" v-model="recoverCode" type="text" autocomplete="off" placeholder="XXXX-XXXX-XXXX-XXXX" :disabled="loading" />
        </div>
      </div>
      <div class="field">
        <label for="rec-new">Mật khẩu mới</label>
        <PasswordInput id="rec-new" v-model="recoverNewPassword" autocomplete="new-password" placeholder="Tuỳ bạn đặt" :disabled="loading" />
      </div>
      <div class="field">
        <label for="rec-confirm">Nhập lại mật khẩu mới</label>
        <PasswordInput id="rec-confirm" v-model="recoverConfirm" autocomplete="new-password" :disabled="loading" />
      </div>
      <button type="submit" class="btn btn-primary btn-block" :disabled="loading" :aria-busy="loading">
        {{ loading ? 'Đang xử lý...' : 'Đặt lại mật khẩu' }}
      </button>
      <div class="auth-link-row"><button type="button" class="auth-link-button" @click="startHelp">Mất cả mã khôi phục? Nhờ Admin hỗ trợ</button></div>
      <div class="auth-link-row"><button type="button" class="auth-link-button" @click="startTicket">Tôi đã có mã hỗ trợ từ Admin</button></div>
      <button type="button" class="btn btn-ghost btn-block" @click="backToCredentials">Quay lại đăng nhập</button>
    </form>

    <form v-else-if="stage === 'help_request'" @submit.prevent="submitHelp">
      <div v-if="error" class="alert alert-error" role="alert">{{ error }}</div>
      <p class="auth-stage-description">
        Gửi yêu cầu để quản trị viên hỗ trợ. Admin sẽ xác minh bạn là chủ tài khoản qua kênh hỗ trợ (ví dụ số điện thoại hoặc tin nhắn đã đăng ký);
        khi được duyệt bạn nhận một <strong>mã hỗ trợ dùng một lần, hạn 24 giờ</strong> để tự đặt mật khẩu mới. Admin không biết mật khẩu của bạn.
      </p>
      <div class="field">
        <label for="help-username">Tên đăng nhập</label>
        <div class="input-wrap">
          <input id="help-username" v-model="recoverUsername" type="text" autocomplete="username" :disabled="loading" />
        </div>
      </div>
      <div class="field">
        <label for="help-note">Thông tin giúp Admin xác minh (không bắt buộc)</label>
        <div class="input-wrap">
          <input id="help-note" v-model="helpNote" type="text" maxlength="300" placeholder="Ví dụ: tên, số điện thoại liên hệ" :disabled="loading" />
        </div>
      </div>
      <button type="submit" class="btn btn-primary btn-block" :disabled="loading" :aria-busy="loading">
        {{ loading ? 'Đang gửi...' : 'Gửi yêu cầu' }}
      </button>
      <button type="button" class="btn btn-ghost btn-block" @click="stage = 'recover'">Quay lại</button>
    </form>

    <div v-else-if="stage === 'help_sent'">
      <div class="alert alert-success">{{ helpMessage }}</div>
      <button type="button" class="btn btn-primary btn-block" @click="startTicket">Tôi đã có mã hỗ trợ</button>
      <button type="button" class="btn btn-ghost btn-block" @click="backToCredentials">Về trang đăng nhập</button>
    </div>

    <form v-else-if="stage === 'ticket'" @submit.prevent="submitTicket">
      <div v-if="error" class="alert alert-error" role="alert">{{ error }}</div>
      <p class="auth-stage-description">Nhập mã hỗ trợ Admin đã gửi cho bạn và đặt mật khẩu mới. Mã chỉ dùng được một lần.</p>
      <div class="field">
        <label for="tk-username">Tên đăng nhập</label>
        <div class="input-wrap">
          <input id="tk-username" v-model="recoverUsername" type="text" autocomplete="username" :disabled="loading" />
        </div>
      </div>
      <div class="field">
        <label for="tk-code">Mã hỗ trợ</label>
        <div class="input-wrap">
          <input id="tk-code" v-model="ticketCode" type="text" autocomplete="off" placeholder="XXXX-XXXX-XXXX-XXXX" :disabled="loading" />
        </div>
      </div>
      <div class="field">
        <label for="tk-new">Mật khẩu mới</label>
        <PasswordInput id="tk-new" v-model="recoverNewPassword" autocomplete="new-password" placeholder="Tuỳ bạn đặt" :disabled="loading" />
      </div>
      <div class="field">
        <label for="tk-confirm">Nhập lại mật khẩu mới</label>
        <PasswordInput id="tk-confirm" v-model="recoverConfirm" autocomplete="new-password" :disabled="loading" />
      </div>
      <button type="submit" class="btn btn-primary btn-block" :disabled="loading" :aria-busy="loading">
        {{ loading ? 'Đang xử lý...' : 'Đặt lại mật khẩu' }}
      </button>
      <button type="button" class="btn btn-ghost btn-block" @click="backToCredentials">Quay lại đăng nhập</button>
    </form>

    <div v-else-if="stage === 'recover_code'">
      <div class="alert alert-success">Đã đặt lại mật khẩu. Đây là mã khôi phục mới của bạn.</div>
      <RecoveryCodeDisplay :code="newRecoveryCode" continue-text="Về trang đăng nhập" @confirmed="recoverDone" />
    </div>

    <div v-else-if="stage === 'wipe_confirm'">
      <div class="alert alert-warning">
        Cảnh báo: mật khẩu bạn vừa nhập là <strong>mật khẩu xoá dữ liệu</strong>. Nếu tiếp tục, số liệu đã nhập, danh sách khách hàng, mẫu cú pháp, lịch xoá tự động,
        nhật ký cuộc gọi, tin nhắn phản hồi với Admin, lịch sử giao dịch và yêu cầu thanh toán chưa duyệt của tài khoản này
        sẽ bị xoá <strong>vĩnh viễn và không thể khôi phục</strong>. Tài khoản, bạn bè và tin nhắn với bạn bè được giữ nguyên. Thao tác này
        sẽ không đăng nhập bạn vào tài khoản.
      </div>
      <div v-if="error" class="alert alert-error" role="alert">{{ error }}</div>

      <label style="display: flex; gap: 8px; align-items: flex-start; font-size: 14px; margin-bottom: 16px; cursor: pointer">
        <input v-model="wipeAck" type="checkbox" style="margin-top: 3px" />
        <span>Tôi hiểu rằng thao tác này sẽ xoá vĩnh viễn các dữ liệu nêu trên của tài khoản này.</span>
      </label>

      <button type="button" class="btn btn-danger btn-block" :disabled="!wipeAck || loading" @click="confirmWipe">
        {{ loading ? 'Đang xử lý...' : 'Xác nhận xoá dữ liệu' }}
      </button>
      <button type="button" class="btn btn-ghost btn-block" @click="backToCredentials">Huỷ, quay lại đăng nhập</button>
    </div>

    <div v-else-if="stage === 'wipe_done'">
      <div class="alert alert-success">Dữ liệu của tài khoản đã được xoá. Bạn có thể đăng nhập lại bình thường.</div>
      <button type="button" class="btn btn-primary btn-block" @click="backToCredentials">Về trang đăng nhập</button>
    </div>
  </AuthLayout>
</template>

<style scoped>
.auth-link-row {
  display: flex;
  justify-content: flex-end;
  margin: -4px 0 8px;
}

.auth-link-button {
  border: 0;
  padding: 8px 0;
  background: transparent;
  color: var(--link);
  font: inherit;
  font-size: 14px;
  font-weight: 700;
  cursor: pointer;
}

.auth-link-button:focus-visible {
  outline: 3px solid var(--focus);
  outline-offset: 2px;
}

.auth-stage-description {
  margin: 0 0 22px;
  color: var(--muted);
  font-size: 15px;
  line-height: 1.5;
}
</style>
