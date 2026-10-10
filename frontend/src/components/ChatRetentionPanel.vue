<!--
  Auto-delete for ONE friend conversation (K36/S05). Chat is end-to-end encrypted
  and stored only on each device (docs/MA_HOA_2_DAU.md), so this rule runs on THIS
  device: messages (or only images) older than the chosen time are removed from
  its local history. It does not touch the friend's device.
  The buttons that open/turn off this setting live in the conversation's top bar
  (FriendsView); this panel shows the current rule and the settings form.
  Props: friendId, friendName, open (v-model:open). Emits: applied, rule(rule|null).
  Exposes cancel().
-->
<script setup>
import { computed, ref, watch } from 'vue'
import { useChatStore } from '../e2ee/chat'
import AppSelect from './AppSelect.vue'

const props = defineProps({
  friendId: { type: String, required: true },
  friendName: { type: String, default: '' },
  open: { type: Boolean, default: false },
})
const emit = defineEmits(['applied', 'update:open', 'rule'])
const chat = useChatStore()

const TTL_OPTIONS = [
  { value: 3600, label: '1 giờ' },
  { value: 86400, label: '1 ngày' },
  { value: 604800, label: '7 ngày' },
  { value: 2592000, label: '30 ngày' },
]
const rule = ref(null)
const ttl = ref(86400)
const scope = ref('all')
const error = ref('')
const busy = ref(false)

const ttlLabel = computed(() => TTL_OPTIONS.find((o) => o.value === rule.value?.ttlSeconds)?.label || '')

async function load() {
  error.value = ''
  rule.value = await chat.retentionOf(props.friendId)
  emit('rule', rule.value)
}
watch(() => [props.friendId, chat.ready], () => { emit('update:open', false); load() }, { immediate: true })

async function apply() {
  error.value = ''
  busy.value = true
  try {
    await chat.setRetention(props.friendId, { ttlSeconds: ttl.value, scope: scope.value })
    emit('update:open', false)
    await load()
    emit('applied')
  } catch (err) {
    error.value = err.message || 'Không đặt được tự xoá'
  } finally {
    busy.value = false
  }
}

async function cancel() {
  await chat.setRetention(props.friendId, null)
  await load()
}
defineExpose({ cancel })
</script>

<template>
  <div class="retention">
    <div class="retention-line">
      <span v-if="rule" class="retention-state">
        Tự xoá {{ rule.scope === 'images' ? 'ảnh' : 'tin nhắn' }} cũ hơn {{ ttlLabel }} (trên thiết bị này)
      </span>
      <span v-else class="retention-state muted">Tin nhắn không tự xoá</span>
    </div>
    <div v-if="error" class="alert alert-error" style="margin: 6px 0 0">{{ error }}</div>
    <form v-if="open" class="retention-form" @submit.prevent="apply">
      <p class="retention-hint">
        Tin nhắn/ảnh cũ hơn thời gian chọn sẽ bị xoá khỏi thiết bị này. Máy chủ không lưu tin nhắn, và thiết bị của {{ friendName }} có cài đặt riêng.
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
  font-size: 14px;
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
