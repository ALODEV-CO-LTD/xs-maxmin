<!--
  Bộ khung nút chức năng dùng chung (web). Một chỗ quyết định hình dạng, màu, cỡ, icon và trạng thái đang xử lý của MỌI nút;
  các class `.btn .btn-primary ...` trong styles/base.css vẫn dùng được cho nút lẻ, nhưng nút mới nên dùng component này.

  Props
    variant   'primary' (hành động chính, tối đa một nút mỗi hàng) | 'secondary' (viền xanh) | 'ghost' (Huỷ, Đóng, Quay lại)
              | 'danger' (xoá, hành động không hoàn tác được)
    size      'md' (mặc định) | 'sm' (nút trong bảng, trong dòng)
    icon      tên icon của AppIcon, hiện bên trái chữ
    iconOnly  chỉ có icon: bắt buộc có `label` (đọc cho trình đọc màn hình + tooltip), nút vuông 44px
    loading   đang xử lý: hiện vòng quay, khoá nút (giữ nguyên chiều rộng, không nhảy bố cục)
    block     rộng hết dòng
    type      'button' (mặc định, tránh vô tình gửi form) | 'submit'
  Slot: chữ của nút. Mọi thuộc tính khác (@click, form, :disabled, data-*) đi thẳng vào thẻ <button>.
-->
<script setup>
import AppIcon from './AppIcon.vue'

defineProps({
  variant: { type: String, default: 'secondary', validator: (v) => ['primary', 'secondary', 'ghost', 'danger'].includes(v) },
  size: { type: String, default: 'md', validator: (v) => ['md', 'sm'].includes(v) },
  icon: { type: String, default: '' },
  iconOnly: { type: Boolean, default: false },
  label: { type: String, default: '' },
  loading: { type: Boolean, default: false },
  block: { type: Boolean, default: false },
  type: { type: String, default: 'button' },
})
</script>

<template>
  <button
    :type="type"
    class="btn app-btn"
    :class="[`btn-${variant}`, { 'btn-sm': size === 'sm', 'btn-block': block, 'btn-icon': iconOnly, 'is-loading': loading }]"
    :aria-label="iconOnly ? label : undefined"
    :title="iconOnly ? label : undefined"
    :aria-busy="loading || undefined"
    :disabled="loading || undefined"
  >
    <AppIcon v-if="icon && !loading" :name="icon" />
    <span v-if="loading" class="app-btn-spin" aria-hidden="true"></span>
    <span v-if="!iconOnly" class="app-btn-text"><slot /></span>
  </button>
</template>

<style scoped>
.app-btn {
  position: relative;
  min-height: 44px; /* vùng chạm tối thiểu trên điện thoại */
}
.app-btn.btn-sm {
  min-height: 36px;
}
.btn-icon {
  width: 44px;
  padding: 0;
  font-size: 18px;
}
.btn-icon.btn-sm {
  width: 36px;
}
.app-btn-spin {
  width: 1em;
  height: 1em;
  border: 2px solid currentColor;
  border-right-color: transparent;
  border-radius: 50%;
  animation: app-btn-turn 0.7s linear infinite;
}
.is-loading {
  cursor: progress;
}
@keyframes app-btn-turn {
  to {
    transform: rotate(360deg);
  }
}
@media (prefers-reduced-motion: reduce) {
  .app-btn-spin {
    animation-duration: 2s;
  }
}
</style>
