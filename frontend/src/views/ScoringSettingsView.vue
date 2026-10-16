<!--
  Cấu hình tính điểm mặc định (account-wide). The editor itself lives in components/ScoringConfigEditor.vue (it is also
  used per customer in Khách hàng > Xem chi tiết). A page of its own (menu "Cấu hình tính điểm"); `embedded` = the same editor inside the dialog opened from Khách hàng.
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
