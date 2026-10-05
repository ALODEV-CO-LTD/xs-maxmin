import { ref, watch } from 'vue'

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
// capture time. Before an image is sent it is redrawn through a canvas and
// exported again, which keeps only the pixels. The server strips JPEG/PNG
// metadata too (backend/lib/src/attachments.dart) as a second layer.
// The switch defaults to ON; turning it off sends the original file as-is
// (the server then keeps it as well - see `keepMetadata` in fileToPayload).
const STRIP_KEY = 'xs_strip_image_metadata'
function loadStrip() {
  try {
    return localStorage.getItem(STRIP_KEY) !== '0'
  } catch {
    return true
  }
}
export const stripImageMetadata = ref(loadStrip())
watch(stripImageMetadata, (on) => {
  try {
    localStorage.setItem(STRIP_KEY, on ? '1' : '0')
  } catch {
    /* storage unavailable - the choice just isn't remembered */
  }
})

// Types a canvas can re-encode faithfully (GIF would lose its animation).
const REDRAW_TYPES = ['image/jpeg', 'image/png', 'image/webp']
export function isScrubbableImage(file) {
  return REDRAW_TYPES.includes(file.type)
}

const SCRUB_FAILED =
  'Không xử lý được ảnh để xoá thông tin vị trí/thiết bị. Hãy chọn ảnh khác hoặc tắt tuỳ chọn xoá thông tin ảnh.'

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

// File -> { name, type, data } with `data` as base64 (no data: prefix), the
// shape POST .../messages expects in its `attachment` field. JPEG/PNG/WebP
// images are scrubbed of metadata first unless the user turned that off, in
// which case `keepMetadata` tells the server not to strip them either.
export async function fileToPayload(file) {
  let toSend = file
  let keepMetadata = false
  if (isScrubbableImage(file)) {
    if (stripImageMetadata.value) toSend = await scrubImageMetadata(file)
    else keepMetadata = true
  }
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onerror = () => reject(new Error('Không đọc được tệp'))
    reader.onload = () => {
      const result = String(reader.result || '')
      const payload = {
        name: file.name,
        type: toSend.type || 'application/octet-stream',
        data: result.slice(result.indexOf(',') + 1),
      }
      if (keepMetadata) payload.keepMetadata = true
      resolve(payload)
    }
    reader.readAsDataURL(toSend)
  })
}
