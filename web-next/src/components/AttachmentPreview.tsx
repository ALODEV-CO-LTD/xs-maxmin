'use client'
import './AttachmentPreview.css'
import { useEffect, useState } from 'react'
import AppIcon from './AppIcon'
import { formatSize, isScrubbableImage } from '@/lib/attachments'

// The file chosen for the next message: thumbnail (images) or name + size, with a remove button.
export default function AttachmentPreview({ file, onRemove }: { file: File; onRemove: () => void }) {
  const isImage = file.type.startsWith('image/') && file.type !== 'image/svg+xml'
  const [previewUrl, setPreviewUrl] = useState('')
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- object URL lives with the chosen file
    if (!isImage) return setPreviewUrl('')
    const url = URL.createObjectURL(file)
    setPreviewUrl(url)
    return () => URL.revokeObjectURL(url)
  }, [file, isImage])
  return (
    <div className="att-wrap">
      <div className="att-preview">
        {isImage ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={previewUrl} alt={file.name} className="att-thumb" />
        ) : (
          <span className="att-icon"><AppIcon name="paperclip" /></span>
        )}
        <span className="att-info">
          <span className="att-name">{file.name}</span>
          <span className="att-size">{formatSize(file.size)}</span>
        </span>
        <button type="button" className="att-remove" aria-label="Bỏ tệp đính kèm" onClick={onRemove}>
          <AppIcon name="x" />
        </button>
      </div>
      {/* Images are always scrubbed before sending (K37/K38/S09); no switch. */}
      {isScrubbableImage(file) && (
        <div className="att-privacy">
          <div className="att-privacy-note">
            Ảnh sẽ tự động được xoá thông tin ẩn (vị trí GPS, thiết bị, thời gian chụp) và đổi tên trước khi gửi.
            Lưu ý: sau khi gửi, bản người nhận đã lưu về máy thì không thể xoá thông tin khỏi đó.
          </div>
        </div>
      )}
    </div>
  )
}
