// The signaling WebSocket seen from outside the call store: the chat store sends its e2ee frames through `send` and
// gets the frames of type e2ee-msg / e2ee-ack / e2ee-undelivered from `chatHandler`. Kept apart so the chat store and
// the call store do not import each other.
let sender = () => {}
let ready = () => false
let chatHandler = () => {}

export const transport = {
  send: (message) => sender(message),
  ready: () => ready(),
  deliverToChat: (message) => chatHandler(message),
}
export const bindSocket = (send, isReady) => {
  sender = send
  ready = isReady
}
export const setChatHandler = (fn) => {
  chatHandler = fn
}
