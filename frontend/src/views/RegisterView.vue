<!--
  /register - POST /api/auth/register always requires setting a second
  password (>=4 chars, different from password), plus an optional wipe
  password (>=4 chars, different from both). The backend always responds
  'second_password_required' (registration never skips step2), so this
  view re-prompts for the just-set second password and calls
  POST /api/auth/step2 exactly like LoginView does.
-->
<script setup>
import { computed, nextTick, reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { api, ApiError } from '../api'
import { useAuthStore } from '../stores/auth'
import AuthLayout from '../components/AuthLayout.vue'
import AppIcon from '../components/AppIcon.vue'
import PasswordInput from '../components/PasswordInput.vue'

const router = useRouter()
const auth = useAuthStore()

const stage = ref('form') // 'form' | 'second_password'
const loading = ref(false)
const error = ref('') // server / network errors only; field errors are inline

const name = ref('')
const username = ref('')
const password = ref('')
const confirmPassword = ref('') // client-side only, never sent to the API
const secondPassword = ref('')
const wipePassword = ref('')

const pendingToken = ref('')
const step2Password = ref('')

// Inline validation: a field shows its state once it has been blurred or the
// form has been submitted. Rules mirror the backend (routes/api/auth/register.dart).
const touched = reactive({})
const submitted = ref(false)
const touch = (f) => (touched[f] = true)
const show = (f) => submitted.value || touched[f]

const fieldErrors = computed(() => ({
  name: name.value.trim() ? '' : 'Vui lòng nhập tên hiển thị',
  username: username.value.trim().length >= 3 ? '' : 'Tên đăng nhập phải có ít nhất 3 ký tự',
  password: password.value.length >= 6 ? '' : 'Mật khẩu phải có ít nhất 6 ký tự',
  confirmPassword: !confirmPassword.value
    ? 'Vui lòng nhập lại mật khẩu'
    : confirmPassword.value !== password.value
      ? 'Mật khẩu xác nhận không khớp'
      : '',
  secondPassword:
    secondPassword.value.length < 4
      ? 'Mật khẩu lớp hai phải có ít nhất 4 ký tự'
      : secondPassword.value === password.value
        ? 'Mật khẩu lớp hai phải khác mật khẩu đăng nhập'
        : '',
  wipePassword: !wipePassword.value
    ? ''
    : wipePassword.value.length < 4
      ? 'Mật khẩu xoá dữ liệu phải có ít nhất 4 ký tự'
      : wipePassword.value === password.value || wipePassword.value === secondPassword.value
        ? 'Mật khẩu xoá dữ liệu phải khác 2 mật khẩu còn lại'
        : '',
}))

const okMessages = {
  name: 'Hợp lệ',
  username: 'Tên đăng nhập hợp lệ',
  password: 'Mật khẩu hợp lệ',
  confirmPassword: 'Mật khẩu khớp',
  secondPassword: 'Mật khẩu lớp hai hợp lệ',
  wipePassword: 'Mật khẩu xoá dữ liệu hợp lệ',
}

// 'error' | 'ok' | '' (nothing to show yet, or an optional field left empty)
function state(f) {
  if (f === 'wipePassword' && !wipePassword.value) return ''
  if (!show(f)) return ''
  return fieldErrors.value[f] ? 'error' : 'ok'
}

const fieldIds = {
  name: 'name',
  username: 'reg-username',
  password: 'reg-password',
  confirmPassword: 'reg-confirm-password',
  secondPassword: 'reg-second-password',
  wipePassword: 'reg-wipe-password',
}

async function focusFirstInvalid() {
  const first = Object.keys(fieldIds).find((f) => fieldErrors.value[f])
  if (!first) return
  await nextTick()
  document.getElementById(fieldIds[first])?.focus()
}

async function submitForm() {
  error.value = ''
  submitted.value = true
  if (Object.values(fieldErrors.value).some(Boolean)) {
    focusFirstInvalid()
    return
  }
  loading.value = true
  try {
    const res = await api.post('/auth/register', {
      name: name.value.trim(),
      username: username.value.trim(),
      password: password.value,
      secondPassword: secondPassword.value,
      wipePassword: wipePassword.value || undefined,
    })
    if (res.stage === 'second_password_required') {
      pendingToken.value = res.pendingToken
      step2Password.value = ''
      stage.value = 'second_password'
    } else {
      error.value = 'Phản hồi không xác định từ máy chủ'
    }
  } catch (e) {
    error.value = e instanceof ApiError ? e.message : 'Đã xảy ra lỗi, vui lòng thử lại'
  } finally {
    loading.value = false
  }
}

async function submitStep2() {
  error.value = ''
  if (!step2Password.value) {
    error.value = 'Vui lòng nhập mật khẩu lớp hai vừa đặt'
    return
  }
  loading.value = true
  try {
    const res = await api.post('/auth/step2', {
      pendingToken: pendingToken.value,
      password: step2Password.value,
    })
    if (res.token) {
      auth.login(res.token, res.role)
      router.push('/')
    } else {
      // Freshly-registered accounts can't yet have a wipe-password matching
      // this input, but handle it defensively in case one was configured.
      error.value = res.stage === 'wipe_confirmation_required'
        ? 'Mật khẩu không khớp với mật khẩu lớp hai vừa đặt'
        : 'Phản hồi không xác định từ máy chủ'
    }
  } catch (e) {
    error.value = e instanceof ApiError ? e.message : 'Đã xảy ra lỗi, vui lòng thử lại'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <AuthLayout subtitle="Tạo tài khoản mới để bắt đầu sử dụng XOSO">
    <form v-if="stage === 'form'" novalidate @submit.prevent="submitForm">
      <div v-if="error" class="alert alert-error" role="alert">{{ error }}</div>

      <div class="field">
        <label for="name">Tên hiển thị</label>
        <div class="input-wrap">
          <input
            id="name"
            v-model="name"
            type="text"
            autocomplete="name"
            placeholder="Nguyễn Văn A"
            :disabled="loading"
            :aria-invalid="state('name') === 'error'"
            :data-valid="state('name') === 'ok'"
            aria-describedby="msg-name"
            @blur="touch('name')"
          />
        </div>
        <p id="msg-name" class="field-msg" :class="state('name')" aria-live="polite">
          <template v-if="state('name') === 'error'"><AppIcon name="circle-alert" />{{ fieldErrors.name }}</template>
          <template v-else-if="state('name') === 'ok'"><AppIcon name="circle-check" />{{ okMessages.name }}</template>
        </p>
      </div>

      <div class="field">
        <label for="reg-username">Tên đăng nhập</label>
        <div class="input-wrap">
          <input
            id="reg-username"
            v-model="username"
            type="text"
            autocomplete="username"
            placeholder="Ít nhất 3 ký tự"
            :disabled="loading"
            :aria-invalid="state('username') === 'error'"
            :data-valid="state('username') === 'ok'"
            aria-describedby="msg-username"
            @blur="touch('username')"
          />
        </div>
        <p id="msg-username" class="field-msg" :class="state('username')" aria-live="polite">
          <template v-if="state('username') === 'error'"><AppIcon name="circle-alert" />{{ fieldErrors.username }}</template>
          <template v-else-if="state('username') === 'ok'"><AppIcon name="circle-check" />{{ okMessages.username }}</template>
        </p>
      </div>

      <div class="field">
        <label for="reg-password">Mật khẩu</label>
        <PasswordInput
          id="reg-password"
          v-model="password"
          autocomplete="new-password"
          placeholder="Ít nhất 6 ký tự"
          :disabled="loading"
          :aria-invalid="state('password') === 'error'"
          :data-valid="state('password') === 'ok'"
          aria-describedby="msg-password"
          @blur="touch('password')"
        />
        <p id="msg-password" class="field-msg" :class="state('password')" aria-live="polite">
          <template v-if="state('password') === 'error'"><AppIcon name="circle-alert" />{{ fieldErrors.password }}</template>
          <template v-else-if="state('password') === 'ok'"><AppIcon name="circle-check" />{{ okMessages.password }}</template>
        </p>
      </div>

      <div class="field">
        <label for="reg-confirm-password">Xác nhận mật khẩu</label>
        <PasswordInput
          id="reg-confirm-password"
          v-model="confirmPassword"
          autocomplete="new-password"
          placeholder="Nhập lại mật khẩu"
          :disabled="loading"
          :aria-invalid="state('confirmPassword') === 'error'"
          :data-valid="state('confirmPassword') === 'ok'"
          aria-describedby="msg-confirm-password"
          @blur="touch('confirmPassword')"
        />
        <p id="msg-confirm-password" class="field-msg" :class="state('confirmPassword')" aria-live="polite">
          <template v-if="state('confirmPassword') === 'error'"><AppIcon name="circle-alert" />{{ fieldErrors.confirmPassword }}</template>
          <template v-else-if="state('confirmPassword') === 'ok'"><AppIcon name="circle-check" />{{ okMessages.confirmPassword }}</template>
        </p>
      </div>

      <div class="field">
        <label for="reg-second-password">Mật khẩu lớp hai</label>
        <PasswordInput
          id="reg-second-password"
          v-model="secondPassword"
          autocomplete="off"
          placeholder="Ít nhất 4 ký tự"
          :disabled="loading"
          :aria-invalid="state('secondPassword') === 'error'"
          :data-valid="state('secondPassword') === 'ok'"
          aria-describedby="msg-second-password"
          @blur="touch('secondPassword')"
        />
        <p id="msg-second-password" class="field-msg" :class="state('secondPassword')" aria-live="polite">
          <template v-if="state('secondPassword') === 'error'"><AppIcon name="circle-alert" />{{ fieldErrors.secondPassword }}</template>
          <template v-else-if="state('secondPassword') === 'ok'"><AppIcon name="circle-check" />{{ okMessages.secondPassword }}</template>
          <template v-else>Phải khác mật khẩu đăng nhập. Được yêu cầu thêm mỗi lần đăng nhập để bảo vệ tài khoản.</template>
        </p>
      </div>

      <section class="optional-box" aria-labelledby="wipe-title">
        <h2 id="wipe-title" class="optional-title">
          Mật khẩu xoá dữ liệu
          <span class="optional-badge">Không bắt buộc</span>
        </h2>
        <p class="optional-desc">
          Nếu đặt, khi nhập mật khẩu này ở màn hình đăng nhập, bạn sẽ được đưa tới bước xoá toàn bộ dữ liệu tài khoản.
          Bạn cũng có thể đặt sau trong mục Tài khoản.
        </p>
        <p class="optional-warn">
          <AppIcon name="triangle-alert" />
          <span>Cảnh báo: xoá dữ liệu là vĩnh viễn và không thể khôi phục. Phải khác 2 mật khẩu còn lại.</span>
        </p>
        <div class="field">
          <label for="reg-wipe-password">Nhập mật khẩu xoá dữ liệu</label>
          <PasswordInput
            id="reg-wipe-password"
            v-model="wipePassword"
            autocomplete="off"
            placeholder="Để trống nếu không cần"
            :disabled="loading"
            :aria-invalid="state('wipePassword') === 'error'"
            :data-valid="state('wipePassword') === 'ok'"
            aria-describedby="msg-wipe-password"
            @blur="touch('wipePassword')"
          />
          <p id="msg-wipe-password" class="field-msg" :class="state('wipePassword')" aria-live="polite">
            <template v-if="state('wipePassword') === 'error'"><AppIcon name="circle-alert" />{{ fieldErrors.wipePassword }}</template>
            <template v-else-if="state('wipePassword') === 'ok'"><AppIcon name="circle-check" />{{ okMessages.wipePassword }}</template>
          </p>
        </div>
      </section>

      <button type="submit" class="btn btn-primary btn-block" :disabled="loading" :aria-busy="loading">
        {{ loading ? 'Đang xử lý...' : 'Đăng ký' }}
      </button>

      <p class="auth-footer">
        Đã có tài khoản? <RouterLink to="/login">Đăng nhập</RouterLink>
      </p>
    </form>

    <form v-else @submit.prevent="submitStep2">
      <div v-if="error" class="alert alert-error" role="alert">{{ error }}</div>
      <p style="color: var(--muted); font-size: 15px; margin-bottom: 24px">
        Vui lòng nhập lại mật khẩu lớp hai bạn vừa đặt để hoàn tất đăng ký.
      </p>

      <div class="field">
        <label for="step2-password">Mật khẩu lớp hai</label>
        <PasswordInput
          id="step2-password"
          v-model="step2Password"
          autocomplete="off"
          placeholder="Nhập mật khẩu lớp hai"
          :disabled="loading"
          :aria-invalid="!!error"
        />
      </div>

      <button type="submit" class="btn btn-primary btn-block" :disabled="loading" :aria-busy="loading">
        {{ loading ? 'Đang xử lý...' : 'Hoàn tất đăng ký' }}
      </button>
    </form>
  </AuthLayout>
</template>
