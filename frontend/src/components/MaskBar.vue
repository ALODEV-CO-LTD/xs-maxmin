<!--
  The "Ẩn số liệu" controls shared by Nhập số, Khách hàng and Tính điểm (see stores/mask.js).
  One state, one main action: off -> "Bật ẩn số liệu" (no password); covered -> "Hiện số liệu"
  (password, then a live countdown with a progress bar); shown -> "Che lại". The gear menu holds
  the rarely used settings: how long figures stay visible (10 s - 5 min, per device) and turning
  the mode off (password). The page decides what to mask with
  <MaskedValue /> or mask.masked.

  <MaskBar /> goes inside any flex row; page-specific buttons go next to it.
-->
<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import AppIcon from './AppIcon.vue'
import PasswordPromptDialog from './PasswordPromptDialog.vue'
import { mask, REVEAL_CHOICES } from '../stores/mask'

const masked = mask.masked
const enabled = computed(() => mask.state.enabled)

const menuOpen = ref(false)
const menuBox = ref(null)
function onDocClick(e) {
  if (menuOpen.value && menuBox.value && !menuBox.value.contains(e.target)) menuOpen.value = false
}
function turnOff() {
  menuOpen.value = false
  openPrompt('disable')
}

const promptOpen = ref(false)
const promptPurpose = ref('reveal') // 'reveal' | 'disable'
function toggle() {
  mask.enable()
}
function openPrompt(purpose) {
  promptPurpose.value = purpose
  promptOpen.value = true
}
function onVerified() {
  promptOpen.value = false
  if (promptPurpose.value === 'disable') mask.disable()
  else mask.reveal()
}

const revealSeconds = computed({
  get: () => mask.state.revealSeconds,
  set: (v) => mask.setRevealSeconds(Number(v)),
})
function secondsLabel(n) {
  return n >= 60 ? `${n / 60} phút` : `${n} giây`
}

// live countdown while the figures are shown
const secondsLeft = ref(0)
const progress = computed(() => Math.min(100, Math.round((secondsLeft.value / mask.state.revealSeconds) * 100)))
let timer = null
watch(
  () => mask.state.revealUntil,
  (until) => {
    clearInterval(timer)
    if (!until) {
      secondsLeft.value = 0
      return
    }
    const tick = () => (secondsLeft.value = Math.max(0, Math.ceil((mask.state.revealUntil - Date.now()) / 1000)))
    tick()
    timer = setInterval(tick, 500)
  },
  { immediate: true },
)

onMounted(() => {
  mask.attach()
  document.addEventListener('mousedown', onDocClick)
})
onBeforeUnmount(() => {
  clearInterval(timer)
  document.removeEventListener('mousedown', onDocClick)
  mask.detach()
})
</script>

