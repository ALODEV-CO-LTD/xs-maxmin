// Admin-set security policy as the app sees it (A09, GET /me/policy): the
// default idle auto-lock (used until a person picks their own), whether to draw the
// viewer watermark (off unless the Admin turns it on) and whether to cover the screen
// when a desktop screenshot shortcut is held. The watermark stays off until the answer says otherwise.
import { defineStore } from 'pinia'
import { api } from '../api'
import { usePrivacyStore } from './privacy'
import { setScreenshotGuardEnabled } from '../screenshotGuard'

export const usePolicyStore = defineStore('policy', {
  state: () => ({ watermarkEnabled: false, screenshotGuardEnabled: true, blurOnHideEnabled: true, autoLockMinutes: 0, loaded: false }),
  actions: {
    async load() {
      try {
        const res = await api.get('/me/policy')
        this.watermarkEnabled = res.watermarkEnabled === true
        this.screenshotGuardEnabled = res.screenshotGuardEnabled !== false
        setScreenshotGuardEnabled(this.screenshotGuardEnabled)
        this.blurOnHideEnabled = res.blurOnHideEnabled !== false
        usePrivacyStore().setBlurPolicy(this.blurOnHideEnabled)
        this.autoLockMinutes = Number(res.autoLockMinutes) || 0
        this.loaded = true
        usePrivacyStore().applyServerDefault(this.autoLockMinutes)
      } catch {
        /* keep the safe defaults */
      }
    },
  },
})
