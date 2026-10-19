import { Suspense } from 'react'
import MessagesView from '@/features/admin/MessagesView'

export default function Page() {
  return (
    <Suspense fallback={null}>
      <MessagesView />
    </Suspense>
  )
}
