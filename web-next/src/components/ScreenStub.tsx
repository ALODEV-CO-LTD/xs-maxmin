'use client'
import { routeOf } from '@/lib/routes'
import { usePathname } from 'next/navigation'

// Placeholder shown by a screen that is not converted yet (the Vue screen of the same name is still the live one).
export default function ScreenStub({ vue }: { vue: string }) {
  const route = routeOf(usePathname())
  return (
    <main style={{ padding: 24 }}>
      <h1>{route?.title ?? 'MAMBA'}</h1>
      <p style={{ color: 'var(--muted)' }}>Màn hình này đang được chuyển từ Vue sang Next.js ({vue}).</p>
    </main>
  )
}
