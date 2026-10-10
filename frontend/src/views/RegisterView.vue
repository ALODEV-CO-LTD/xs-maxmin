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
import RecoveryCodeDisplay from '../components/RecoveryCodeDisplay.vue'

const router = useRouter()
const auth = useAuthStore()

const stage = ref('account') // 'account' | 'security' | 'recovery_code' | 'second_password'
const recoveryCode = ref('') // shown once, then dropped
const loading = ref(false)
const error = ref('') // server / network errors only; field errors are inline

const name = ref('')
const username = ref('')
const password = ref('')
const confirmPassword = ref('') // client-side only, never sent to the API
const secondPassword = ref('')
const wipePassword = ref('')
const showWipePassword = ref(false)

const pendingToken = ref('')
const step2Password = ref('')

// Inline validation: a field shows its state once it has been blurred or the
// form has been submitted. Rules mirror the backend (routes/api/auth/register.dart).
// Any non-empty password is fine (up to bcrypt's 72 bytes) - see backend password_policy.dart.
const passwordProblem = (v) =>
  !v ? 'Vui lòng nhập mật khẩu' : new TextEncoder().encode(v).length > 72 ? 'Mật khẩu quá dài (tối đa 72 ký tự)' : ''
const touched = reactive({})
const submitted = ref(false)
const touch = (f) => (touched[f] = true)
const show = (f) => submitted.value || touched[f]

const fieldErrors = computed(() => ({
  name: name.value.trim() ? '' : 'Vui lòng nhập tên hiển thị',
  username: username.value.trim().length >= 3 ? '' : 'Tên đăng nhập phải có ít nhất 3 ký tự',
  password: passwordProblem(password.value),
  confirmPassword: !confirmPassword.value
    ? 'Vui lòng nhập lại mật khẩu'
    : confirmPassword.value !== password.value
      ? 'Mật khẩu xác nhận không khớp'
      : '',
  secondPassword: passwordProblem(secondPassword.value),
  wipePassword: !showWipePassword.value || !wipePassword.value
    ? ''
    : passwordProblem(wipePassword.value)
      ? passwordProblem(wipePassword.value)
      : wipePassword.value === password.value || wipePassword.value === secondPassword.value
        ? 'Mật khẩu xoá dữ liệu phải khác 2 mật khẩu còn lại'
        : '',
}))

// Show only actionable errors. Successful fields do not add extra text to the form.
function state(f) {
  if (f === 'wipePassword' && (!showWipePassword.value || !wipePassword.value)) return ''
  if (!show(f)) return ''
  return fieldErrors.value[f] ? 'error' : ''
}

const fieldIds = {
  name: 'name',
  username: 'reg-username',
  password: 'reg-password',
  confirmPassword: 'reg-confirm-password',
  secondPassword: 'reg-second-password',
  wipePassword: 'reg-wipe-password',
}

const accountFields = ['name', 'username', 'password', 'confirmPassword']
const securityFields = ['secondPassword', 'wipePassword']

async function focusFirstInvalid(fields) {
  const first = fields.find((f) => fieldErrors.value[f])
  if (!first) return
  await nextTick()
  document.getElementById(fieldIds[first])?.focus()
}

function goToSecurity() {
  submitted.value = true
  if (accountFields.some((f) => fieldErrors.value[f])) {
    focusFirstInvalid(accountFields)
    return
  }
  error.value = ''
  submitted.value = false
  stage.value = 'security'
}

function goToAccount() {
  error.value = ''
  submitted.value = false
  stage.value = 'account'
}

function toggleWipePassword() {
  showWipePassword.value = !showWipePassword.value
  if (!showWipePassword.value) wipePassword.value = ''
}

