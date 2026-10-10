<!--
  Persistent shell wrapping every authenticated page: top bar (brand, user
  name/role, logout) + nav (sidebar on desktop, bottom bar on mobile).
  Admin nav items only render when auth.isAdmin.

  Other agents: add new nav entries here (both `userLinks`/`adminLinks`
  arrays below) as real views replace PlaceholderView in the router - the
  route `name`/`path` values already match what's in src/router/index.js.
-->
<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '../stores/auth'
import { useCallStore } from '../stores/call'
import CallOverlay from './CallOverlay.vue'
import MessageToast from './MessageToast.vue'
import { useNotifyStore } from '../stores/notify'
import ConfirmDialog from './ConfirmDialog.vue'
import { showConfirm } from '../confirm'
import AppIcon from './AppIcon.vue'
import ThemeToggle from './ThemeToggle.vue'
import SupportChat from './SupportChat.vue'
import SyncStatus from './SyncStatus.vue'
import AnnouncementBanner from './AnnouncementBanner.vue'
import { startSync } from '../offline'

const auth = useAuthStore()
const call = useCallStore()
const notify = useNotifyStore()

// Unread count shown next to a nav entry (new messages pushed by the server).
function badgeFor(name) {
  if (name === 'friends') return notify.friendUnread
  if (name === 'feedback') return notify.supportUnread
  if (name === 'admin-messages') return notify.adminSupportUnread
  return 0
}
const router = useRouter()
const route = useRoute()

// Phones/tablets: header has [theme] [menu] [account]; the menu drops down from the header.
const menuOpen = ref(false)
watch(
  () => route.fullPath,
  () => {
    menuOpen.value = false
  },
)
function onMenuKey(e) {
  if (e.key === 'Escape') menuOpen.value = false
}

const userLinks = [
  { name: 'entries', label: 'Nhập số', icon: 'pencil' },
  { name: 'results', label: 'Nhập kết quả', icon: 'pencil-line' },
  { name: 'scoring', label: 'Tính điểm', icon: 'calculator' },
  { name: 'scoring-settings', label: 'Cấu hình tính điểm', icon: 'settings' },
  { name: 'customers', label: 'Khách hàng', icon: 'users' },
  { name: 'friends', label: 'Bạn bè', icon: 'message-circle-more' },
  { name: 'packages', label: 'Gói & Thanh toán', icon: 'badge-dollar-sign' },
  { name: 'account', label: 'Tài khoản', icon: 'user' },
]

const adminLinks = [
  { name: 'admin-users', label: 'Khách hàng', icon: 'users' },
  { name: 'admin-stats', label: 'Thống kê', icon: 'chart-column-increasing' },
  { name: 'admin-payment-requests', label: 'Duyệt thanh toán', icon: 'circle-check' },
  { name: 'admin-renewals', label: 'Gia hạn', icon: 'refresh-cw' },
  { name: 'admin-messages', label: 'Phản hồi', icon: 'message-square-more' },
  { name: 'admin-notices', label: 'Thông báo', icon: 'message-square-more' },
  { name: 'admin-backups', label: 'Sao lưu', icon: 'refresh-cw' },
  { name: 'admin-settings', label: 'Cài đặt', icon: 'settings' },
  // Admin dùng chung trang /account với khách hàng (đổi mật khẩu...). Admin
  // không có mục "Bạn bè": liên hệ với khách chỉ qua "Phản hồi" ở trên.
  { name: 'account', label: 'Tài khoản', icon: 'user' },
]

const links = computed(() => (auth.isAdmin ? adminLinks : userLinks))

// Back button (K44): child screens declare `meta.parent` (route name) in
// router/index.js; /customers opened from Nhập số goes back there. The same
// button, size and place on every child screen.
const backTarget = computed(() => {
  const parent = route.meta.parent || (route.name === 'customers' && route.query.from === 'entries' ? 'entries' : null)
  if (!parent) return null
  const target = router.resolve({ name: parent })
  return { name: parent, title: target.meta?.title || '' }
})

