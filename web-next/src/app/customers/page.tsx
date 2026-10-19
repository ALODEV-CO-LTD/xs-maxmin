import { Suspense } from 'react'
import CustomersScreen from '@/features/customers/CustomersScreen'

// useSearchParams (?from=entries, ?config=default) needs a Suspense boundary in a static export.
export default function Page() {
  return (
    <Suspense>
      <CustomersScreen />
    </Suspense>
  )
}
