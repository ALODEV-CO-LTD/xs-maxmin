<!--
  Viewer watermark (A09 / K33). A web page cannot block or detect screenshots, so
  every screen carries a faint, tiled mark with who is looking and when. A leaked
  screenshot then shows whose account it came from and the minute it was taken.
  It never blocks clicks (pointer-events: none), follows the admin's on/off switch
  (stores/policy.js) and puts itself back if the element is removed or restyled
  from the browser tools. That is a deterrent, not protection: only an app can
  really stop screenshots.
-->
<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { useAuthStore } from '../stores/auth'
import { usePolicyStore } from '../stores/policy'

const auth = useAuthStore()
const policy = usePolicyStore()
const el = ref(null)
const now = ref(new Date())

// The mark must stay readable on a white page and on a dark one: dark ink on light
// themes, light ink on dark ones (follows <html data-theme> and the OS setting).
const mq = window.matchMedia('(prefers-color-scheme: dark)')
const readDark = () => {
  const t = document.documentElement.getAttribute('data-theme')
  return t ? t === 'dark' : mq.matches
}
const dark = ref(readDark())
const onTheme = () => (dark.value = readDark())
let tick = null
let observer = null
let themeObserver = null

const pad = (n) => String(n).padStart(2, '0')
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' })[c])

// Tile: name · username on one line, minute + id tail on the next, rotated.
const tile = computed(() => {
  const u = auth.user
  if (!u) return ''
  const d = now.value
  const when = `${pad(d.getHours())}:${pad(d.getMinutes())} ${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()}`
  const who = `${u.name || ''} · ${u.username || ''}`.slice(0, 40)
  const tail = String(u.id || '').slice(-4)
  const svg =
    `<svg xmlns="http://www.w3.org/2000/svg" width="380" height="210">` +
    `<g transform="rotate(-24 190 105)" fill="${dark.value ? 'rgba(255,255,255,0.15)' : 'rgba(30,41,59,0.20)'}" font-family="system-ui,sans-serif" font-size="15" font-weight="600" text-anchor="middle">` +
    `<text x="190" y="98">${esc(who)}</text><text x="190" y="120" font-size="13" font-weight="500">${esc(when)} · ${esc(tail)}</text></g></svg>`
  return `url("data:image/svg+xml;utf8,${encodeURIComponent(svg)}")`
})

const styleText = computed(
  () =>
    `position:fixed!important;inset:0!important;z-index:2147483000!important;pointer-events:none!important;display:block!important;` +
    `visibility:visible!important;opacity:1!important;background-image:${tile.value}!important;background-repeat:repeat!important;`,
)

const shown = computed(() => policy.watermarkEnabled && !!auth.user)

function guard() {
  // Removed from the page, or its style tampered with: restore.
  if (!shown.value) return
  // Vue cannot re-render into a node somebody detached, so put the very same element back.
  if (el.value && !el.value.isConnected) document.body.appendChild(el.value)
  if (el.value && el.value.getAttribute('style') !== styleText.value) el.value.setAttribute('style', styleText.value)
}

onMounted(() => {
  tick = setInterval(() => (now.value = new Date()), 30000)
  observer = new MutationObserver(guard)
  observer.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['style', 'class', 'hidden'] })
  themeObserver = new MutationObserver(onTheme)
  themeObserver.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] })
  mq.addEventListener('change', onTheme)
})
onBeforeUnmount(() => {
  clearInterval(tick)
  observer?.disconnect()
  themeObserver?.disconnect()
  mq.removeEventListener('change', onTheme)
})
</script>

<template>
  <div v-if="shown" ref="el" class="screen-watermark" aria-hidden="true" :style="styleText"></div>
</template>

<style>
.screen-watermark {
  user-select: none;
  -webkit-user-select: none;
}
@media print {
  .screen-watermark {
    display: block !important;
  }
}
</style>
