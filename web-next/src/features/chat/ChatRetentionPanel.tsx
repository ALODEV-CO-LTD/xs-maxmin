'use client'
import './ChatRetentionPanel.css'
import { useCallback, useEffect, useImperativeHandle, useState } from 'react'
import AppButton from '@/components/AppButton'
import AppSelect from '@/components/AppSelect'
import { useChatStore } from './chatStore'

// Auto-delete for ONE friend conversation. Chat is end-to-end encrypted and kept only on each device, so the rule runs
// on THIS device: messages (or only images) older than the chosen time are removed from its local history; the
// friend's device is not touched. The buttons that open / turn off the setting live in the conversation's top bar.
const TTL_OPTIONS = [
  { value: 3600, label: '1 giờ' },
  { value: 86400, label: '1 ngày' },
  { value: 604800, label: '7 ngày' },
  { value: 2592000, label: '30 ngày' },
]
export type RetentionRule = { ttlSeconds: number; scope: 'all' | 'images' }
export interface RetentionHandle { cancel: () => Promise<void> }

export default function ChatRetentionPanel({
  friendId,
  friendName = '',
  open,
  onOpenChange,
  onRule,
  onApplied,
  handle,
}: {
  friendId: string
  friendName?: string
  open: boolean
  onOpenChange: (open: boolean) => void
  onRule?: (rule: RetentionRule | null) => void
  onApplied?: () => void
  handle?: React.Ref<RetentionHandle>
}) {
  const ready = useChatStore((s) => s.ready)
  const [rule, setRule] = useState<RetentionRule | null>(null)
  const [ttl, setTtl] = useState(86400)
  const [scope, setScope] = useState<'all' | 'images'>('all')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const ttlLabel = TTL_OPTIONS.find((o) => o.value === rule?.ttlSeconds)?.label || ''

  const load = useCallback(async () => {
    setError('')
    const r = await useChatStore.getState().retentionOf(friendId)
    setRule(r)
    onRule?.(r)
  }, [friendId, onRule])
  useEffect(() => {
    onOpenChange(false)
    // eslint-disable-next-line react-hooks/set-state-in-effect -- reload the rule when the conversation changes
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [friendId, ready])

  async function apply(e: React.FormEvent) {
    e.preventDefault()
    setError('')
    setBusy(true)
    try {
      await useChatStore.getState().setRetention(friendId, { ttlSeconds: ttl, scope })
      onOpenChange(false)
      await load()
      onApplied?.()
    } catch (err) {
      setError((err as Error).message || 'Không đặt được tự xoá')
    } finally {
      setBusy(false)
    }
  }
  const cancel = async () => {
    await useChatStore.getState().setRetention(friendId, null)
    await load()
  }
  useImperativeHandle(handle, () => ({ cancel }))

  return (
    <div className="retention">
      <div className="retention-line">
        {rule ? (
          <span className="retention-state">Tự xoá {rule.scope === 'images' ? 'ảnh' : 'tin nhắn'} cũ hơn {ttlLabel} (trên thiết bị này)</span>
        ) : (
          <span className="retention-state muted">Tin nhắn không tự xoá</span>
        )}
      </div>
      {error && <div className="alert alert-error" style={{ margin: '6px 0 0' }}>{error}</div>}
      {open && (
        <form className="retention-form" onSubmit={apply}>
          <p className="retention-hint">
            Tin nhắn/ảnh cũ hơn thời gian chọn sẽ bị xoá khỏi thiết bị này. Máy chủ không lưu tin nhắn, và thiết bị của {friendName} có cài đặt riêng.
          </p>
          <div className="retention-row">
            <AppSelect value={ttl} onChange={setTtl} aria-label="Thời gian tự xoá">
              {TTL_OPTIONS.map((o) => <option key={o.value} value={o.value}>Sau {o.label}</option>)}
            </AppSelect>
            <AppSelect value={scope} onChange={setScope} aria-label="Phạm vi tự xoá">
              <option value="all">Tin nhắn và tệp đính kèm</option>
              <option value="images">Chỉ ảnh</option>
            </AppSelect>
            <AppButton variant="danger" size="sm" type="submit" disabled={busy}>{busy ? '...' : 'Áp dụng'}</AppButton>
          </div>
        </form>
      )}
    </div>
  )
}
