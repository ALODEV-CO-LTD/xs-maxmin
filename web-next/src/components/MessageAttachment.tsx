'use client'
import './MessageAttachment.css'
import { useEffect, useState } from 'react'
import AppIcon from './AppIcon'
import { api } from '@/lib/api'
import { formatSize } from '@/lib/attachments'

// An attachment inside a chat bubble. Images load as a thumbnail (fetched with the session token, then shown from an
// object URL; click to open full size). Other files show their name + size and download on click.
export interface Att { name: string; type?: string; size: number; isImage?: boolean }

export default function MessageAttachment({ att, path = '', blob = null }: { att: Att; path?: string; blob?: Blob | null }) {
  const [imageUrl, setImageUrl] = useState('')
  const [failed, setFailed] = useState(false)
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    if (!att.isImage) return
    let url = ''
    let gone = false
    ;(async () => {
      try {
        url = URL.createObjectURL(blob || (await api.blob(path)))
        if (gone) URL.revokeObjectURL(url)
        else setImageUrl(url)
      } catch {
        if (!gone) setFailed(true)
      }
    })()
    return () => {
      gone = true
      if (url) URL.revokeObjectURL(url)
    }
  }, [att.isImage, blob, path])

  async function download() {
    if (busy) return
    setBusy(true)
    try {
      const url = URL.createObjectURL(blob || (await api.blob(path)))
      const a = document.createElement('a')
      a.href = url
      a.download = att.name
      document.body.appendChild(a)
      a.click()
      a.remove()
      setTimeout(() => URL.revokeObjectURL(url), 10000)
    } catch {
      setFailed(true)
    } finally {
      setBusy(false)
    }
  }

  if (att.isImage && imageUrl) {
    return (
      <a href={imageUrl} target="_blank" rel="noopener" className="ma-image-link" title={att.name}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={imageUrl} alt={att.name} className="ma-image" />
      </a>
    )
  }
  if (att.isImage && !failed) return <div className="ma-image ma-loading" aria-busy="true" />
  return (
    <button type="button" className="ma-file" disabled={busy} onClick={download}>
      <span className="ma-file-icon"><AppIcon name="paperclip" /></span>
      <span className="ma-file-info">
        <span className="ma-file-name">{att.name}</span>
        <span className="ma-file-size">{failed ? 'Không tải được tệp' : formatSize(att.size)}</span>
      </span>
    </button>
  )
}