// Go to the parent screen. When the browser history's previous entry already is that
// parent (the usual case) step back so Back/forward stay in sync; otherwise (deep link,
// reload) replace the current entry, so no parent<->child ping-pong is built up.
function goBack() {
  if (!backTarget.value) return
  const parentPath = router.resolve({ name: backTarget.value.name }).path
  const prev = typeof window.history.state?.back === 'string' ? window.history.state.back.split('?')[0] : ''
  if (prev === parentPath) router.back()
  else router.replace({ name: backTarget.value.name })
}

const displayName = computed(() => auth.user?.name || (auth.isAdmin ? 'Quản trị viên' : 'Người dùng'))

onMounted(() => {
  if (!auth.user) {
    auth.fetchMe().catch(() => {})
  }
  // Mounted once for the whole authenticated app - so an incoming call can
  // ring on any page, not only while the Bạn bè tab happens to be open.
  call.connect()
  startSync()
  // Browsers only show the notification permission prompt after a click.
  window.addEventListener('pointerdown', () => notify.askPermission(), { once: true })
  // Real unread counts from the server now, and again whenever the tab is
  // brought back to the front.
  notify.refresh()
  document.addEventListener('visibilitychange', onVisible)
  // Safety net: if the WebSocket push is blocked or silently dropped (mobile
  // networks, proxies), badges and the open chat still catch up within seconds.
  pollTimer = setInterval(() => {
    if (!document.hidden) notify.refresh()
  }, 10000)
})
let pollTimer = null
onBeforeUnmount(() => {
  document.removeEventListener('visibilitychange', onVisible)
  clearInterval(pollTimer)
})
function onVisible() {
  if (!document.hidden) notify.refresh()
}

async function logout() {
  if (!(await showConfirm({ title: 'Đăng xuất', message: 'Bạn có chắc muốn đăng xuất?', confirmText: 'Đăng xuất' }))) return
  call.disconnect()
  notify.clearAll()
  auth.logout()
  router.push('/login')
}
</script>

<template>
  <div class="shell">
    <header class="topbar">
      <div class="brand" aria-label="MAMBA">
        <img class="brand-mark" src="../assets/logo-mark.png" alt="" width="322" height="256" />
        <img class="brand-word" src="../assets/logo-word.png" alt="MAMBA" width="538" height="64" />
      </div>
      <div class="topbar-right">
        <SyncStatus />
        <SupportChat v-if="!auth.isAdmin" />
        <ThemeToggle />
        <button
          type="button"
          class="hdr-btn hdr-only-small"
          :class="{ 'hdr-btn-active': menuOpen }"
          :aria-expanded="menuOpen"
          aria-label="Menu"
          @click="menuOpen = !menuOpen"
          @keydown="onMenuKey"
        >
          <AppIcon name="menu" />
          <span v-if="notify.total" class="hdr-badge">{{ notify.total > 99 ? '99+' : notify.total }}</span>
        </button>
        <RouterLink :to="{ name: 'account' }" class="hdr-btn hdr-only-small" active-class="hdr-btn-active" aria-label="Tài khoản">
          <AppIcon name="user" />
        </RouterLink>
        <span class="who">
          {{ displayName }}
          <span class="chip" :class="auth.isAdmin ? 'chip-brand' : ''">{{
            auth.isAdmin ? 'Admin' : 'Khách hàng'
          }}</span>
        </span>
        <button class="btn btn-ghost btn-sm" @click="logout">Đăng xuất</button>
      </div>
    </header>

    <div class="body">
      <nav class="sidenav">
        <RouterLink
          v-for="link in links"
          :key="link.name"
          :to="{ name: link.name }"
          class="nav-link"
          active-class="nav-link-active"
        >
          <span>{{ link.label }}</span>
          <span v-if="badgeFor(link.name)" class="nav-badge">{{ badgeFor(link.name) }}</span>
        </RouterLink>
      </nav>

      <main class="content">
        <AnnouncementBanner />
        <div v-if="backTarget" class="back-bar">
          <button type="button" class="back-btn" @click="goBack">
            <AppIcon name="arrow-left" /> Quay lại<span v-if="backTarget.title" class="back-to">: {{ backTarget.title }}</span>
          </button>
        </div>
        <RouterView />
      </main>
    </div>

    <!-- Phones / small tablets: menu dropping down from the header -->
    <div v-if="menuOpen" class="menu-overlay" @mousedown.self="menuOpen = false" @keydown="onMenuKey">
      <nav class="menu-dropdown" aria-label="Menu">
        <RouterLink
          v-for="link in links"
          :key="link.name"
          :to="{ name: link.name }"
          class="sheet-link"
          active-class="sheet-link-active"
        >
          <span>{{ link.label }}</span>
          <span v-if="badgeFor(link.name)" class="nav-badge">{{ badgeFor(link.name) }}</span>
        </RouterLink>
      </nav>
    </div>

    <CallOverlay />
    <MessageToast />
    <ConfirmDialog />
  </div>
