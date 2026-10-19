// Pure view helpers of the friends screen (kept out of the component so the tests can load them).

export const REPLY_MARK = '↪ '

// A reply is stored as "↪ <quoted text>\n<body>" (the format the app uses too). Returns the quote and the body.
export function quoteOf(content) {
  const [first, ...rest] = String(content || '').split('\n')
  if (!first.startsWith(REPLY_MARK) || !rest.length) return { quote: '', body: content }
  return { quote: first.slice(REPLY_MARK.length), body: rest.join('\n') }
}

// The text shown for a quoted / pinned message (without any "↪" quote line of its own).
export const quoteText = (m) => (m.content || (m.attachment ? '[Ảnh]' : '')).split('\n').filter((l) => !l.startsWith(REPLY_MARK)).join(' ').slice(0, 60)

export function callLine(c) {
  const mins = Math.floor((c.durationSeconds || 0) / 60)
  const secs = String((c.durationSeconds || 0) % 60).padStart(2, '0')
  const dur = `${mins}:${secs}`
  const out = c.direction === 'outgoing'
  switch (c.status) {
    case 'completed':
      return `${out ? 'Cuộc gọi thoại đi' : 'Cuộc gọi thoại đến'} · ${dur}`
    case 'missed':
      return out ? 'Cuộc gọi đi · Không ai nghe máy' : 'Cuộc gọi nhỡ'
    case 'busy':
      return out ? 'Cuộc gọi đi · Máy bận' : 'Cuộc gọi nhỡ (bạn đang bận)'
    case 'rejected':
      return out ? 'Cuộc gọi đi · Bị từ chối' : 'Bạn đã từ chối cuộc gọi'
    case 'failed':
      return 'Cuộc gọi · Không kết nối được âm thanh'
    default:
      return 'Cuộc gọi thoại'
  }
}
export const isMissedCall = (c) => c.direction === 'incoming' && (c.status === 'missed' || c.status === 'busy')

// The status under the conversation title. "Đã kết nối" only says MY connection to the server is up; when the last thing
// in the chat is my own message the relay could not hand over because the friend is not online, say that instead
// (same rule as the app's _peerOffline in chat_page.dart). `messages` are the mapped rows of the screen.
export function peerOfflineLabel(messages, socketReady) {
  const last = messages[messages.length - 1]
  if (socketReady && last && last.mine && last.status === 'failed' && last.reason === 'offline') return { text: 'Bạn bè đang offline', tone: 'warn' }
  return socketReady ? { text: 'Đã kết nối', tone: 'ok' } : { text: 'Mất kết nối', tone: 'bad' }
}
