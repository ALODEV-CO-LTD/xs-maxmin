<!-- The file chosen for the next message: thumbnail (images) or name + size, with a remove button. -->
<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import AppIcon from './AppIcon.vue'
import { formatSize, isScrubbableImage } from '../attachments'

const props = defineProps({ file: { type: File, required: true } })
defineEmits(['remove'])

const scrubbable = computed(() => isScrubbableImage(props.file))

const isImage = computed(() => props.file.type.startsWith('image/') && props.file.type !== 'image/svg+xml')
const previewUrl = ref('')
watch(
  () => props.file,
  (file) => {
    if (previewUrl.value) URL.revokeObjectURL(previewUrl.value)
    previewUrl.value = isImage.value ? URL.createObjectURL(file) : ''
  },
  { immediate: true },
)
onBeforeUnmount(() => {
  if (previewUrl.value) URL.revokeObjectURL(previewUrl.value)
})
</script>

<template>
  <div class="att-wrap">
    <div class="att-preview">
      <img v-if="isImage" :src="previewUrl" :alt="file.name" class="att-thumb" />
      <span v-else class="att-icon"><AppIcon name="paperclip" /></span>
      <span class="att-info">
        <span class="att-name">{{ file.name }}</span>
        <span class="att-size">{{ formatSize(file.size) }}</span>
      </span>
      <button type="button" class="att-remove" aria-label="Bỏ tệp đính kèm" @click="$emit('remove')">
        <AppIcon name="x" />
      </button>
    </div>
    <!-- Images are always scrubbed before sending (K37/K38/S09); no switch. -->
    <div v-if="scrubbable" class="att-privacy">
      <div class="att-privacy-note">
        Ảnh sẽ tự động được xoá thông tin ẩn (vị trí GPS, thiết bị, thời gian chụp) và đổi tên trước khi gửi.
        Lưu ý: sau khi gửi, bản người nhận đã lưu về máy thì không thể xoá thông tin khỏi đó.
      </div>
    </div>
  </div>
</template>

<style scoped>
.att-wrap {
  margin-bottom: 8px;
}
.att-privacy {
  margin-top: 6px;
  font-size: 14px;
  color: var(--text-secondary);
}
.att-privacy-toggle {
  display: flex;
  align-items: flex-start;
  gap: 6px;
  cursor: pointer;
  color: var(--text-primary);
}
.att-privacy-toggle input {
  width: auto;
  margin-top: 2px;
}
.att-privacy-note {
  margin-top: 2px;
}
.att-preview {
  display: flex;
  align-items: center;
  gap: 10px;
  max-width: 100%;
  padding: 6px 8px;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 10px;
}
.att-thumb {
  width: 40px;
  height: 40px;
  flex: none;
  object-fit: cover;
  border-radius: 8px;
}
.att-icon {
  width: 40px;
  height: 40px;
  flex: none;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 24px;
  color: var(--text-secondary);
  background: var(--card);
  border-radius: 8px;
}
.att-info {
  min-width: 0;
  flex: 1;
  display: flex;
  flex-direction: column;
}
.att-name {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 14px;
  font-weight: 600;
  color: var(--text-primary);
}
.att-size {
  font-size: 14px;
  color: var(--text-secondary);
}
.att-remove {
  width: 32px;
  height: 32px;
  flex: none;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 0;
  font-size: 18px;
  color: var(--text-secondary);
  background: transparent;
  border: 0;
  border-radius: 8px;
  cursor: pointer;
}
.att-remove:hover {
  color: var(--danger-text);
  background: var(--danger-soft);
}
</style>
