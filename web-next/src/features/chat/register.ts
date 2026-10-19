// Plugs the call store and the chat store into the app shell through lib/hooks.js. Import this file once from a module
// that always loads (the shell / Providers): `import '@/features/chat/register'`.
import CallOverlay from '../calls/CallOverlay'
import { inCall, useCallStore } from '../calls/callStore'
import { hooks, registerShellOverlay, registerShellStart, registerTeardown, registerUserReady } from '@/lib/hooks'
import { useChatStore } from './chatStore'

let done = false
if (!done) {
  done = true
  hooks.inCall = inCall
  ;(hooks as { markFriendRead: (id: string) => void }).markFriendRead = (friendId) => void useChatStore.getState().markRead(friendId)
  // the call socket stays live while the shell is mounted (also carries chat frames and push events)
  registerShellStart(() => {
    useCallStore.getState().connect()
    return () => useCallStore.getState().disconnect()
  })
  registerUserReady(() => void useChatStore.getState().init())
  registerShellOverlay(CallOverlay)
  registerTeardown(() => {
    useCallStore.getState().disconnect()
    useChatStore.getState().reset()
  })
}
