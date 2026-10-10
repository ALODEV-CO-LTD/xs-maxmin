<!--
  Image button for a chat composer. Only JPG, PNG and WebP pictures can be sent (GIFs and
  other files can carry author/device/time data that cannot be reliably removed).
  Emits `pick` with the chosen File and `error` with a message when the file is not an
  allowed picture, is empty or is over the 5 MB limit. The chosen file is shown by <AttachmentPreview>.
-->
<script setup>
import { ref } from 'vue'
import AppIcon from './AppIcon.vue'
import { ALLOWED_IMAGE_TYPES, IMAGE_ONLY_MESSAGE, MAX_ATTACHMENT_BYTES } from '../attachments'

defineProps({ disabled: { type: Boolean, default: false } })
const emit = defineEmits(['pick', 'error'])

const imageInput = ref(null)

function onChange(e) {
  const file = e.target.files?.[0]
  e.target.value = '' // allow picking the same file again
  if (!file) return
  if (!ALLOWED_IMAGE_TYPES.includes(file.type)) return emit('error', IMAGE_ONLY_MESSAGE)
  if (file.size === 0) return emit('error', 'Tệp trống')
  if (file.size > MAX_ATTACHMENT_BYTES) return emit('error', 'Tệp quá lớn (tối đa 5 MB)')
  emit('pick', file)
}
</script>

<template>
  <div class="attach-buttons">
    <input ref="imageInput" type="file" accept="image/jpeg,image/png,image/webp" class="attach-input" @change="onChange" />
    <button type="button" class="attach-btn" :disabled="disabled" aria-label="Gửi ảnh" title="Gửi ảnh (JPG, PNG, WebP)" @click="imageInput.click()">
      <AppIcon name="image" />
    </button>
  </div>
</template>

<style scoped>
.attach-buttons {
  display: flex;
  flex: none;
  gap: 2px;
}
.attach-input {
  display: none;
}
.attach-btn {
  width: 44px;
  height: 44px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 0;
  font-size: 30px; /* icons are 30px */
  color: var(--text-secondary);
  background: transparent;
  border: 0;
  border-radius: 10px;
  cursor: pointer;
  transition: color 0.15s ease, background 0.15s ease;
}
.attach-btn:hover:not(:disabled) {
  color: var(--text-primary);
  background: var(--surface);
}
.attach-btn:focus-visible {
  outline: 3px solid color-mix(in srgb, var(--primary) 55%, transparent);
  outline-offset: 2px;
}
.attach-btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
</style>