<template>
  <div class="mask-bar" :class="{ off: !enabled, covered: enabled && masked, shown: enabled && !masked }">
    <!-- Off: one clear call to action -->
    <button v-if="!enabled" type="button" class="mb-btn mb-ghost" @click="toggle">
      <AppIcon name="eye-off" /> Bật ẩn số liệu
    </button>

    <template v-else>
      <!-- State + the one action that makes sense right now -->
      <span v-if="masked" class="mb-status" role="status"><AppIcon name="eye-off" /> Số liệu đang ẩn</span>
      <span v-else class="mb-status mb-live" role="timer" aria-live="off">
        <AppIcon name="eye" /> Không thao tác, che sau <strong>{{ secondsLeft }}s</strong>
        <span class="mb-bar" aria-hidden="true"><span class="mb-fill" :style="{ width: progress + '%' }"></span></span>
      </span>
      <button v-if="masked" type="button" class="mb-btn mb-primary" @click="openPrompt('reveal')">
        <AppIcon name="eye" /> Hiện số liệu
      </button>
      <button v-else type="button" class="mb-btn mb-primary" @click="mask.cover()">
        <AppIcon name="eye-off" /> Che lại
      </button>

      <!-- Rarely used: time + turn off -->
      <div ref="menuBox" class="mb-menu-wrap">
        <button
          type="button"
          class="mb-btn mb-icon"
          aria-haspopup="true"
          :aria-expanded="menuOpen"
          aria-label="Tuỳ chọn ẩn số liệu"
          title="Tuỳ chọn"
          @click="menuOpen = !menuOpen"
        >
          <AppIcon name="settings" />
        </button>
        <div v-if="menuOpen" class="mb-menu" role="group" aria-label="Tuỳ chọn ẩn số liệu" @keydown.esc="menuOpen = false">
          <label class="mb-field">
            <span>Tự che khi không thao tác sau</span>
            <select v-model.number="revealSeconds" aria-label="Thời gian hiện số liệu sau khi nhập mật khẩu">
              <option v-for="n in REVEAL_CHOICES" :key="n" :value="n">{{ secondsLabel(n) }}</option>
            </select>
          </label>
          <button type="button" class="mb-btn mb-danger" @click="turnOff">Tắt chế độ ẩn (cần mật khẩu)</button>
        </div>
      </div>
    </template>

    <PasswordPromptDialog
      :open="promptOpen"
      :title="promptPurpose === 'disable' ? 'Tắt ẩn số liệu' : 'Hiện số liệu'"
      :description="
        promptPurpose === 'disable'
          ? 'Nhập mật khẩu đăng nhập để tắt chế độ ẩn số liệu.'
          : `Nhập mật khẩu đăng nhập để xem số liệu. Số liệu tự ẩn lại sau ${secondsLabel(mask.state.revealSeconds)} không thao tác (đang thao tác thì không ẩn), hoặc ngay khi bạn rời cửa sổ này.`
      "
      @verified="onVerified"
      @close="promptOpen = false"
    />
  </div>
</template>

<style scoped>
.mask-bar {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 8px;
}
.mb-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  min-height: 44px;
  padding: 0 16px;
  font: inherit;
  font-size: 14px;
  font-weight: 700;
  color: var(--text-primary);
  background: var(--surface);
  border: 1px solid var(--input-border);
  border-radius: 10px;
  cursor: pointer;
}
.mb-btn:hover {
  border-color: var(--input-border-hover);
}
.mb-btn:focus-visible {
  outline: 2px solid var(--primary);
  outline-offset: 2px;
}
.mb-primary {
  color: var(--on-primary);
  background: var(--primary);
  border-color: var(--primary);
}
.mb-primary:hover {
  filter: brightness(1.08);
  border-color: var(--primary);
}
.mb-ghost {
  font-weight: 600;
  color: var(--text-secondary);
}
.mb-icon {
  width: 44px;
  padding: 0;
}
.mb-danger {
  width: 100%;
  color: var(--danger-text);
}
.mb-status {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  min-height: 44px;
  padding: 0 14px;
  font-size: 14px;
  color: var(--text-secondary);
  background: color-mix(in srgb, var(--text-secondary) 12%, transparent);
  border-radius: 10px;
}
.mb-live {
  color: var(--text-primary);
  background: color-mix(in srgb, var(--primary) 16%, transparent);
  font-variant-numeric: tabular-nums;
}
.mb-bar {
  width: 48px;
  height: 4px;
  overflow: hidden;
  background: color-mix(in srgb, var(--primary) 25%, transparent);
  border-radius: 2px;
}
.mb-fill {
  display: block;
  height: 100%;
  background: var(--primary);
  transition: width 0.5s linear;
}
.mb-menu-wrap {
  position: relative;
}
.mb-menu {
  position: absolute;
  top: calc(100% + 6px);
  left: 0;
  z-index: 20;
  display: grid;
  gap: 12px;
  width: 260px;
  max-width: calc(100vw - 32px);
  padding: 14px;
  background: var(--card);
  border: 1px solid var(--input-border);
  border-radius: 12px;
  box-shadow: var(--shadow-lg);
}
.mb-field {
  display: grid;
  gap: 6px;
  font-size: 14px;
  color: var(--text-secondary);
}
.mb-field select {
  min-height: 44px;
  padding: 0 10px;
  font-size: 14px;
  color: var(--text-primary);
  background: var(--surface);
  border: 1px solid var(--input-border);
  border-radius: 10px;
}
@media (max-width: 480px) {
  .mask-bar .mb-primary {
    flex: 1 1 auto;
  }
}
</style>
