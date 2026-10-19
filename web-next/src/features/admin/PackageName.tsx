'use client'
import { usePackageLabel } from '@/lib/packageLabels'

// Display name of a package code from the admin-edited catalog (re-renders once the catalog has loaded).
export default function PackageName({ code }: { code: string }) {
  return <>{usePackageLabel(code)}</>
}