async function submitForm() {
  error.value = ''
  submitted.value = true
  if (accountFields.some((f) => fieldErrors.value[f])) {
    stage.value = 'account'
    focusFirstInvalid(accountFields)
    return
  }
  if (securityFields.some((f) => fieldErrors.value[f])) {
    focusFirstInvalid(securityFields)
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
      // Mã khôi phục is shown once; the user must confirm they saved it first.
      recoveryCode.value = res.recoveryCode || ''
      stage.value = recoveryCode.value ? 'recovery_code' : 'second_password'
    } else {
      error.value = 'Phản hồi không xác định từ máy chủ'
    }
  } catch (e) {
    error.value = e instanceof ApiError ? e.message : 'Đã xảy ra lỗi, vui lòng thử lại'
  } finally {
    loading.value = false
  }
}

function recoveryConfirmed() {
  recoveryCode.value = ''
  stage.value = 'second_password'
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
  <AuthLayout
    mode="register"
    :show-tabs="stage === 'account' || stage === 'security'"
    :title="stage === 'account' ? 'Tạo tài khoản' : stage === 'security' ? 'Bảo vệ tài khoản' : stage === 'recovery_code' ? 'Lưu mã khôi phục' : 'Xác minh lần cuối'"
    subtitle="Dùng thử miễn phí 30 ngày"
  >
    <form v-if="stage === 'account'" novalidate @submit.prevent="goToSecurity">
      <div class="step-progress" aria-label="Bước 1 trong 2">Bước 1/2 · Thông tin tài khoản</div>
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
            aria-describedby="msg-name"
            @blur="touch('name')"
          />
        </div>
        <p id="msg-name" class="field-msg" :class="state('name')" aria-live="polite">
          <template v-if="state('name') === 'error'"><AppIcon name="circle-alert" />{{ fieldErrors.name }}</template>
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
            aria-describedby="msg-username"
            @blur="touch('username')"
          />
        </div>
        <p id="msg-username" class="field-msg" :class="state('username')" aria-live="polite">
          <template v-if="state('username') === 'error'"><AppIcon name="circle-alert" />{{ fieldErrors.username }}</template>
        </p>
      </div>

      <div class="field">
        <label for="reg-password">Mật khẩu</label>
        <PasswordInput
          id="reg-password"
          v-model="password"
          autocomplete="new-password"
          placeholder="Tuỳ bạn đặt"
          :disabled="loading"
          :aria-invalid="state('password') === 'error'"
          aria-describedby="msg-password"
          @blur="touch('password')"
        />
        <p id="msg-password" class="field-msg" :class="state('password')" aria-live="polite">
          <template v-if="state('password') === 'error'"><AppIcon name="circle-alert" />{{ fieldErrors.password }}</template>
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
          aria-describedby="msg-confirm-password"
          @blur="touch('confirmPassword')"
        />
        <p id="msg-confirm-password" class="field-msg" :class="state('confirmPassword')" aria-live="polite">
          <template v-if="state('confirmPassword') === 'error'"><AppIcon name="circle-alert" />{{ fieldErrors.confirmPassword }}</template>
        </p>
      </div>

      <button type="submit" class="btn btn-primary btn-block">Tiếp tục</button>
    </form>

    <form v-else-if="stage === 'security'" novalidate @submit.prevent="submitForm">
      <div class="step-progress" aria-label="Bước 2 trong 2">Bước 2/2 · Bảo mật</div>
      <div v-if="error" class="alert alert-error" role="alert">{{ error }}</div>
      <p class="security-intro">Mật khẩu lớp hai được hỏi thêm mỗi lần đăng nhập. Bạn đặt gì tuỳ ý.</p>

      <div class="field">
        <label for="reg-second-password">Mật khẩu lớp hai <span class="required-note">Bắt buộc</span></label>
        <PasswordInput
          id="reg-second-password"
          v-model="secondPassword"
          autocomplete="off"
          placeholder="Tuỳ bạn đặt"
          :disabled="loading"
          :aria-invalid="state('secondPassword') === 'error'"
          aria-describedby="msg-second-password"
          @blur="touch('secondPassword')"
        />
        <p id="msg-second-password" class="field-msg" :class="state('secondPassword')" aria-live="polite">
          <template v-if="state('secondPassword') === 'error'"><AppIcon name="circle-alert" />{{ fieldErrors.secondPassword }}</template>
          <template v-else>Tuỳ bạn đặt, dùng ở bước đăng nhập thứ hai.</template>
        </p>
      </div>

      <button type="button" class="optional-toggle" :aria-expanded="showWipePassword" aria-controls="wipe-password-fields" @click="toggleWipePassword">
        <span><strong>Mật khẩu xoá dữ liệu</strong><small>Không bắt buộc · Có thể đặt sau trong Tài khoản</small></span>
        <span aria-hidden="true">{{ showWipePassword ? '−' : '+' }}</span>
      </button>
      <div v-if="showWipePassword" id="wipe-password-fields" class="optional-content">
        <p class="optional-desc">Nếu nhập mật khẩu này khi đăng nhập, ứng dụng sẽ mở bước xác nhận xoá dữ liệu vĩnh viễn. Mật khẩu này phải khác hai mật khẩu trên.</p>
        <div class="field">
          <label for="reg-wipe-password">Mật khẩu xoá dữ liệu</label>
          <PasswordInput
            id="reg-wipe-password"
            v-model="wipePassword"
            autocomplete="off"
            placeholder="Tuỳ bạn đặt"
            :disabled="loading"
            :aria-invalid="state('wipePassword') === 'error'"
            aria-describedby="msg-wipe-password"
            @blur="touch('wipePassword')"
          />
          <p id="msg-wipe-password" class="field-msg" :class="state('wipePassword')" aria-live="polite">
            <template v-if="state('wipePassword') === 'error'"><AppIcon name="circle-alert" />{{ fieldErrors.wipePassword }}</template>
          </p>
        </div>
      </div>

      <button type="submit" class="btn btn-primary btn-block" :disabled="loading" :aria-busy="loading">
        {{ loading ? 'Đang tạo tài khoản...' : 'Tạo tài khoản' }}
      </button>
      <button type="button" class="btn btn-ghost btn-block" :disabled="loading" @click="goToAccount">Quay lại</button>
    </form>

    <div v-else-if="stage === 'recovery_code'">
      <RecoveryCodeDisplay :code="recoveryCode" continue-text="Tiếp tục" @confirmed="recoveryConfirmed" />
    </div>

    <form v-else @submit.prevent="submitStep2">
      <div v-if="error" class="alert alert-error" role="alert">{{ error }}</div>
      <p class="security-intro">Nhập lại mật khẩu lớp hai bạn vừa đặt để hoàn tất đăng ký.</p>

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

<style scoped>
.step-progress {
  width: fit-content;
  margin: 0 0 18px;
  padding: 7px 11px;
  border-radius: 999px;
  color: var(--link);
  background: var(--primary-soft);
  font-size: 13px;
  font-weight: 700;
}

.security-intro {
  margin: 0 0 22px;
  color: var(--muted);
  line-height: 1.5;
}

.required-note {
  margin-left: 6px;
  color: var(--muted);
  font-size: 12px;
  font-weight: 400;
}

.optional-toggle {
  width: 100%;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-top: 22px;
  padding: 14px 16px;
  border: 1px solid var(--border);
  border-radius: 12px;
  color: var(--text);
  background: var(--surface);
  text-align: left;
  cursor: pointer;
}

.optional-toggle span:first-child { display: grid; gap: 3px; }
.optional-toggle strong { font-size: 14px; }
.optional-toggle small { color: var(--muted); font-size: 12px; }
.optional-toggle span:last-child { color: var(--link); font-size: 22px; line-height: 1; }
.optional-toggle:focus-visible { outline: 3px solid var(--focus); outline-offset: 2px; }

.optional-content {
  padding: 14px 16px 2px;
  border: 1px solid var(--border);
  border-top: 0;
  border-radius: 0 0 12px 12px;
}

.optional-desc {
  margin: 0 0 14px;
  color: var(--muted);
  font-size: 13px;
  line-height: 1.5;
}
</style>
