import { createApp } from 'vue'
import { createPinia } from 'pinia'
import './styles/tokens.css'
import './styles/base.css'
import App from './App.vue'
import { router } from './router'
import { useAuthStore } from './stores/auth'
import { initTheme } from './theme'

initTheme()

const app = createApp(App)
app.use(createPinia())

// Restore session from localStorage before the router runs its first guard.
useAuthStore().init()

app.use(router)
app.mount('#app')

// Offline shell cache (production build only - in dev it would serve stale modules).
if ('serviceWorker' in navigator && import.meta.env.PROD) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').catch(() => {})
  })
}
