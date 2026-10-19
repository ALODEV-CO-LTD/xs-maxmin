'use client'
import './AppShell.css'
import Link from 'next/link'
import { usePathname, useRouter, useSearchParams } from 'next/navigation'
import { useEffect, useState } from 'react'
import AnnouncementBanner from './AnnouncementBanner'
import AppButton from './AppButton'
import AppIcon from './AppIcon'
import ConfirmDialog from './ConfirmDialog'
import MessageToast from './MessageToast'
import SupportChat from './SupportChat'
import SyncStatus from './SyncStatus'
import ThemeToggle from './ThemeToggle'
import { useAuthStore } from '@/lib/authStore'
import { showConfirm } from '@/lib/confirm'
import { shellRegistry } from '@/lib/hooks'
import { adminSupportUnreadOf, friendUnreadOf, supportUnreadOf, totalOf, useNotifyStore } from '@/lib/notifyStore'
import { startSync } from '@/lib/offline'
import { usePolicyStore } from '@/lib/policyStore'
import { backTargetOf } from '@/lib/routes'
import { teardownSession } from '@/lib/session'
import { linksFor } from '@/lib/navLinks'

// Persistent shell wrapping every authenticated page: top bar (brand, user name/role, logout) + nav (sidebar on
// desktop, dropdown menu on phones). Admin nav items only render for admins, filtered by permission.
//
// New nav entries go in lib/navLinks.js (the paths match lib/routes.ts).
const isActive = (path: string, href: string) => path === href || path.startsWith(href + '/')

