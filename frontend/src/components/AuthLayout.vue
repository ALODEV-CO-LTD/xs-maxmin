<!--
  Shared full-height hero layout for the public auth pages (/login,
  /register). Puts a centered card on the themed page background,
  matching the XOSO design system in src/styles/tokens.css.
-->
<script setup>
import ThemeToggle from './ThemeToggle.vue'

defineProps({
  subtitle: { type: String, default: '' },
})
</script>

<template>
  <div class="auth-page">
    <ThemeToggle class="auth-theme" />
    <main class="auth-card">
      <header class="auth-brand">
        <div class="auth-logo" aria-hidden="true">XS</div>
        <h1>XOSO</h1>
        <p v-if="subtitle" class="auth-subtitle">{{ subtitle }}</p>
      </header>
      <slot />
    </main>
  </div>
</template>

<style scoped>
/* Spacing follows an 8px grid (8/16/24/32/40). Colours come from the shared
   theme tokens (styles/tokens.css) so Light/Dark switch with <html data-theme>. */
.auth-page {
  --auth-link: var(--link);
  --auth-ok: var(--success-text);
  --auth-error: var(--danger-text);
  --auth-warn: var(--warning-text);
  --auth-input-bg: var(--surface);
  --auth-input-border: var(--input-border);
  --auth-input-border-hover: var(--input-border-hover);
  position: relative;
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 24px 16px;
  background: var(--background);
}

.auth-theme {
  position: absolute;
  top: 16px;
  right: 16px;
}

.auth-card {
  width: 100%;
  max-width: 400px;
  padding: 40px 32px;
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 16px;
  box-shadow: var(--shadow-lg);
}

/* ---- Brand: logo -> title -> description ---- */
.auth-brand {
  text-align: center;
  margin-bottom: 32px;
}

.auth-logo {
  width: 56px;
  height: 56px;
  margin: 0 auto 16px;
  border-radius: 14px;
  background: var(--primary);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  font-family: var(--font-display);
  font-weight: 800;
  font-size: 20px;
}

.auth-brand h1 {
  font-size: 28px;
  line-height: 1.2;
  margin: 0 0 8px;
}

.auth-subtitle {
  color: var(--muted);
  font-size: 15px;
  line-height: 1.5;
  margin: 0;
  text-wrap: balance;
}

/* ---- Form controls (scoped to the auth card only) ---- */
.auth-card :deep(.field) {
  margin-bottom: 16px;
}

.auth-card :deep(.field label) {
  font-size: 14px;
  font-weight: 700;
  color: var(--text);
  margin-bottom: 8px;
}

.auth-card :deep(.field input) {
  height: 48px;
  padding: 0 16px;
  font-size: 16px;
  border-radius: 10px;
  background: var(--auth-input-bg);
  border: 1px solid var(--auth-input-border);
  transition: border-color 0.15s ease, box-shadow 0.15s ease;
}

.auth-card :deep(.field.has-icon input) {
  padding-left: 54px;
}

.auth-card :deep(.field .input-icon) {
  left: 12px;
  width: 30px;
  height: 30px;
  color: var(--muted);
  transition: color 0.15s ease;
}

.auth-card :deep(.field input::placeholder) {
  color: var(--muted);
  opacity: 1;
}

.auth-card :deep(.field input:hover:not(:disabled)) {
  border-color: var(--auth-input-border-hover);
}

.auth-card :deep(.field input:focus) {
  outline: none;
  border-color: var(--focus);
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--focus) 35%, transparent);
}

.auth-card :deep(.field .input-wrap:focus-within .input-icon) {
  color: var(--focus);
}

.auth-card :deep(.field input:disabled) {
  opacity: 0.6;
  cursor: not-allowed;
}

.auth-card :deep(.field input[aria-invalid='true']) {
  border-color: var(--danger-text);
}

.auth-card :deep(.field input[aria-invalid='true']:focus) {
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--danger) 35%, transparent);
}

/* ---- Inline field validation / hints ---- */
.auth-card :deep(.field-msg) {
  display: flex;
  align-items: flex-start;
  gap: 6px;
  margin: 8px 0 0;
  font-size: 14px;
  line-height: 1.4;
  color: var(--muted);
}

.auth-card :deep(.field-msg .app-icon) {
  flex: none;
  width: 16px;
  height: 16px;
  margin-top: 1px;
}

.auth-card :deep(.field-msg.error) {
  color: var(--auth-error);
}

.auth-card :deep(.field-msg.ok) {
  color: var(--auth-ok);
}

