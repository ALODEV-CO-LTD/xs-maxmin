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
import { ref } from 'vue'
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
const stage = ref('credentials')
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
  if (recoverNewPassword.value.length < 6) {
    error.value = 'Mật khẩu mới phải có ít nhất 6 ký tự'
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
  <AuthLayout subtitle="Đăng nhập để nhập số liệu và quản lý gói dịch vụ">
    <form v-if="stage === 'credentials'" @submit.prevent="submitCredentials">
      <div v-if="error" class="alert alert-error" role="alert">{{ error }}</div>

      <div class="field has-icon">
        <label for="username">Tên đăng nhập</label>
        <div class="input-wrap">
          <svg class="input-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <circle cx="12" cy="8" r="5" />
            <path d="M20 21a8 8 0 0 0-16 0" />
          </svg>
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

      <div class="field has-icon">
        <label for="password">Mật khẩu</label>
        <div class="input-wrap">
          <svg class="input-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <rect width="18" height="11" x="3" y="11" rx="2" ry="2" />
            <path d="M7 11V7a5 5 0 0 1 10 0v4" />
          </svg>
          <input
            id="password"
            v-model="password"
            type="password"
            autocomplete="current-password"
            placeholder="Nhập mật khẩu"
            :disabled="loading"
            :aria-invalid="!!error"
          />
        </div>
      </div>

      <button type="submit" class="btn btn-primary btn-block" :disabled="loading" :aria-busy="loading">
        {{ loading ? 'Đang xử lý...' : 'Đăng nhập' }}
      </button>

      <p class="auth-footer">
        <a href="#" @click.prevent="startRecover">Quên mật khẩu?</a>
      </p>
      <p class="auth-footer">
        Chưa có tài khoản? <RouterLink to="/register">Đăng ký</RouterLink>
      </p>
    </form>

    <form v-else-if="stage === 'second_password'" @submit.prevent="submitSecondPassword">
      <div v-if="error" class="alert alert-error" role="alert">{{ error }}</div>
      <p style="color: var(--muted); font-size: 15px; margin-bottom: 24px">
        Tài khoản của bạn được bảo vệ bằng mật khẩu lớp hai. Vui lòng nhập để tiếp tục.
      </p>

      <div class="field has-icon">
        <label for="second-password">Mật khẩu lớp hai</label>
        <div class="input-wrap">
          <svg class="input-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <rect width="18" height="11" x="3" y="11" rx="2" ry="2" />
            <path d="M7 11V7a5 5 0 0 1 10 0v4" />
          </svg>
          <input
            id="second-password"
            v-model="secondPassword"
            type="password"
            autocomplete="off"
            placeholder="Nhập mật khẩu lớp hai"
            :disabled="loading"
            :aria-invalid="!!error"
          />
        </div>
      </div>

      <button type="submit" class="btn btn-primary btn-block" :disabled="loading" :aria-busy="loading">
        {{ loading ? 'Đang xử lý...' : 'Xác nhận' }}
      </button>
      <button type="button" class="btn btn-ghost btn-block" @click="backToCredentials">Quay lại</button>
    </form>

    <form v-else-if="stage === 'recover'" @submit.prevent="submitRecover">
      <div v-if="error" class="alert alert-error" role="alert">{{ error }}</div>
      <p style="color: var(--muted); font-size: 15px; margin-bottom: 24px">
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
        <PasswordInput id="rec-new" v-model="recoverNewPassword" autocomplete="new-password" placeholder="Ít nhất 6 ký tự" :disabled="loading" />
      </div>
      <div class="field">
        <label for="rec-confirm">Nhập lại mật khẩu mới</label>
        <PasswordInput id="rec-confirm" v-model="recoverConfirm" autocomplete="new-password" :disabled="loading" />
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
        Cảnh báo: mật khẩu bạn vừa nhập là <strong>mật khẩu xoá dữ liệu</strong>. Nếu tiếp tục, TOÀN BỘ số liệu, tin nhắn
        và lịch sử giao dịch của tài khoản này sẽ bị xoá <strong>vĩnh viễn và không thể khôi phục</strong>. Thao tác này
        sẽ không đăng nhập bạn vào tài khoản.
      </div>
      <div v-if="error" class="alert alert-error" role="alert">{{ error }}</div>

      <label style="display: flex; gap: 8px; align-items: flex-start; font-size: 14px; margin-bottom: 16px; cursor: pointer">
        <input v-model="wipeAck" type="checkbox" style="margin-top: 3px" />
        <span>Tôi hiểu rằng thao tác này sẽ xoá vĩnh viễn toàn bộ dữ liệu của tài khoản này.</span>
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
