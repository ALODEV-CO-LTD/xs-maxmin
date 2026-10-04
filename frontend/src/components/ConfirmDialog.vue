<!-- Centred confirmation box driven by src/confirm.js. Mounted once in AppShell. -->
<script setup>
import { nextTick, ref, watch } from 'vue'
import { confirmState, resolveConfirm } from '../confirm'

const box = ref(null)
const cancelBtn = ref(null)
const okBtn = ref(null)
let lastFocus = null

watch(
  () => confirmState.open,
  async (open) => {
    if (open) {
      lastFocus = document.activeElement
      await nextTick()
      // destructive actions focus "Huỷ" first so a stray Enter can't confirm them
      ;(confirmState.danger ? cancelBtn.value : okBtn.value)?.focus()
    } else if (lastFocus && typeof lastFocus.focus === 'function') {
      lastFocus.focus()
      lastFocus = null
    }
  },
)

function onKey(e) {
  if (e.key === 'Escape') {
    e.preventDefault()
    resolveConfirm(false)
  } else if (e.key === 'Tab') {
    // keep focus inside the dialog
    const items = [cancelBtn.value, okBtn.value].filter(Boolean)
    const i = items.indexOf(document.activeElement)
    e.preventDefault()
    items[(i + (e.shiftKey ? -1 : 1) + items.length) % items.length]?.focus()
  }
}
</script>

<template>
  <Teleport to="body">
    <div v-if="confirmState.open" class="cd-overlay" @mousedown.self="resolveConfirm(false)" @keydown="onKey">
      <div
        ref="box"
        class="cd-box"
        role="alertdialog"
        aria-modal="true"
        aria-labelledby="cd-title"
        aria-describedby="cd-message"
      >
        <h2 id="cd-title" class="cd-title">{{ confirmState.title }}</h2>
        <p id="cd-message" class="cd-message">{{ confirmState.message }}</p>
        <div class="cd-actions">
          <button ref="cancelBtn" type="button" class="btn btn-secondary" @click="resolveConfirm(false)">
            {{ confirmState.cancelText }}
          </button>
          <button
            ref="okBtn"
            type="button"
            class="btn"
            :class="confirmState.danger ? 'btn-danger' : 'btn-primary'"
            @click="resolveConfirm(true)"
          >
            {{ confirmState.confirmText }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.cd-overlay {
  position: fixed;
  inset: 0;
  z-index: 100;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 16px;
  background: var(--overlay);
}
.cd-box {
  width: 100%;
  max-width: 400px;
  padding: 24px;
  background: var(--card);
  border: 1px solid var(--input-border);
  border-radius: 16px;
  box-shadow: var(--shadow-lg);
}
.cd-title {
  margin: 0 0 8px;
  font-size: 18px;
  line-height: 1.3;
}
.cd-message {
  margin: 0 0 24px;
  font-size: 15px;
  line-height: 1.5;
  color: var(--text-secondary);
  overflow-wrap: anywhere;
}
.cd-actions {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
}
.cd-actions .btn {
  min-height: 40px;
  padding: 0 18px;
  font-size: 14px;
  font-weight: 600;
  border-radius: 10px;
}
.cd-actions .btn:focus-visible {
  outline: 3px solid color-mix(in srgb, var(--primary) 55%, transparent);
  outline-offset: 2px;
}
@media (max-width: 480px) {
  .cd-actions {
    flex-direction: column-reverse;
  }
  .cd-actions .btn {
    width: 100%;
  }
}
</style>
