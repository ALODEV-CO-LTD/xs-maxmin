<!--
  Asks for the account password and checks it with POST /me/verify-password
  ({ password } -> 200 ok, 403 wrong, 429 locked out with a message). Emits
  `verified` on success and `close` on cancel/Esc. Errors stay in the dialog.
-->
<script setup>
import { ref, watch } from 'vue'
import { api } from '../api'
import ModalDialog from './ModalDialog.vue'
import AppButton from './AppButton.vue'
import PasswordInput from './PasswordInput.vue'

const props = defineProps({
  open: { type: Boolean, default: false },
  title: { type: String, default: 'Nhập mật khẩu' },
  description: { type: String, default: 'Nhập mật khẩu đăng nhập để tiếp tục.' },
  confirmText: { type: String, default: 'Xác nhận' },
})
const emit = defineEmits(['verified', 'close'])

const password = ref('')
const error = ref('')
const busy = ref(false)

watch(
  () => props.open,
  (o) => {
    if (o) {
      password.value = ''
      error.value = ''
      busy.value = false
    }
  },
)

async function submit() {
  if (busy.value) return
  if (!password.value) {
    error.value = 'Vui lòng nhập mật khẩu'
    return
  }
  busy.value = true
  error.value = ''
  try {
    await api.post('/me/verify-password', { password: password.value })
    password.value = ''
    emit('verified')
  } catch (err) {
    error.value = err.message || 'Không xác nhận được mật khẩu'
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <ModalDialog :open="open" :title="title" :description="description" @close="emit('close')">
    <form id="pwd-prompt-form" @submit.prevent="submit">
      <div class="field" style="margin-bottom: 0">
        <label for="pwd-prompt-input">Mật khẩu đăng nhập</label>
        <PasswordInput
          id="pwd-prompt-input"
          v-model="password"
          data-autofocus
          autocomplete="current-password"
          :disabled="busy"
        />
      </div>
      <div v-if="error" class="alert alert-error" role="alert" style="margin: 12px 0 0">{{ error }}</div>
    </form>
    <template #footer>
      <AppButton variant="ghost" :disabled="busy" @click="emit('close')">Huỷ</AppButton>
      <AppButton variant="primary" type="submit" form="pwd-prompt-form" :loading="busy">{{ busy ? 'Đang kiểm tra...' : confirmText }}</AppButton>
    </template>
  </ModalDialog>
</template>
