<!--
  Shows a mã khôi phục exactly once and makes the user confirm they saved it
  before continuing. Used by RegisterView, LoginView (after a reset) and
  RecoveryCodePanel (AccountView). Emits `confirmed` when they continue.
  The code is only held in the parent's memory - never stored client-side.
-->
<script setup>
import { ref } from 'vue'

defineProps({
  code: { type: String, required: true },
  continueText: { type: String, default: 'Tiếp tục' },
})
const emit = defineEmits(['confirmed'])

const saved = ref(false)
const copied = ref(false)

async function copy(code) {
  try {
    await navigator.clipboard.writeText(code)
    copied.value = true
  } catch {
    copied.value = false
  }
}
</script>

<template>
  <div class="rc">
    <div class="alert alert-warning">
      Đây là <strong>mã khôi phục</strong> của bạn. Mã chỉ hiển thị <strong>một lần duy nhất</strong> và không ai
      (kể cả quản trị viên) xem lại được. Hãy ghi lại hoặc lưu ở nơi an toàn. Có mã này, bạn đặt lại được mật khẩu khi
      quên - vì vậy đừng chia sẻ cho người khác.
    </div>
    <div class="rc-code" aria-label="Mã khôi phục">{{ code }}</div>
    <button type="button" class="btn btn-secondary btn-block" @click="copy(code)">
      {{ copied ? 'Đã sao chép' : 'Sao chép mã' }}
    </button>
    <label class="rc-ack">
      <input v-model="saved" type="checkbox" />
      <span>Tôi đã lưu mã khôi phục ở nơi an toàn.</span>
    </label>
    <button type="button" class="btn btn-primary btn-block" :disabled="!saved" @click="emit('confirmed')">
      {{ continueText }}
    </button>
  </div>
</template>

<style scoped>
.rc-code {
  margin: 0 0 12px;
  padding: 16px 12px;
  text-align: center;
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  font-size: 22px;
  font-weight: 700;
  letter-spacing: 0.08em;
  background: var(--surface);
  border: 1px dashed var(--input-border);
  border-radius: var(--radius-md);
  user-select: all;
  overflow-wrap: anywhere;
}
.rc-ack {
  display: flex;
  gap: 8px;
  align-items: flex-start;
  margin: 16px 0;
  font-size: 14px;
  cursor: pointer;
}
.rc-ack input {
  margin-top: 3px;
}
</style>
