<!--
  Generic centred dialog shell (same look as ConfirmDialog / AddBetTypeDialog):
  overlay, title + optional description, scrolling body, footer slot. Esc or a
  click on the backdrop emits `close`; focus goes to the first
  [data-autofocus] (else first field) on open and returns to the opener on
  close. Used by PasswordPromptDialog, DeleteDataDialog and the schedule dialog.
-->
<script setup>
import { nextTick, ref, watch } from 'vue'

const props = defineProps({
  open: { type: Boolean, default: false },
  title: { type: String, default: '' },
  description: { type: String, default: '' },
  wide: { type: Boolean, default: false },
  xwide: { type: Boolean, default: false },
  closeButton: { type: Boolean, default: true }, // the X in the corner (Esc and a click outside also close) // very wide (about 960px): big forms such as Cấu hình tính điểm
})
const emit = defineEmits(['close'])

const box = ref(null)
let lastFocus = null

watch(
  () => props.open,
  async (open) => {
    if (open) {
      lastFocus = document.activeElement
      await nextTick()
      const el =
        box.value?.querySelector('[data-autofocus]') ||
        box.value?.querySelector('input:not([type=hidden]), select, textarea, button')
      el?.focus()
    } else if (lastFocus && typeof lastFocus.focus === 'function') {
      lastFocus.focus()
      lastFocus = null
    }
  },
)

function onKey(e) {
  if (e.key === 'Escape') {
    e.preventDefault()
    e.stopPropagation()
    emit('close')
  }
}
</script>

<template>
  <Teleport to="body">
    <div v-if="open" class="md-overlay" @mousedown.self="emit('close')" @keydown="onKey">
      <div ref="box" class="md-box" :class="{ 'md-wide': wide, 'md-xwide': xwide }" role="dialog" aria-modal="true" aria-labelledby="md-title">
        <div class="md-head">
          <h2 id="md-title" class="md-title">{{ title }}</h2>
          <button v-if="closeButton" type="button" class="md-close" aria-label="Đóng" title="Đóng" @click="emit('close')">
            <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18" /></svg>
          </button>
        </div>
        <p v-if="description" class="md-desc">{{ description }}</p>
        <div class="md-body"><slot /></div>
        <div v-if="$slots.footer" class="md-actions"><slot name="footer" /></div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.md-overlay {
  position: fixed;
  inset: 0;
  z-index: 90;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 16px;
  background: var(--overlay);
}
.md-box {
  display: flex;
  flex-direction: column;
  width: 100%;
  max-width: 440px;
  max-height: calc(100dvh - 32px);
  padding: 24px;
  background: var(--card);
  border: 1px solid var(--input-border);
  border-radius: 16px;
  box-shadow: var(--shadow-lg);
}
.md-box.md-xwide {
  max-width: 1080px;
  max-height: 92vh;
}
.md-box.md-wide {
  max-width: 600px;
}
.md-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
}
.md-close {
  flex: none;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 36px;
  height: 36px;
  margin: -6px -8px 0 0;
  padding: 0;
  color: var(--text-secondary);
  background: transparent;
  border: 0;
  border-radius: 10px;
  cursor: pointer;
}
.md-close:hover {
  color: var(--text-primary);
  background: var(--surface);
}
.md-title {
  margin: 0 0 8px;
  font-size: 18px;
  line-height: 1.3;
}
.md-desc {
  margin: 0 0 16px;
  font-size: 15px;
  line-height: 1.5;
  color: var(--text-secondary);
  overflow-wrap: anywhere;
}
.md-body {
  overflow-y: auto;
  min-height: 0;
  padding: 2px;
  margin: -2px;
}
.md-actions {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
  margin-top: 20px;
}
.md-actions :deep(.btn) {
  min-height: 44px;
  padding: 0 18px;
  font-size: 14px;
  font-weight: 600;
  border-radius: 10px;
}
@media (max-width: 480px) {
  .md-box {
    padding: 20px 16px;
  }
  .md-actions {
    flex-direction: column-reverse;
  }
  .md-actions :deep(.btn) {
    width: 100%;
  }
}
</style>
