// Chat attachments (files + images). The server stores them with the message
// and enforces the same 5 MB limit; checking here just saves a round trip.
export const MAX_ATTACHMENT_BYTES = 5 * 1024 * 1024

export function formatSize(bytes) {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

// File -> { name, type, data } with `data` as base64 (no data: prefix), the
// shape POST .../messages expects in its `attachment` field.
export function fileToPayload(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onerror = () => reject(new Error('Không đọc được tệp'))
    reader.onload = () => {
      const result = String(reader.result || '')
      resolve({ name: file.name, type: file.type || 'application/octet-stream', data: result.slice(result.indexOf(',') + 1) })
    }
    reader.readAsDataURL(file)
  })
}
