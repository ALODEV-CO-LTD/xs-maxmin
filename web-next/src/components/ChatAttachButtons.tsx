'use client'
import './ChatAttachButtons.css'
import { useRef } from 'react'
import AppIcon from './AppIcon'
import { ALLOWED_IMAGE_TYPES, IMAGE_ONLY_MESSAGE, MAX_ATTACHMENT_BYTES } from '@/lib/attachments'

// Image button for a chat composer. Only JPG, PNG and WebP pictures can be sent (GIFs and other files can carry
// author/device/time data that cannot be reliably removed). `onPick` gets the chosen File, `onError` a message when the
// file is not an allowed picture, is empty or is over the 25 MB limit. The chosen file is shown by <AttachmentPreview>.
export default function ChatAttachButtons({
  disabled = false,
  icon = 'image',
  onPick,
  onError,
}: {
  disabled?: boolean
  icon?: string
  onPick: (file: File) => void
  onError: (message: string) => void
}) {
  const imageInput = useRef<HTMLInputElement>(null)
  const onChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    e.target.value = '' // allow picking the same file again
    if (!file) return
    if (!ALLOWED_IMAGE_TYPES.includes(file.type)) return onError(IMAGE_ONLY_MESSAGE)
    if (file.size === 0) return onError('Tệp trống')
    if (file.size > MAX_ATTACHMENT_BYTES) return onError('Tệp quá lớn (tối đa 25 MB)')
    onPick(file)
  }
  return (
    <div className="attach-buttons">
      <input ref={imageInput} type="file" accept="image/jpeg,image/png,image/webp" className="attach-input" onChange={onChange} />
      <button type="button" className="attach-btn" disabled={disabled} aria-label="Gửi ảnh" title="Gửi ảnh (JPG, PNG, WebP)" onClick={() => imageInput.current?.click()}>
        <AppIcon name={icon} />
      </button>
    </div>
  )
}
