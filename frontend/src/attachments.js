// Chat attachments (files + images). The server stores them with the message
// and enforces the same 5 MB limit; checking here just saves a round trip.
export const MAX_ATTACHMENT_BYTES = 5 * 1024 * 1024

export function formatSize(bytes) {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

// ---- Image metadata scrubbing (K37/K38/S09) ----------------------------
// A photo straight from a phone carries EXIF: GPS position, device model,
// capture time. Every JPEG/PNG/WebP is ALWAYS redrawn through a canvas and
// exported again before sending, which keeps only the pixels, and it is sent
// under a random file name (the original name often holds a date/device).
// There is no switch to turn this off. The server strips JPEG/PNG metadata
// too (backend/lib/src/attachments.dart) as a second layer.

// Types a canvas can re-encode faithfully (GIF would lose its animation).
const REDRAW_TYPES = ['image/jpeg', 'image/png', 'image/webp']
export function isScrubbableImage(file) {
  return REDRAW_TYPES.includes(file.type)
}

const SCRUB_FAILED =
  'Không xử lý được ảnh để xoá thông tin vị trí/thiết bị. Hãy chọn ảnh khác.'

// Redraws the image and exports it in its own format -> a new File with no
// EXIF/GPS/device/time data. Honours the EXIF orientation first so the photo
// doesn't come out rotated once that tag is gone.
export async function scrubImageMetadata(file) {
  let bitmap
  try {
    bitmap = await createImageBitmap(file, { imageOrientation: 'from-image' })
  } catch {
    throw new Error(SCRUB_FAILED)
  }
  const canvas = document.createElement('canvas')
  canvas.width = bitmap.width
  canvas.height = bitmap.height
  canvas.getContext('2d').drawImage(bitmap, 0, 0)
  bitmap.close?.()
  const blob = await new Promise((resolve) => canvas.toBlob(resolve, file.type, 0.92))
  // Some browsers can't export WebP and silently fall back to PNG.
  if (!blob || blob.type !== file.type) throw new Error(SCRUB_FAILED)
  return new File([blob], file.name, { type: file.type, lastModified: Date.now() })
}

const EXT = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' }
export function anonymousName(type) {
  const id = Array.from(crypto.getRandomValues(new Uint8Array(5)), (b) => b.toString(16).padStart(2, '0')).join('')
  return `anh-${id}.${EXT[type] || 'jpg'}`
}

// File -> { name, type, data } with `data` as base64 (no data: prefix), the
// shape POST .../messages expects in its `attachment` field. JPEG/PNG/WebP
// images are always scrubbed of metadata and renamed first.
export async function fileToPayload(file) {
  let toSend = file
  let name = file.name
  if (isScrubbableImage(file)) {
    toSend = await scrubImageMetadata(file)
    name = anonymousName(toSend.type)
  }
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onerror = () => reject(new Error('Không đọc được tệp'))
    reader.onload = () => {
      const result = String(reader.result || '')
      resolve({
        name,
        type: toSend.type || 'application/octet-stream',
        data: result.slice(result.indexOf(',') + 1),
      })
    }
    reader.readAsDataURL(toSend)
  })
}
