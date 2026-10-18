<!--
  Tài khoản > Cài đặt quyền riêng tư (K34): auto-lock (K09/K40), lock/blur
  when the page is hidden (K32/S10). Stored in this browser only (see
  stores/privacy.js). Note K33: a web page cannot block screenshots.
-->
<script setup>
import { usePrivacyStore } from '../stores/privacy'

const privacy = usePrivacyStore()

const idleOptions = [
  { value: 0, label: 'Tắt' },
  { value: 1, label: '1 phút' },
  { value: 5, label: '5 phút' },
  { value: 15, label: '15 phút' },
  { value: 30, label: '30 phút' },
]
const hideOptions = [
  { value: 0, label: 'Tắt' },
  { value: 30, label: 'Sau 30 giây' },
  { value: 60, label: 'Sau 1 phút' },
  { value: 300, label: 'Sau 5 phút' },
]
</script>

<template>
  <div class="card">
    <h3 style="margin-top: 0">Cài đặt quyền riêng tư</h3>
    <p class="page-subtitle">Áp dụng cho trình duyệt này.</p>

    <div class="field">
      <label for="priv-idle">Tự động khoá khi không hoạt động</label>
      <select id="priv-idle" :value="privacy.autoLockMinutes" @change="privacy.saveSettings({ autoLockMinutes: Number($event.target.value) })">
        <option v-for="o in idleOptions" :key="o.value" :value="o.value">{{ o.label }}</option>
      </select>
    </div>

    <div class="field">
      <label for="priv-hide">Khoá khi chuyển tab / ẩn trang</label>
      <select id="priv-hide" :value="privacy.hideLockSeconds" @change="privacy.saveSettings({ hideLockSeconds: Number($event.target.value) })">
        <option v-for="o in hideOptions" :key="o.value" :value="o.value">{{ o.label }}</option>
      </select>
    </div>

    <label class="priv-check">
      <input type="checkbox" :checked="privacy.blurOnHide" @change="privacy.saveSettings({ blurOnHide: $event.target.checked })" />
      <span>Làm mờ nội dung khi trang bị ẩn hoặc mất focus</span>
    </label>

    <p class="priv-note">
      Khi khoá, bạn nhập lại mật khẩu (hoặc mật khẩu lớp hai) để xem dữ liệu; dữ liệu đang nhập được giữ lại. Lưu ý:
      trình duyệt không cho phép chặn hoàn toàn việc chụp màn hình hay xem trước ở màn hình đa nhiệm, nên làm mờ chỉ
      giúp giảm nội dung lộ ra.
    </p>
  </div>
</template>

<style scoped>
.priv-check {
  display: flex;
  gap: 8px;
  align-items: flex-start;
  margin: 4px 0 12px;
  font-size: 14px;
  cursor: pointer;
}
.priv-check input {
  margin-top: 3px;
}
.priv-note {
  margin: 0;
  font-size: 12px;
  line-height: 1.5;
  color: var(--text-secondary);
}
</style>
