<!--
  A figure that turns into "••••" while the "Ẩn số liệu" mask is on (see
  stores/mask.js). The real text is not rendered at all while masked.
  <MaskedValue :text="formatNumber(n)" />
-->
<script setup>
import { mask } from '../stores/mask'

defineProps({ text: { type: [String, Number], default: '' } })
const masked = mask.masked
</script>

<template>
  <span v-if="masked" class="masked" aria-label="Số liệu đã ẩn">••••</span>
  <span v-else>{{ text }}</span>
</template>

<style scoped>
.masked {
  letter-spacing: 0.1em;
  user-select: none;
}
</style>
