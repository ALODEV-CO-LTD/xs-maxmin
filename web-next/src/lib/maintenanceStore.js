// Maintenance mode for customers. While Admin has it on, the server answers a customer's requests with 503
// `{error, maintenance: true}`; api.js puts the message here and <MaintenanceScreen> covers the app. The notice feed
// (GET /announcements, left open during maintenance) turns it off again. Admins are never covered.
import { create } from 'zustand'

export const DEFAULT_MAINTENANCE_MESSAGE = 'Hệ thống đang bảo trì, vui lòng quay lại sau.'

export const useMaintenanceStore = create((set) => ({
  message: null, // null = not in maintenance
  setMessage: (message) => set({ message }),
  clear: () => set({ message: null }),
}))

// The `maintenance` object of GET /announcements: {enabled, message}.
export function applyNotices(m) {
  const on = !!m && m.enabled === true
  const text = on && typeof m.message === 'string' && m.message.trim() ? m.message.trim() : DEFAULT_MAINTENANCE_MESSAGE
  useMaintenanceStore.getState().setMessage(on ? text : null)
}
