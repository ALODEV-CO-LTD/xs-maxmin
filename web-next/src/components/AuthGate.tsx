'use client'
import { useEffect, useState } from 'react'
import { usePathname, useRouter, useSearchParams } from 'next/navigation'
import { useAuthStore } from '@/lib/authStore'
import { safeRedirect } from '@/lib/authFlow'
import { useNotifyStore } from '@/lib/notifyStore'
import { REDIRECTS, routeOf } from '@/lib/routes'

// Route guard (port of router.beforeEach): public pages need no session; everything else sends a signed-out visitor to
// /login?redirect=...; admins stay in their own area and customers out of it.
export default function AuthGate({ children }: { children: React.ReactNode }) {
  const path = usePathname()
  const router = useRouter()
  const search = useSearchParams()
  const { token, role, user, fetchMe, adminHome, can } = useAuthStore()
  const route = routeOf(path)
  // admin permissions (hence adminHome) come from the profile: wait for it once before any admin redirect (router.beforeEach awaits fetchMe the same way)
  const [meTried, setMeTried] = useState(false)

  useEffect(() => {
    if (token && role === 'admin' && !user && !meTried) {
      fetchMe().catch(() => {}).finally(() => setMeTried(true))
      return
    }
    const old = REDIRECTS[path]
    if (old) return router.replace(old)
    // Old Phản hồi address (bookmarks): open the popover on the page the person lands on.
    if (path === '/feedback') {
      if (token && role !== 'admin') useNotifyStore.setState({ supportOpen: true })
      return router.replace('/')
    }
    if (path === '/') return router.replace(!token ? '/login' : role === 'admin' ? adminHome() : '/entries')
    if (!route) return router.replace('/')
    // Signed in on /login: back to the page they were sent from (?redirect=), else their home.
    if (route.kind === 'public') {
      if (!token) useAuthStore.setState({ signedOutByUser: false })
      return void (token && router.replace(safeRedirect(search.get('redirect')) || (role === 'admin' ? adminHome() : '/entries')))
    }
    if (!token) {
      // An explicit logout lands on a clean /login: do not leave the next person (maybe another account) a link back
      // to the page the previous one was on.
      if (useAuthStore.getState().signedOutByUser) {
        useAuthStore.setState({ signedOutByUser: false })
        return router.replace('/login')
      }
      return router.replace(`/login?redirect=${encodeURIComponent(path + (search.toString() ? '?' + search.toString() : ''))}`)
    }
    if (!user) fetchMe().catch(() => {})
    if (route.kind === 'user' && role === 'admin') return router.replace(adminHome())
    if (route.kind === 'admin' && role !== 'admin') return router.replace('/')
    if (route.kind === 'admin' && user && ((route.rootOnly && !user.isRoot) || (route.perm && !can(route.perm)))) router.replace(adminHome())
  }, [path, token, role, user, meTried, route, router, search, fetchMe, adminHome, can])

  return <>{children}</>
}
