<!--
  Auto-delete rule for ONE friend conversation (K36/S05): messages (or only
  images) older than a chosen time are deleted by a server background timer,
  for both people. Shown under the thread header in FriendsView. Setting a
  rule first shows the server's warning (scope + when) in a confirm dialog;
  either friend can change or cancel it.
  API: GET/POST /me/deletion-schedules, DELETE /me/deletion-schedules/:id
-->
<script setup>
import { computed, ref, watch } from 'vue'
import { api } from '../api'
import { showConfirm } from '../confirm'
import AppSelect from './AppSelect.vue'

const props = defineProps({ friendId: { type: String, required: true }, friendName: { type: String, default: '' } })
const emit = defineEmits(['applied'])

const TTL_OPTIONS = [
  { value: 3600, label: '1 giờ' },
  { value: 86400, label: '1 ngày' },
  { value: 604800, label: '7 ngày' },
  { value: 2592000, label: '30 ngày' },
]
const rule = ref(null)
const open = ref(false)
const ttl = ref(86400)
const scope = ref('all')
const error = ref('')
const busy = ref(false)

const ttlLabel = computed(() => TTL_OPTIONS.find((o) => o.value === rule.value?.ttlSeconds)?.label || '')

async function load() {
  error.value = ''
  try {
    const res = await api.get('/me/deletion-schedules')
    rule.value = res.schedules.find((s) => s.kind === 'chat' && s.status === 'pending' && s.friendId === props.friendId) || null
  } catch (err) {
    error.value = err.message || 'Không tải được cài đặt tự xoá'
  }
}
watch(() => props.friendId, () => { open.value = false; load() }, { immediate: true })

async function apply() {
  error.value = ''
  busy.value = true
  try {
    const body = { kind: 'chat', friendId: props.friendId, ttlSeconds: ttl.value, chatScope: scope.value }
    const preview = await api.post('/me/deletion-schedules', body)
    const ok = await showConfirm({
      title: 'Xác nhận tự xoá tin nhắn',
      message: `CẢNH BÁO: ${preview.scopeText}\n\nÁp dụng từ: ${new Date(preview.runAt).toLocaleString('vi-VN')}. Bạn có thể tắt bất cứ lúc nào, nhưng nội dung đã xoá không khôi phục được.`,
      confirmText: 'Bật tự xoá',
      danger: true,
    })
    if (!ok) return
    await api.post('/me/deletion-schedules', { ...body, confirm: true })
    open.value = false
    await load()
    emit('applied')
  } catch (err) {
    error.value = err.message || 'Không đặt được tự xoá'
  } finally {
    busy.value = false
  }
}

async function cancel() {
  if (!rule.value) return
  try {
    await api.del(`/me/deletion-schedules/${rule.value.id}`)
    await load()
  } catch (err) {
    error.value = err.message || 'Không tắt được tự xoá'
  }
}
</script>

<template>
  <div class="retention">
    <div class="retention-line">
      <span v-if="rule" class="retention-state">
        Tự xoá {{ rule.chatScope === 'images' ? 'ảnh' : 'tin nhắn' }} cũ hơn {{ ttlLabel }}{{ rule.setByMe ? '' : ' (bạn bè đặt)' }}
      </span>
      <span v-else class="retention-state muted">Tin nhắn không tự xoá</span>
      <button type="button" class="btn btn-ghost btn-sm" @click="open = !open">{{ open ? 'Đóng' : 'Cài đặt tự xoá' }}</button>
      <button v-if="rule" type="button" class="btn btn-ghost btn-sm" @click="cancel">Tắt</button>
    </div>
    <div v-if="error" class="alert alert-error" style="margin: 6px 0 0">{{ error }}</div>
    <form v-if="open" class="retention-form" @submit.prevent="apply">
      <p class="retention-hint">
        Tin nhắn/ảnh cũ hơn thời gian chọn sẽ bị xoá tự động cho cả hai phía của cuộc trò chuyện với {{ friendName }}.
      </p>
      <div class="retention-row">
        <AppSelect v-model="ttl" aria-label="Thời gian tự xoá">
          <option v-for="o in TTL_OPTIONS" :key="o.value" :value="o.value">Sau {{ o.label }}</option>
        </AppSelect>
        <AppSelect v-model="scope" aria-label="Phạm vi tự xoá">
          <option value="all">Tin nhắn và tệp đính kèm</option>
          <option value="images">Chỉ ảnh</option>
        </AppSelect>
        <button type="submit" class="btn btn-danger btn-sm" :disabled="busy">{{ busy ? '...' : 'Áp dụng' }}</button>
      </div>
    </form>
  </div>
</template>

<style scoped>
.retention {
  margin-bottom: 8px;
  font-size: 13px;
}
.retention-line {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 4px;
}
.retention-state {
  flex: 1;
  color: var(--text-primary);
}
.retention-state.muted {
  color: var(--text-secondary);
}
.retention-form {
  margin-top: 6px;
  padding: 8px 10px;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 10px;
}
.retention-hint {
  margin: 0 0 8px;
  color: var(--text-secondary);
}
.retention-row {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  align-items: center;
}
</style>
