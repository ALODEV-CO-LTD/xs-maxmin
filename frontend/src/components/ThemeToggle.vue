<!-- Sun/Moon switch between Light and Dark. State lives in src/theme.js. -->
<script setup>
import { computed } from 'vue'
import AppIcon from './AppIcon.vue'
import { theme, toggleTheme } from '../theme'

const isDark = computed(() => theme.value === 'dark')
const label = computed(() => (isDark.value ? 'Chuyển sang giao diện sáng' : 'Chuyển sang giao diện tối'))
</script>

<template>
  <button type="button" class="theme-toggle" :aria-label="label" :title="label" @click="toggleTheme">
    <AppIcon :name="isDark ? 'sun' : 'moon'" />
  </button>
</template>

<style scoped>
.theme-toggle {
  width: 44px;
  height: 44px;
  flex: none;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 0;
  font-size: 20px;
  color: var(--text-secondary);
  background: transparent;
  border: 1px solid transparent;
  border-radius: 10px;
  cursor: pointer;
  transition: color 0.15s ease, background 0.15s ease, border-color 0.15s ease;
}

.theme-toggle:hover {
  color: var(--text-primary);
  background: var(--surface);
  border-color: var(--border);
}

.theme-toggle:focus-visible {
  outline: 3px solid color-mix(in srgb, var(--primary) 55%, transparent);
  outline-offset: 2px;
}
</style>