</template>

<style scoped>
.shell {
  min-height: 100vh;
  display: flex;
  flex-direction: column;
}

.topbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  min-height: 64px;
  padding: 8px 24px;
  background: var(--header);
  border-bottom: 1px solid var(--border);
  color: var(--text-primary);
  position: sticky;
  top: 0;
  z-index: 10;
}

.brand {
  display: flex;
  align-items: center;
  gap: 10px;
}
.brand-mark {
  height: 28px;
  width: auto;
}
.brand-word {
  height: 13px;
  width: auto;
}

.topbar-right {
  display: flex;
  align-items: center;
  gap: 16px;
  min-width: 0;
}

.who {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 14px;
  font-weight: 700;
  padding-right: 16px;
  border-right: 1px solid var(--border);
}

.who .chip-brand {
  color: var(--link);
  background: var(--primary-soft);
  border-color: color-mix(in srgb, var(--primary) 35%, transparent);
}

.who .chip {
  font-size: 14px;
  padding: 4px 10px;
  color: color-mix(in srgb, var(--text-secondary) 80%, var(--text-primary));
  background: var(--surface);
  border: 1px solid var(--border);
  white-space: nowrap;
}

.topbar-right .btn-ghost {
  white-space: nowrap;
  min-height: 40px;
  padding: 0 16px;
  font-size: 14px;
  font-weight: 700;
  color: var(--text-primary);
  border: 1px solid var(--input-border);
  border-radius: 10px;
}

.topbar-right .btn-ghost:hover {
  background: var(--surface);
  border-color: var(--input-border-hover);
}

.topbar-right .btn-ghost:focus-visible {
  outline: 3px solid color-mix(in srgb, var(--primary) 55%, transparent);
  outline-offset: 2px;
}

.body {
  flex: 1;
  display: flex;
  width: 100%;
  max-width: 1440px;
  margin: 0 auto;
}

.sidenav {
  display: none;
  flex-direction: column;
  gap: 4px;
  width: 248px;
  flex-shrink: 0;
  padding: 16px;
  margin: 16px 0 16px 16px;
  background: var(--sidebar);
  border: 1px solid var(--border);
  border-radius: 16px;
  position: sticky;
  top: 80px;
  align-self: flex-start;
  max-height: calc(100vh - 96px);
  overflow-y: auto;
}

