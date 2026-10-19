'use client'
import { Suspense, useEffect } from 'react'
import { usePathname, useRouter } from 'next/navigation'
import { useAuthStore } from '@/lib/authStore'
import { setNavigator } from '@/lib/hooks'
import { initTheme } from '@/lib/theme'
import { routeOf } from '@/lib/routes'
import { teardownSession } from '@/lib/session'
import { startScreenshotGuard, stopScreenshotGuard } from '@/lib/screenshotGuard'
import AppShell from './AppShell'
import AuthGate from './AuthGate'
import PrivacyGuard from './PrivacyGuard'
import ScreenWatermark from './ScreenWatermark'

// Runs once on the client before any screen renders: restore the session, apply the theme, register the offline shell
// cache. Then it frames the screen: public pages (login / register) stand alone, every other route sits inside the
// shell once the person is signed in (port of App.vue).
export default function Providers({ children }: { children: React.ReactNode }) {
  const ready = useAuthStore((s) => s.ready)
  const router = useRouter()
  useEffect(() => {
    initTheme()
    useAuthStore.getState().init()
    if ('serviceWorker' in navigator && process.env.NODE_ENV === 'production') {
      window.addEventListener('load', () => navigator.serviceWorker.register('/sw.js').catch(() => {}))
    }
  }, [])
  useEffect(() => setNavigator((to: string) => router.push(to)), [router])
  if (!ready) return null
  return (
    <Suspense fallback={null}>
      <div id="app">
        <AuthGate>
          <Frame>{children}</Frame>
        </AuthGate>
      </div>
    </Suspense>
  )
}

function Frame({ children }: { children: React.ReactNode }) {
  const path = usePathname()
  const token = useAuthStore((s) => s.token)
  const route = routeOf(path)

  // Desktop screenshot shortcuts cover the screen while signed in. Whatever ended the session (explicit logout,
  // auto-lock, 401 expiry), drop the old account's call socket, chat keys/db, unread counters and toasts.
  useEffect(() => {
    if (!token) return
    useAuthStore.setState({ signedOutByUser: false })
    startScreenshotGuard()
    return () => {
      stopScreenshotGuard()
      teardownSession()
    }
  }, [token])

  return (
    <>
      {token && <PrivacyGuard />}
      {token && <ScreenWatermark />}
      {!route ? null : route.kind === 'public' ? children : token ? <AppShell>{children}</AppShell> : null}
    </>
  )
}
