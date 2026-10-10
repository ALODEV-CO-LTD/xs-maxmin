// Admin-set security policy as the app sees it (A09, GET /me/policy): the
// default idle auto-lock (used until a person picks their own) and whether to
// draw the viewer watermark. Until the answer arrives the watermark stays ON,
// so a slow network never shows an unmarked screen.
import { defineStore } from 'pinia'
import { api } from '../api'
import { usePrivacyStore } from './privacy'

export const usePolicyStore = defineStore('policy', {
  state: () => ({ watermarkEnabled: true, autoLockMinutes: 0, loaded: false }),
  actions: {
    async load() {
      try {
        const res = await api.get('/me/policy')
        this.watermarkEnabled = res.watermarkEnabled !== false
        this.autoLockMinutes = Number(res.autoLockMinutes) || 0
        this.loaded = true
        usePrivacyStore().applyServerDefault(this.autoLockMinutes)
      } catch {
        /* keep the safe defaults */
      }
    },
  },
})
