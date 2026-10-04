<!--
  Themed dropdown that replaces the native <select>. The native popup is drawn
  by the OS: it covers the control it belongs to and ignores the app's
  Light/Dark theme. This one opens below (or above, when there is no room),
  never covers its trigger, and uses the theme tokens.

  Drop-in usage - keep the <option> children exactly as for <select>:
    <AppSelect v-model="x" id="a" required class="my-class">
      <option value="">-- Chon --</option>
      <option v-for="c in list" :key="c.id" :value="c.id">{{ c.name }}</option>
    </AppSelect>
  `class` lands on the wrapper (set `height` there to resize); other attrs
  (id, aria-*) go to the trigger button.
-->
<script setup>
import { computed, nextTick, onBeforeUnmount, ref, useSlots, Fragment, Text } from 'vue'
import AppIcon from './AppIcon.vue'

defineOptions({ inheritAttrs: false })
const props = defineProps({
  modelValue: { default: '' },
  modelModifiers: { type: Object, default: () => ({}) },
  required: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
})
const emit = defineEmits(['update:modelValue'])
const slots = useSlots()

function textOf(children) {
  if (children == null) return ''
  if (typeof children === 'string') return children
  if (Array.isArray(children)) return children.map(textOf).join('')
  if (children && typeof children === 'object' && 'children' in children) return textOf(children.children)
  return ''
}
function collect(nodes, out) {
  for (const n of nodes || []) {
    if (n.type === Fragment) collect(n.children, out)
    else if (n.type === 'option') {
      const label = textOf(n.children).trim()
      const p = n.props || {}
      out.push({ value: p.value !== undefined ? p.value : label, label, disabled: p.disabled !== undefined && p.disabled !== false, hidden: p.hidden !== undefined && p.hidden !== false })
    }
  }
  return out
}
const options = computed(() => collect(slots.default?.(), []))
const selected = computed(() => options.value.find((o) => o.value === props.modelValue))
const label = computed(() => selected.value?.label ?? '')
const isPlaceholder = computed(() => props.modelValue === '' || props.modelValue == null)

const open = ref(false)
const menuStyle = ref({})
const active = ref(-1)
const root = ref(null)
const list = ref(null)

function openMenu() {
  if (props.disabled) return
  // fixed positioning so the menu is never clipped by an overflow:auto parent (e.g. tables)
  const r = root.value.getBoundingClientRect()
  const flip = window.innerHeight - r.bottom < 280 && r.top > 280
  menuStyle.value = flip
    ? { left: r.left + 'px', width: r.width + 'px', bottom: window.innerHeight - r.top + 4 + 'px' }
    : { left: r.left + 'px', width: r.width + 'px', top: r.bottom + 4 + 'px' }
  active.value = Math.max(0, options.value.findIndex((o) => o.value === props.modelValue))
  open.value = true
  document.addEventListener('mousedown', onOutside)
  window.addEventListener('scroll', onScrollAway, true)
  window.addEventListener('resize', closeMenu)
  nextTick(() => list.value?.querySelector('[data-active="true"]')?.scrollIntoView({ block: 'nearest' }))
}
function closeMenu() {
  open.value = false
  document.removeEventListener('mousedown', onOutside)
  window.removeEventListener('scroll', onScrollAway, true)
  window.removeEventListener('resize', closeMenu)
}
function onScrollAway(e) {
  if (list.value && list.value.contains(e.target)) return
  closeMenu()
}
function onOutside(e) {
  if (root.value && !root.value.contains(e.target)) closeMenu()
}
function choose(o) {
  if (o.disabled) return
  emit('update:modelValue', o.value)
  closeMenu()
}
function move(delta) {
  const n = options.value.length
  if (!n) return
  let i = active.value
  for (let k = 0; k < n; k++) {
    i = (i + delta + n) % n
    if (!options.value[i].disabled) break
  }
  active.value = i
  nextTick(() => list.value?.querySelector('[data-active="true"]')?.scrollIntoView({ block: 'nearest' }))
}
function onKey(e) {
  if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
    e.preventDefault()
    if (!open.value) openMenu()
    else move(e.key === 'ArrowDown' ? 1 : -1)
  } else if (e.key === 'Enter' || e.key === ' ') {
    if (open.value) {
      e.preventDefault()
      const o = options.value[active.value]
      if (o) choose(o)
    } else if (e.key === ' ') {
      e.preventDefault()
      openMenu()
    }
  } else if (e.key === 'Escape' && open.value) {
    e.preventDefault()
    closeMenu()
  } else if (e.key === 'Tab' && open.value) {
    closeMenu()
  }
}
onBeforeUnmount(closeMenu)
</script>