export default function AppShell({ children }: { children: React.ReactNode }) {
  const router = useRouter()
  const path = usePathname()
  const search = useSearchParams()
  const user = useAuthStore((s) => s.user)
  const role = useAuthStore((s) => s.role)
  const can = useAuthStore((s) => s.can)
  const isAdmin = role === 'admin'
  const notifyTotal = useNotifyStore(totalOf)
  const friendBadge = useNotifyStore((s) => friendUnreadOf(s) + s.friendRequests)
  const adminBadge = useNotifyStore(adminSupportUnreadOf)
  const supportBadge = useNotifyStore(supportUnreadOf)
  void supportBadge
  const badgeFor = (k?: string) => (k === 'friends' ? friendBadge : k === 'admin-messages' ? adminBadge : 0)

  // Phones/tablets: header has [theme] [menu] [account]; the menu drops down from the header.
  const [menuOpen, setMenuOpen] = useState(false)
  // eslint-disable-next-line react-hooks/set-state-in-effect -- the menu closes on every navigation
  useEffect(() => setMenuOpen(false), [path, search])

  const links = linksFor(isAdmin, !!user?.isRoot, can)
  const back = backTargetOf(path, search)
  const displayName = user?.name || (isAdmin ? 'Quản trị viên' : 'Người dùng')

  // Go to the parent screen. When the browser history's previous entry already is that parent (the usual case) step
  // back so Back/forward stay in sync; otherwise (deep link, reload) replace the current entry, so no parent<->child
  // ping-pong is built up.
  function goBack() {
    if (!back) return
    const prev = document.referrer ? new URL(document.referrer).pathname : ''
    if (prev === back.path && window.history.length > 1) router.back()
    else router.replace(back.path)
  }

  // Mounted once for the whole authenticated app - so an incoming call can ring on any page.
  useEffect(() => {
    if (!useAuthStore.getState().user) useAuthStore.getState().fetchMe().catch(() => {})
    const cleanups = shellRegistry.shellStart.map((fn: () => void | (() => void)) => fn())
    startSync()
    usePolicyStore.getState().load()
    // Browsers only show the notification permission prompt after a click.
    const ask = () => useNotifyStore.getState().askPermission()
    window.addEventListener('pointerdown', ask, { once: true })
    // Real unread counts from the server now, and again whenever the tab is brought back to the front.
    const refresh = () => useNotifyStore.getState().refresh()
    refresh()
    const onVisible = () => !document.hidden && refresh()
    document.addEventListener('visibilitychange', onVisible)
    // Safety net: if the WebSocket push is blocked or silently dropped (mobile networks, proxies), badges and the open
    // chat still catch up within seconds.
    const poll = setInterval(() => !document.hidden && refresh(), 10000)
    return () => {
      window.removeEventListener('pointerdown', ask)
      document.removeEventListener('visibilitychange', onVisible)
      clearInterval(poll)
      cleanups.forEach((c: unknown) => typeof c === 'function' && c())
    }
  }, [])

  // End-to-end encrypted chat needs the account loaded (for its id), so start it as soon as the profile is there.
  useEffect(() => {
    if (user) shellRegistry.userReady.forEach((fn: (u: unknown) => void) => fn(user))
  }, [user?.id]) // eslint-disable-line react-hooks/exhaustive-deps

  async function logout() {
    if (!(await showConfirm({ title: 'Đăng xuất', message: 'Bạn có chắc muốn đăng xuất?', confirmText: 'Đăng xuất' }))) return
    teardownSession() // also run when the session ends any other way (Providers watches the token)
    useAuthStore.getState().logout()
    router.push('/login')
  }

  return (
    <div className="shell">
      <header className="topbar">
        <div className="brand" aria-label="MAMBA">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img className="brand-mark" src="/img/logo-mark.png" alt="" width={322} height={256} />
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img className="brand-word" src="/img/logo-word.png" alt="MAMBA" width={538} height={64} />
        </div>
        <div className="topbar-right">
          <SyncStatus />
          {!isAdmin && <SupportChat />}
          <ThemeToggle />
          <button
            type="button"
            className={`hdr-btn hdr-only-small${menuOpen ? ' hdr-btn-active' : ''}`}
            aria-expanded={menuOpen}
            aria-label="Menu"
            onClick={() => setMenuOpen(!menuOpen)}
            onKeyDown={(e) => e.key === 'Escape' && setMenuOpen(false)}
          >
            <AppIcon name="menu" />
            {notifyTotal > 0 && <span className="hdr-badge">{notifyTotal > 99 ? '99+' : notifyTotal}</span>}
          </button>
          <Link href="/account" className={`hdr-btn hdr-only-small${isActive(path, '/account') ? ' hdr-btn-active' : ''}`} aria-label="Tài khoản">
            <AppIcon name="user" />
          </Link>
          <span className="who">
            {displayName}
            <span className={`chip${isAdmin ? ' chip-brand' : ''}`}>{isAdmin ? 'Admin' : 'Khách hàng'}</span>
          </span>
          <AppButton variant="ghost" size="sm" onClick={logout}>Đăng xuất</AppButton>
        </div>
      </header>

      <div className="body">
        <nav className="sidenav">
          {links.map((link) => (
            <Link key={link.path} href={link.path} className={`nav-link${isActive(path, link.path) ? ' nav-link-active' : ''}`}>
              <span>{link.label}</span>
              {badgeFor(link.badge) > 0 && <span className="nav-badge">{badgeFor(link.badge)}</span>}
            </Link>
          ))}
        </nav>

        <main className="content">
          <AnnouncementBanner />
          {back && (
            <div className="back-bar">
              <button type="button" className="back-btn" onClick={goBack}>
                <AppIcon name="arrow-left" /> Quay lại{back.title && <span className="back-to">: {back.title}</span>}
              </button>
            </div>
          )}
          {children}
        </main>
      </div>

      {/* Phones / small tablets: menu dropping down from the header */}
      {menuOpen && (
        <div className="menu-overlay" onMouseDown={(e) => e.target === e.currentTarget && setMenuOpen(false)} onKeyDown={(e) => e.key === 'Escape' && setMenuOpen(false)}>
          <nav className="menu-dropdown" aria-label="Menu">
            {links.map((link) => (
              <Link key={link.path} href={link.path} className={`sheet-link${isActive(path, link.path) ? ' sheet-link-active' : ''}`}>
                <span>{link.label}</span>
                {badgeFor(link.badge) > 0 && <span className="nav-badge">{badgeFor(link.badge)}</span>}
              </Link>
            ))}
          </nav>
        </div>
      )}

      {shellRegistry.shellOverlays.map((Overlay: React.ComponentType, i: number) => (
        <Overlay key={i} />
      ))}
      <MessageToast />
      <ConfirmDialog />
    </div>
  )
}
