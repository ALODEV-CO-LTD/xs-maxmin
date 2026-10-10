<!--
  An attachment inside a chat bubble. Images load as a thumbnail (fetched with
  the session token, then shown from an object URL; click to open full size).
  Other files show their name + size and download on click.
-->
<script setup>
import { onBeforeUnmount, onMounted, ref } from 'vue'
import AppIcon from './AppIcon.vue'
import { api } from '../api'
import { formatSize } from '../attachments'

const props = defineProps({
  att: { type: Object, required: true }, // { name, type, size, isImage }
  path: { type: String, default: '' }, // API path of the attachment bytes
  blob: { type: Blob, default: null }, // or the bytes themselves (end-to-end encrypted chat, kept on this device)
})

const imageUrl = ref('')
const failed = ref(false)
const busy = ref(false)

onMounted(async () => {
  if (!props.att.isImage) return
  try {
    imageUrl.value = URL.createObjectURL(props.blob || (await api.blob(props.path)))
  } catch {
    failed.value = true
  }
})
onBeforeUnmount(() => {
  if (imageUrl.value) URL.revokeObjectURL(imageUrl.value)
})

async function download() {
  if (busy.value) return
  busy.value = true
  try {
    const url = URL.createObjectURL(props.blob || (await api.blob(props.path)))
    const a = document.createElement('a')
    a.href = url
    a.download = props.att.name
    document.body.appendChild(a)
    a.click()
    a.remove()
    setTimeout(() => URL.revokeObjectURL(url), 10000)
  } catch {
    failed.value = true
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <a v-if="att.isImage && imageUrl" :href="imageUrl" target="_blank" rel="noopener" class="ma-image-link" :title="att.name">
    <img :src="imageUrl" :alt="att.name" class="ma-image" />
  </a>
  <div v-else-if="att.isImage && !failed" class="ma-image ma-loading" aria-busy="true"></div>
  <button v-else type="button" class="ma-file" :disabled="busy" @click="download">
    <span class="ma-file-icon"><AppIcon name="paperclip" /></span>
    <span class="ma-file-info">
      <span class="ma-file-name">{{ att.name }}</span>
      <span class="ma-file-size">{{ failed ? 'Không tải được tệp' : formatSize(att.size) }}</span>
    </span>
  </button>
</template>

<style scoped>
.ma-image-link {
  display: block;
  margin-top: 4px;
}
.ma-image {
  display: block;
  max-width: min(260px, 100%);
  max-height: 240px;
  border-radius: 10px;
  object-fit: cover;
}
.ma-loading {
  width: 200px;
  height: 140px;
  background: var(--surface);
}
.ma-file {
  display: flex;
  align-items: center;
  gap: 10px;
  max-width: 100%;
  margin-top: 4px;
  padding: 8px 10px;
  font-family: var(--font-body);
  text-align: left;
  color: var(--text-primary);
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 10px;
  cursor: pointer;
}
.ma-file:hover:not(:disabled) {
  border-color: var(--input-border);
}
.ma-file-icon {
  flex: none;
  display: inline-flex;
  font-size: 22px;
  color: var(--text-secondary);
}
.ma-file-info {
  min-width: 0;
  display: flex;
  flex-direction: column;
}
.ma-file-name {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 14px;
  font-weight: 600;
}
.ma-file-size {
  font-size: 14px;
  color: var(--text-secondary);
}
</style>
