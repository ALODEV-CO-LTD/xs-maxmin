// Static guards for CSS bugs found when comparing the Next.js shell with the Vue build (QA admin/nền).
import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'

const read = (p) => fs.readFileSync(new URL('../' + p, import.meta.url), 'utf8')

test('PrivacyGuard.css defines the lock overlay, box and veil (lock screen must cover the page)', () => {
  const css = read('src/components/PrivacyGuard.css')
  for (const c of ['.pl-overlay', '.pl-box', '.pl-title', '.pl-msg', '.pl-veil']) assert.ok(css.includes(c + ' {'), c)
  assert.match(css, /\.pl-overlay \{[^}]*position: fixed;[^}]*inset: 0/)
})

test('AppSelect hidden native input beats `.field input` (specificity), else a second bordered box shows', () => {
  const css = read('src/components/AppSelect.css')
  assert.match(css, /div\.app-select > input\.app-select-native \{[^}]*opacity: 0/)
  assert.ok(!/^\.app-select-native \{/m.test(css))
})

test('PaymentRequests reject dialog content is wrapped in .adm-pay (ModalDialog is a portal outside the view)', () => {
  const tsx = read('src/features/admin/PaymentRequestsView.tsx')
  const i = tsx.indexOf('<ModalDialog')
  assert.ok(i > 0)
  assert.match(tsx.slice(i), /<div className="adm-pay">[\s\S]*r-chip[\s\S]*<\/div>\s*<\/ModalDialog>/)
})

test('AuthGate waits for the admin profile before choosing an admin redirect', () => {
  const tsx = read('src/components/AuthGate.tsx')
  assert.match(tsx, /role === 'admin' && !user && !meTried/)
})
