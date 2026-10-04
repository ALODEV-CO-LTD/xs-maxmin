<!--
  Password <input> with a show/hide toggle. Extra attrs (id, placeholder,
  autocomplete, aria-*, disabled, @blur...) go straight to the <input>.
-->
<script setup>
import { ref } from 'vue'
import AppIcon from './AppIcon.vue'

defineOptions({ inheritAttrs: false })
const model = defineModel({ type: String, default: '' })
const visible = ref(false)
</script>

<template>
  <div class="input-wrap pw-wrap">
    <input v-bind="$attrs" v-model="model" :type="visible ? 'text' : 'password'" />
    <button
      type="button"
      class="pw-toggle"
      :aria-label="visible ? 'Ẩn mật khẩu' : 'Hiện mật khẩu'"
      :aria-pressed="visible"
      :disabled="$attrs.disabled"
      @click="visible = !visible"
    >
      <AppIcon :name="visible ? 'eye-off' : 'eye'" />
    </button>
  </div>
</template>

<style scoped>
.pw-wrap :deep(input) {
  padding-right: 52px;
}

.pw-toggle {
  position: absolute;
  top: 2px;
  right: 2px;
  width: 44px;
  height: 44px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 0;
  font-size: 20px;
  color: var(--muted);
  background: transparent;
  border: 0;
  border-radius: 8px;
  cursor: pointer;
  transition: color 0.15s ease, background 0.15s ease;
}

.pw-toggle:hover:not(:disabled) {
  color: var(--text);
  background: color-mix(in srgb, var(--text) 8%, transparent);
}

.pw-toggle:focus-visible {
  outline: 3px solid color-mix(in srgb, var(--focus) 60%, transparent);
  outline-offset: -2px;
}

.pw-toggle:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}
</style>
