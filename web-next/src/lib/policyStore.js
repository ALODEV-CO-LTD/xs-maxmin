// Admin-set security policy as the app sees it (A09, GET /me/policy): the default idle auto-lock (used until a person
// picks their own), whether to draw the viewer watermark (off unless the Admin turns it on) and whether to cover the
// screen when a desktop screenshot shortcut is held. The watermark stays off until the answer says otherwise.
import { create } from 'zustand'
import { api } from './api'
import { usePrivacyStore } from './privacyStore'
import { setScreenshotGuardEnabled } from './screenshotGuard'

export const usePolicyStore = create((set) => ({
  watermarkEnabled: false,
  screenshotGuardEnabled: true,
  blurOnHideEnabled: false,
  autoLockMinutes: 0,
  hideLockSeconds: 0,
  loaded: false,
  async load() {
    try {
      const res = await api.get('/me/policy')
      const screenshotGuardEnabled = res.screenshotGuardEnabled !== false
      setScreenshotGuardEnabled(screenshotGuardEnabled)
      const blurOnHideEnabled = res.blurOnHideEnabled === true
      const autoLockMinutes = Number(res.autoLockMinutes) || 0
      const hideLockSeconds = Number(res.hideLockSeconds) || 0
      set({ watermarkEnabled: res.watermarkEnabled === true, screenshotGuardEnabled, blurOnHideEnabled, autoLockMinutes, hideLockSeconds, loaded: true })
      usePrivacyStore.getState().setBlurPolicy(blurOnHideEnabled)
      usePrivacyStore.getState().applyServerDefault(autoLockMinutes, hideLockSeconds)
    } catch {
      /* keep the safe defaults */
    }
  },
}))
