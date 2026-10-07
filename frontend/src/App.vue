<script setup>
import { watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import AppShell from './components/AppShell.vue'
import PrivacyGuard from './components/PrivacyGuard.vue'
import { useAuthStore } from './stores/auth'

const route = useRoute()
const router = useRouter()
const auth = useAuthStore()

// The session can die while a page is open (expired/revoked token -> api.js clears it on a 401).
// Without this the user stays on the page, which then only shows errors; send them to the login
// screen at once and bring them back to the same page afterwards.
watch(
  () => auth.isAuthenticated,
  (ok) => {
    if (ok || route.meta.public) return
    router.replace({ path: '/login', query: { redirect: route.fullPath } })
  },
)
</script>

<template>
  <!-- Khoá tự động + làm mờ khi rời trang (stores/privacy.js) -->
  <PrivacyGuard v-if="auth.isAuthenticated" />
  <AppShell v-if="!route.meta.public" />
  <RouterView v-else />
</template>