<template>
  <div ref="root" class="app-select" :class="[$attrs.class, { 'is-open': open, 'is-disabled': disabled }]">
    <button
      v-bind="{ ...$attrs, class: undefined, style: undefined }"
      type="button"
      class="app-select-trigger"
      role="combobox"
      aria-haspopup="listbox"
      :aria-expanded="open"
      :disabled="disabled"
      @click="open ? closeMenu() : openMenu()"
      @keydown="onKey"
    >
      <span class="app-select-label" :class="{ placeholder: isPlaceholder }">{{ label }}</span>
      <AppIcon name="chevron-down" class="app-select-chevron" />
    </button>
    <!-- keeps native `required` validation working on the enclosing form -->
    <input
      class="app-select-native"
      tabindex="-1"
      aria-hidden="true"
      :required="required"
      :value="isPlaceholder ? '' : String(modelValue)"
      @focus="$el.querySelector('.app-select-trigger')?.focus()"
    />
    <ul v-if="open" ref="list" class="app-select-menu" :style="menuStyle" role="listbox">
      <li
        v-for="(o, i) in options"
        v-show="!o.hidden"
        :key="i"
        role="option"
        class="app-select-option"
        :class="{ selected: o.value === modelValue, disabled: o.disabled }"
        :aria-selected="o.value === modelValue"
        :data-active="i === active"
        @mousedown.prevent="choose(o)"
        @mousemove="active = i"
      >
        <span>{{ o.label }}</span>
        <AppIcon v-if="o.value === modelValue" name="check" class="app-select-check" />
      </li>
    </ul>
  </div>
</template>

<style scoped>
.app-select {
  position: relative;
  width: 100%;
  height: var(--ctl-h, 44px);
}
.app-select-trigger {
  width: 100%;
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  padding: 0 12px 0 14px;
  font-family: var(--font-body);
  font-size: 15px;
  font-weight: inherit;
  text-align: left;
  color: var(--text-primary);
  background: var(--surface);
  border: 1px solid var(--input-border);
  border-radius: 10px;
  cursor: pointer;
  transition: border-color 0.15s ease, box-shadow 0.15s ease;
}
.app-select-trigger:hover:not(:disabled) {
  border-color: var(--input-border-hover);
}
.app-select-trigger:focus-visible,
.app-select.is-open .app-select-trigger {
  outline: none;
  border-color: var(--primary);
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--primary) 35%, transparent);
}
.app-select-trigger:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}
.app-select-label {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.app-select-label.placeholder {
  color: var(--text-secondary);
}
.app-select-chevron {
  flex: none;
  width: 18px;
  height: 18px;
  color: var(--text-secondary);
  transition: transform 0.15s ease;
}
.is-open .app-select-chevron {
  transform: rotate(180deg);
}
.app-select-native {
  position: absolute;
  left: 0;
  bottom: 0;
  width: 1px;
  height: 1px;
  padding: 0;
  border: 0;
  opacity: 0;
  pointer-events: none;
}
.app-select-menu {
  position: fixed;
  z-index: 60;
  max-height: 280px;
  margin: 0;
  padding: 4px;
  overflow-y: auto;
  list-style: none;
  background: var(--card);
  border: 1px solid var(--input-border);
  border-radius: 12px;
  box-shadow: var(--shadow-lg);
}
.app-select-option {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  min-height: 40px;
  padding: 0 12px;
  font-size: 15px;
  color: var(--text-primary);
  border-radius: 8px;
  cursor: pointer;
}
.app-select-option[data-active='true'] {
  background: var(--surface);
}
.app-select-option.selected {
  font-weight: 700;
}
.app-select-option.disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
.app-select-check {
  flex: none;
  width: 16px;
  height: 16px;
  color: var(--primary);
}
</style>