.hdr-badge {
  position: absolute;
  top: -4px;
  right: -4px;
  min-width: 18px;
  padding: 0 5px;
  border-radius: 999px;
  background: var(--danger, #ef4444);
  color: #fff;
  font-size: 11px;
  font-weight: 700;
  line-height: 18px;
  text-align: center;
  box-shadow: 0 0 0 2px var(--bg, #111);
}
.nav-badge {
  margin-left: auto;
  min-width: 20px;
  padding: 1px 6px;
  border-radius: 999px;
  background: var(--danger, #ef4444);
  color: #fff;
  font-size: 12px;
  font-weight: 700;
  text-align: center;
  line-height: 18px;
}
.nav-link {
  position: relative;
  display: flex;
  align-items: center;
  gap: 12px;
  min-height: 48px;
  padding: 0 14px;
  border-radius: 12px;
  color: var(--text);
  text-decoration: none;
  font-weight: 700;
  font-size: 15px;
  transition: background 0.15s ease;
}

.nav-link:hover {
  background: var(--surface-2);
}

.nav-link:focus-visible {
  outline: 3px solid color-mix(in srgb, var(--focus) 60%, transparent);
  outline-offset: 2px;
}

.nav-link-active,
.nav-link-active:hover {
  background: var(--accent-soft);
  color: var(--text);
  font-weight: 700;
  box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--accent) 45%, transparent);
}

.nav-link-active::before {
  content: '';
  position: absolute;
  left: 0;
  top: 10px;
  bottom: 10px;
  width: 4px;
  border-radius: 0 4px 4px 0;
  background: var(--accent);
}

.content {
  flex: 1;
  min-width: 0;
}

/* Back button for child screens - 44px touch target */
.back-bar {
  max-width: var(--page-max);
  margin: 0 auto;
  padding: 12px 16px 0;
}
.back-btn {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  min-height: 44px;
  min-width: 44px;
  padding: 0 16px 0 12px;
  font-family: inherit;
  font-size: 15px;
  font-weight: 700;
  color: var(--text-primary);
  background: var(--surface);
  border: 1px solid var(--input-border);
  border-radius: 12px;
  cursor: pointer;
}
.back-btn:hover {
  border-color: var(--input-border-hover);
  background: var(--surface-2);
}
.back-btn:focus-visible {
  outline: 3px solid color-mix(in srgb, var(--primary) 55%, transparent);
  outline-offset: 2px;
}
.back-to {
  font-weight: 600;
  color: var(--text-secondary);
}

/* Header buttons (menu + account), phones/small tablets only */
.hdr-btn {
  position: relative;
  width: 44px;
  height: 44px;
  flex: none;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 0;
  font-size: 22px;
  color: var(--text-secondary);
  text-decoration: none;
  background: transparent;
  border: 1px solid transparent;
  border-radius: 10px;
  cursor: pointer;
  transition: color 0.15s ease, background 0.15s ease, border-color 0.15s ease;
}

.hdr-btn:hover {
  color: var(--text);
  background: var(--surface);
  border-color: var(--border);
}

.hdr-btn:focus-visible {
  outline: 3px solid color-mix(in srgb, var(--primary) 55%, transparent);
  outline-offset: 2px;
}

.hdr-btn[aria-label='Tài khoản'] {
  font-size: 30px;
}

.hdr-btn-active {
  color: var(--accent);
  background: var(--primary-soft);
}

/* Dropdown menu under the header */
.menu-overlay {
  position: fixed;
  inset: 64px 0 0 0;
  z-index: 25;
  background: var(--overlay);
}

.menu-dropdown {
  position: absolute;
  top: 8px;
  right: 12px;
  width: min(300px, calc(100vw - 24px));
  max-height: calc(100vh - 64px - 24px);
  padding: 8px;
  overflow-y: auto;
  background: var(--card);
  border: 1px solid var(--input-border);
  border-radius: 14px;
  box-shadow: var(--shadow-lg);
}

.sheet-link {
  display: flex;
  align-items: center;
  gap: 12px;
  min-height: 48px;
  padding: 0 14px;
  color: var(--text);
  text-decoration: none;
  font-size: 16px;
  font-weight: 600;
  border-radius: 12px;
}

.sheet-link:hover {
  background: var(--surface);
}

.sheet-link-active {
  background: var(--accent-soft);
  font-weight: 700;
}

@media (max-width: 480px) {
  .topbar {
    padding: 8px 16px;
  }
  .topbar-right {
    gap: 2px;
  }
  .brand {
    gap: 8px;
  }
  .brand-word {
    height: 11px;
  }
  .who {
    padding-right: 8px;
    min-width: 0;
    overflow: hidden;
  }
  .topbar-right .btn-ghost {
    padding: 0 12px;
  }
}

/* below 860px the account (name + logout) lives behind the header account icon */
@media (max-width: 859px) {
  .who,
  .topbar-right .btn-ghost {
    display: none;
  }
}

@media (min-width: 860px) {
  /* Sidebar pinned to the left edge, full height below the header; the page
     content is offset by its width and scrolls independently of it. */
  .sidenav {
    display: flex;
    position: fixed;
    left: 0;
    top: 64px;
    bottom: 0;
    z-index: 5;
    margin: 0;
    height: calc(100vh - 64px);
    max-height: none;
    align-self: auto;
    border-width: 0 1px 0 0;
    border-radius: 0;
  }
  .body {
    max-width: none;
    margin: 0;
    padding-left: 248px;
  }
  .hdr-only-small,
  .menu-overlay {
    display: none;
  }
}
</style>
