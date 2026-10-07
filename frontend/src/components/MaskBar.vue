<!--
  The "Ẩn số liệu" controls shared by Nhập số, Khách hàng and Tính điểm (see stores/mask.js):
  the on/off switch (turning it on needs no password, turning it off does), "Hiện" (asks for the
  password, then shows the figures for a short time with a live countdown), "Che lại", and the
  "Hiện trong" choice (10 s - 5 min, remembered per device). The page decides what to mask with
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

const promptOpen = ref(false)
const promptPurpose = ref('reveal') // 'reveal' | 'disable'
function toggle() {
  if (!mask.state.enabled) mask.enable()
  else openPrompt('disable')
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

onMounted(() => mask.attach())
onBeforeUnmount(() => {
  clearInterval(timer)
  mask.detach()
})
</script>

<template>
  <div class="mask-bar">
    <button type="button" class="mask-switch" role="switch" :aria-checked="enabled" :class="{ on: enabled }" @click="toggle">
      <AppIcon :name="enabled ? 'eye-off' : 'eye'" />
      Ẩn số liệu
      <span class="mask-state">{{ enabled ? 'Bật' : 'Tắt' }}</span>
    </button>
    <button v-if="enabled && masked" type="button" class="mask-btn" @click="openPrompt('reveal')">
      <AppIcon name="eye" /> Hiện
    </button>
    <button v-else-if="enabled" type="button" class="mask-btn" @click="mask.cover()">
      <AppIcon name="eye-off" /> Che lại
    </button>
    <span v-if="enabled && !masked" class="mask-countdown" role="timer" aria-live="off">Tự che sau {{ secondsLeft }}s</span>
    <label v-if="enabled" class="mask-time">
      <span>Hiện trong</span>
      <select v-model.number="revealSeconds" aria-label="Thời gian hiện số liệu sau khi nhập mật khẩu">
        <option v-for="n in REVEAL_CHOICES" :key="n" :value="n">{{ secondsLabel(n) }}</option>
      </select>
    </label>

    <PasswordPromptDialog
      :open="promptOpen"
      :title="promptPurpose === 'disable' ? 'Tắt ẩn số liệu' : 'Hiện số liệu'"
      :description="
        promptPurpose === 'disable'
          ? 'Nhập mật khẩu đăng nhập để tắt chế độ ẩn số liệu.'
          : `Nhập mật khẩu đăng nhập để xem số liệu. Số liệu sẽ tự ẩn lại sau ${secondsLabel(mask.state.revealSeconds)}, hoặc ngay khi bạn rời cửa sổ này.`
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
.mask-switch,
.mask-btn {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  min-height: 44px;
  padding: 0 14px;
  font-size: 14px;
  font-weight: 700;
  color: var(--text-primary);
  background: var(--surface);
  border: 1px solid var(--input-border);
  border-radius: 10px;
  cursor: pointer;
}
.mask-btn {
  gap: 6px;
  font-weight: 600;
}
.mask-switch.on {
  color: var(--on-primary);
  background: var(--primary);
  border-color: var(--primary);
}
.mask-state {
  padding: 1px 8px;
  font-size: 12px;
  background: color-mix(in srgb, currentColor 18%, transparent);
  border-radius: 999px;
}
.mask-countdown {
  padding: 4px 10px;
  font-size: 14px;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
  color: var(--text-primary);
  background: color-mix(in srgb, var(--primary) 18%, transparent);
  border-radius: 999px;
}
.mask-time {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 14px;
  color: var(--text-secondary);
}
.mask-time select {
  min-height: 44px;
  padding: 0 10px;
  font-size: 14px;
  color: var(--text-primary);
  background: var(--surface);
  border: 1px solid var(--input-border);
  border-radius: 10px;
}
</style>
