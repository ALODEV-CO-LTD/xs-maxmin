<script setup>
import { useRoute } from 'vue-router'
import AppShell from './components/AppShell.vue'
import PrivacyGuard from './components/PrivacyGuard.vue'
import { useAuthStore } from './stores/auth'

const route = useRoute()
const auth = useAuthStore()
</script>

<template>
  <!-- Khoá tự động + làm mờ khi rời trang (stores/privacy.js) -->
  <PrivacyGuard v-if="auth.isAuthenticated" />
  <AppShell v-if="!route.meta.public" />
  <RouterView v-else />
</template>
