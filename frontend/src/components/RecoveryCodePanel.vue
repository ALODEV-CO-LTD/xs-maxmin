<!--
  Tài khoản > Mã khôi phục (K07/A06): create the code for an older account
  that has none, or replace it (the old code stops working). Needs the
  current password. The new code is shown once via RecoveryCodeDisplay.
  API: POST /me/recovery-code { currentPassword } -> { recoveryCode }
-->
<script setup>
import AppButton from './AppButton.vue'
import { ref } from 'vue'
import { api } from '../api'
import { useAuthStore } from '../stores/auth'
import RecoveryCodeDisplay from './RecoveryCodeDisplay.vue'

const auth = useAuthStore()

const password = ref('')
const error = ref('')
const busy = ref(false)
const newCode = ref('')

async function submit() {
  error.value = ''
  if (!password.value) {
    error.value = 'Nhập mật khẩu hiện tại để tiếp tục'
    return
  }
  busy.value = true
  try {
    const res = await api.post('/me/recovery-code', { currentPassword: password.value })
    newCode.value = res.recoveryCode
    password.value = ''
    await auth.fetchMe()
  } catch (e) {
    error.value = e.message || 'Không tạo được mã khôi phục'
  } finally {
    busy.value = false
  }
}

function done() {
  newCode.value = ''
}
</script>

<template>
  <div class="card">
    <h3 style="margin-top: 0">Mã khôi phục</h3>
    <template v-if="newCode">
      <RecoveryCodeDisplay :code="newCode" continue-text="Xong" @confirmed="done" />
    </template>
    <form v-else @submit.prevent="submit">
      <p class="page-subtitle">
        <template v-if="auth.user?.hasRecoveryCode">
          Bạn đã có mã khôi phục. Tạo mã mới sẽ <strong>vô hiệu mã cũ</strong>. Mã chỉ hiển thị một lần.
        </template>
        <template v-else>
          Tài khoản chưa có mã khôi phục. Tạo mã để có thể đặt lại mật khẩu khi quên (mã chỉ hiển thị một lần).
        </template>
      </p>
      <div v-if="error" class="alert alert-error">{{ error }}</div>
      <div class="field">
        <label for="rc-password">Mật khẩu hiện tại</label>
        <div class="input-wrap">
          <input id="rc-password" v-model="password" type="password" autocomplete="current-password" :disabled="busy" />
        </div>
      </div>
      <AppButton variant="primary" size="sm" type="submit" :disabled="busy">
{{ busy ? 'Đang tạo...' : auth.user?.hasRecoveryCode ? 'Đổi mã khôi phục' : 'Tạo mã khôi phục' }}
</AppButton>
    </form>
  </div>
</template>
