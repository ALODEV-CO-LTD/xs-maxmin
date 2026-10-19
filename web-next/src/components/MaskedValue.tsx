'use client'
import './MaskedValue.css'
import { useMasked } from '@/lib/maskStore'

// A figure that turns into "••••" while the "Ẩn số liệu" mask is on (see lib/maskStore.js). The real text is not
// rendered at all while masked.   <MaskedValue text={formatNumber(n)} />
export default function MaskedValue({ text = '' }: { text?: string | number }) {
  const masked = useMasked()
  return masked ? <span className="masked" aria-label="Số liệu đã ẩn">••••</span> : <span>{text}</span>
}
