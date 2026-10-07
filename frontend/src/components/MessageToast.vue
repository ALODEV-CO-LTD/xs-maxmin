<!--
  Pop-up for a new message (friend chat or Phản hồi), mounted once in
  AppShell.vue. Tapping it opens the conversation. Driven by stores/notify.js.
-->
<script setup>
import AppIcon from './AppIcon.vue'
import { useNotifyStore } from '../stores/notify'

const notify = useNotifyStore()
</script>

<template>
  <div class="toast-stack" aria-live="polite">
    <button
      v-for="t in notify.toasts"
      :key="t.id"
      type="button"
      class="msg-toast"
      @click="notify.open(t)"
    >
      <span class="toast-icon"><AppIcon name="message-circle-more" /></span>
      <span class="toast-text">
        <strong>{{ t.title }}</strong>
        <span>{{ t.body }}</span>
      </span>
    </button>
  </div>
</template>

<style scoped>
.toast-stack {
  position: fixed;
  top: 72px;
  right: 16px;
  z-index: 60;
  display: flex;
  flex-direction: column;
  gap: 8px;
  max-width: min(360px, calc(100vw - 32px));
}
.msg-toast {
  display: flex;
  align-items: center;
  gap: 10px;
  text-align: left;
  padding: 10px 14px;
  background: var(--surface);
  color: var(--text);
  border: 1px solid var(--border);
  border-left: 4px solid var(--accent);
  border-radius: var(--radius-md);
  box-shadow: 0 6px 24px rgba(0, 0, 0, 0.25);
  cursor: pointer;
  font-family: var(--font-body);
}
.toast-icon {
  color: var(--accent);
  display: inline-flex;
}
.toast-text {
  display: flex;
  flex-direction: column;
  min-width: 0;
}
.toast-text span {
  color: var(--muted);
  font-size: 14px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
</style>