.auth-card :deep(.field input[data-valid='true']) {
  border-color: var(--success);
}

/* ---- Optional, visually separated block (wipe password) ---- */
.auth-card :deep(.optional-box) {
  margin: 24px 0 0;
  padding: 16px;
  border: 1px dashed var(--auth-input-border);
  border-radius: 12px;
  background: color-mix(in srgb, var(--warning) 10%, transparent);
}

.auth-card :deep(.optional-box .field) {
  margin-bottom: 0;
}

.auth-card :deep(.optional-title) {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 8px;
  margin: 0 0 8px;
  font-size: 15px;
  font-weight: 700;
  color: var(--text);
}

.auth-card :deep(.optional-badge) {
  padding: 2px 8px;
  font-size: 12px;
  font-weight: 700;
  color: var(--muted);
  border: 1px solid var(--auth-input-border);
  border-radius: 999px;
}

.auth-card :deep(.optional-desc) {
  margin: 0 0 8px;
  font-size: 14px;
  line-height: 1.5;
  color: var(--muted);
}

.auth-card :deep(.optional-warn) {
  display: flex;
  gap: 8px;
  margin: 0 0 16px;
  font-size: 14px;
  line-height: 1.5;
  color: var(--auth-warn);
}

.auth-card :deep(.optional-warn .app-icon) {
  flex: none;
  width: 16px;
  height: 16px;
  margin-top: 2px;
}

/* ---- Alerts ---- */
.auth-card :deep(.alert) {
  font-size: 14px;
  line-height: 1.5;
  padding: 12px 16px;
  margin-bottom: 24px;
  border-radius: 10px;
  border: 1px solid currentColor;
}

/* ---- Buttons: primary CTA 48px, secondary/ghost match ---- */
.auth-card :deep(.btn) {
  min-height: 48px;
  padding: 0 24px;
  font-size: 16px;
  font-weight: 700;
  border-radius: 10px;
}

.auth-card :deep(.btn-block + .btn-block) {
  margin-top: 8px;
}

.auth-card :deep(form > .btn-primary) {
  margin-top: 24px;
}

.auth-card :deep(.btn-primary) {
  box-shadow: var(--shadow-sm);
}

.auth-card :deep(.btn-primary:active:not(:disabled)) {
  transform: translateY(1px);
}

.auth-card :deep(.btn:focus-visible) {
  outline: 3px solid color-mix(in srgb, var(--focus) 60%, transparent);
  outline-offset: 2px;
}

.auth-card :deep(.btn-ghost) {
  color: var(--text);
  border-color: var(--auth-input-border);
}

.auth-card :deep(.btn-ghost:hover:not(:disabled)) {
  background: var(--surface-2);
}

.auth-card :deep(.btn:disabled) {
  opacity: 0.6;
  cursor: not-allowed;
}

/* Loading: spinner before the label while aria-busy */
.auth-card :deep(.btn[aria-busy='true']) {
  cursor: progress;
}

.auth-card :deep(.btn[aria-busy='true']::before) {
  content: '';
  width: 16px;
  height: 16px;
  border: 2px solid color-mix(in srgb, currentColor 35%, transparent);
  border-top-color: currentColor;
  border-radius: 50%;
  animation: auth-spin 0.7s linear infinite;
}

@keyframes auth-spin {
  to {
    transform: rotate(360deg);
  }
}

@media (prefers-reduced-motion: reduce) {
  .auth-card :deep(.btn[aria-busy='true']::before) {
    animation-duration: 2s;
  }
}

/* ---- Footer (register / login switch) ---- */
.auth-card :deep(.auth-footer) {
  text-align: center;
  font-size: 15px;
  margin: 24px 0 0;
}

.auth-card :deep(.auth-footer a) {
  display: inline-block;
  padding: 8px 4px;
  margin: -8px 0;
  font-weight: 700;
  color: var(--auth-link);
}

.auth-card :deep(.auth-footer a:focus-visible) {
  outline: 3px solid color-mix(in srgb, var(--focus) 60%, transparent);
  outline-offset: 2px;
  border-radius: 4px;
}

/* ---- Large screens: a touch more air ---- */
@media (min-width: 1600px) {
  .auth-card {
    max-width: 420px;
    padding: 48px 40px;
  }
}

/* ---- Mobile ---- */
@media (max-width: 480px) {
  .auth-page {
    align-items: flex-start;
    padding: 24px 16px;
  }
  .auth-card {
    padding: 32px 24px;
    max-width: none;
  }
  .auth-brand {
    margin-bottom: 24px;
  }
}
</style>
