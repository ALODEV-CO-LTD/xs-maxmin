'use client'
import { useEffect } from 'react'
import { usePathname, useRouter, useSearchParams } from 'next/navigation'
import { useAuthStore } from '@/lib/authStore'
import { REDIRECTS, routeOf } from '@/lib/routes'

// Route guard (port of router.beforeEach): public pages need no session; everything else sends a signed-out visitor to
// /login?redirect=...; admins stay in their own area and customers out of it.
export default function AuthGate({ children }: { children: React.ReactNode }) {
  const path = usePathname()
  const router = useRouter()
  const search = useSearchParams()
  const { token, role, user, fetchMe, adminHome, can } = useAuthStore()
  const route = routeOf(path)

  useEffect(() => {
    const old = REDIRECTS[path]
    if (old) return router.replace(old)
    if (path === '/') return router.replace(!token ? '/login' : role === 'admin' ? adminHome() : '/entries')
    if (!route) return router.replace('/')
    if (route.kind === 'public') return void (token && router.replace(role === 'admin' ? adminHome() : '/entries'))
    if (!token) return router.replace(`/login?redirect=${encodeURIComponent(path + (search.toString() ? '?' + search.toString() : ''))}`)
    if (!user) fetchMe().catch(() => {})
    if (route.kind === 'user' && role === 'admin') return router.replace(adminHome())
    if (route.kind === 'admin' && role !== 'admin') return router.replace('/')
    if (route.kind === 'admin' && user && ((route.rootOnly && !user.isRoot) || (route.perm && !can(route.perm)))) router.replace(adminHome())
  }, [path, token, role, user, route, router, search, fetchMe, adminHome, can])

  return <>{children}</>
}
