// Admin-set security policy as the app sees it (A09, GET /me/policy): the
// default idle auto-lock (used until a person picks their own) and whether to
// draw the viewer watermark and cover the screen when a desktop screenshot shortcut is held. Until the answer arrives the watermark stays ON,
// so a slow network never shows an unmarked screen.
import { defineStore } from 'pinia'
import { api } from '../api'
import { usePrivacyStore } from './privacy'
import { setScreenshotGuardEnabled } from '../screenshotGuard'

export const usePolicyStore = defineStore('policy', {
  state: () => ({ watermarkEnabled: true, screenshotGuardEnabled: true, autoLockMinutes: 0, loaded: false }),
  actions: {
    async load() {
      try {
        const res = await api.get('/me/policy')
        this.watermarkEnabled = res.watermarkEnabled !== false
        this.screenshotGuardEnabled = res.screenshotGuardEnabled !== false
        setScreenshotGuardEnabled(this.screenshotGuardEnabled)
        this.autoLockMinutes = Number(res.autoLockMinutes) || 0
        this.loaded = true
        usePrivacyStore().applyServerDefault(this.autoLockMinutes)
      } catch {
        /* keep the safe defaults */
      }
    },
  },
})
