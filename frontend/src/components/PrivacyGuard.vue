<!--
  Auto-lock screen + hide-when-away blur (K09/K40/S02, K32/S10). Mounted once
  in App.vue for logged-in users; all logic lives in stores/privacy.js.
  The pages underneath stay mounted (only covered and made inert) so
  half-typed input is not lost. A web page cannot stop screenshots (K33).
-->
<script setup>
import AppButton from './AppButton.vue'
import { nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { ApiError } from '../api'
import { useAuthStore } from '../stores/auth'
import { useCallStore } from '../stores/call'
import { usePrivacyStore } from '../stores/privacy'
import PasswordInput from './PasswordInput.vue'

const privacy = usePrivacyStore()
const auth = useAuthStore()
const call = useCallStore()
const router = useRouter()

const password = ref('')
const error = ref('')
const busy = ref(false)
const input = ref(null)

function appRoot() {
  return document.getElementById('app')
}

function sync() {
  const root = appRoot()
  document.documentElement.classList.toggle('privacy-away', privacy.away && !privacy.locked)
  if (root) {
    if (privacy.locked) root.setAttribute('inert', '')
    else root.removeAttribute('inert')
  }
}

watch(() => [privacy.away, privacy.locked], sync, { immediate: true })
watch(
  () => privacy.locked,
  async (locked) => {
    if (!locked) return
    password.value = ''
    error.value = ''
    // drop focus from any field underneath so typing can't reach it
    if (document.activeElement instanceof HTMLElement) document.activeElement.blur()
    await nextTick()
    input.value?.querySelector('input')?.focus()
  },
  { immediate: true },
)

onMounted(() => privacy.start())
onBeforeUnmount(() => {
  privacy.stop()
  document.documentElement.classList.remove('privacy-away')
  appRoot()?.removeAttribute('inert')
})

async function submit() {
  error.value = ''
  if (!password.value) {
    error.value = 'Vui lòng nhập mật khẩu'
    return
  }
  busy.value = true
  try {
    await privacy.unlock(password.value)
    password.value = ''
  } catch (e) {
    error.value = e instanceof ApiError ? e.message : 'Đã xảy ra lỗi, vui lòng thử lại'
  } finally {
    busy.value = false
  }
}

function logoutNow() {
  call.disconnect()
  auth.logout()
  router.push('/login')
}
</script>

<template>
  <Teleport to="body">
    <div v-if="privacy.locked" class="pl-overlay" role="dialog" aria-modal="true" aria-labelledby="pl-title">
      <form class="pl-box" @submit.prevent="submit">
        <h2 id="pl-title" class="pl-title">Ứng dụng đã khoá</h2>
        <p class="pl-msg">
          Để bảo vệ dữ liệu, ứng dụng đã khoá. Nhập mật khẩu (hoặc mật khẩu lớp hai) để tiếp tục. Dữ liệu bạn đang
          nhập vẫn được giữ nguyên.
        </p>
        <div v-if="error" class="alert alert-error" role="alert">{{ error }}</div>
        <div ref="input" class="field">
          <label for="pl-password">Mật khẩu</label>
          <PasswordInput id="pl-password" v-model="password" autocomplete="current-password" :disabled="busy" />
        </div>
        <AppButton variant="primary" block type="submit" :loading="busy">{{ busy ? 'Đang kiểm tra...' : 'Mở khoá' }}</AppButton>
        <AppButton variant="ghost" block @click="logoutNow">Đăng xuất</AppButton>
      </form>
    </div>
    <div v-else-if="privacy.away" class="pl-veil" aria-hidden="true"></div>
  </Teleport>
</template>

<style>
/* Blur the whole app while the page is hidden / unfocused (K32). */
html.privacy-away #app {
  filter: blur(18px);
  pointer-events: none;
  user-select: none;
}
</style>

<style scoped>
.pl-overlay {
  position: fixed;
  inset: 0;
  z-index: 300;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 16px;
  background: var(--background);
}
.pl-box {
  width: 100%;
  max-width: 400px;
  padding: 24px;
  background: var(--card);
  border: 1px solid var(--input-border);
  border-radius: 16px;
  box-shadow: var(--shadow-lg);
}
.pl-title {
  margin: 0 0 8px;
  font-size: 20px;
}
.pl-msg {
  margin: 0 0 16px;
  font-size: 14px;
  line-height: 1.5;
  color: var(--text-secondary);
}
/* faint veil on top of the blurred app so nothing sharp shows through */
.pl-veil {
  position: fixed;
  inset: 0;
  z-index: 290;
  background: color-mix(in srgb, var(--background) 55%, transparent);
}
</style>
