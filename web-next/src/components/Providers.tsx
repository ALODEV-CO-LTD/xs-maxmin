'use client'
import { useEffect } from 'react'
import { useAuthStore } from '@/lib/authStore'
import AuthGate from './AuthGate'

// Runs once on the client before any screen renders: restore the session, register the offline shell cache.
export default function Providers({ children }: { children: React.ReactNode }) {
  const ready = useAuthStore((s) => s.ready)
  useEffect(() => {
    useAuthStore.getState().init()
    if ('serviceWorker' in navigator && process.env.NODE_ENV === 'production') {
      window.addEventListener('load', () => navigator.serviceWorker.register('/sw.js').catch(() => {}))
    }
  }, [])
  if (!ready) return null
  return <AuthGate>{children}</AuthGate>
}
