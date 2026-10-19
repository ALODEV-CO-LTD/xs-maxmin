import { Suspense } from 'react'
import AccountPage from '@/features/account/AccountPage'

export default function Page() {
  return (
    <Suspense fallback={null}>
      <AccountPage />
    </Suspense>
  )
}
