<!--
  Cấu hình tính điểm mặc định (account-wide). The editor itself lives in components/ScoringConfigEditor.vue (it is also
  used per customer in Khách hàng > Xem chi tiết). Shown in a dialog on the Khách hàng page; `embedded` is kept for that.
-->
<script setup>
import ScoringConfigEditor from '../components/ScoringConfigEditor.vue'

defineProps({ embedded: { type: Boolean, default: false } })
const emit = defineEmits(['saved'])
</script>

<template>
  <div :class="embedded ? 'settings-embedded' : 'page'">
    <h1 v-if="!embedded" class="page-title">Cấu hình tính điểm</h1>
    <ScoringConfigEditor scope="default" @saved="emit('saved')" />
  </div>
</template>
