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
let tick = null
let observer = null

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
    `<svg xmlns="http://www.w3.org/2000/svg" width="340" height="190">` +
    `<g transform="rotate(-24 170 95)" fill="rgba(128,128,128,0.17)" font-family="system-ui,sans-serif" font-size="15" font-weight="600" text-anchor="middle">` +
    `<text x="170" y="88">${esc(who)}</text><text x="170" y="110" font-size="13" font-weight="500">${esc(when)} · ${esc(tail)}</text></g></svg>`
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
})
onBeforeUnmount(() => {
  clearInterval(tick)
  observer?.disconnect()
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
