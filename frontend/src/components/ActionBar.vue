<!--
  Khung hàng nút thao tác của một màn hình / hộp thoại / form. Mọi màn dùng CÙNG một bố cục và thứ tự để người dùng quen tay:
      [ nút huỷ diệt (Xoá...) ]  ··· ghi chú ···  [ Huỷ ]  [ Hành động chính ]
  - slot `start`    bên trái: nút phụ / nguy hiểm (Xoá, Đặt lại mặc định)
  - slot `note`     chữ nhỏ ở giữa (vd. "3 mục riêng", "Đã lưu")
  - slot mặc định   bên phải: nút Huỷ rồi nút chính LUÔN ở ngoài cùng bên phải
  Props
    sticky  dính đáy vùng cuộn / màn hình (bảng dài: Lưu, Huỷ không bị trôi mất); thêm vùng an toàn của điện thoại
    stack   trên màn hẹp (<= 520px) xếp dọc, nút chính ở trên cùng, nút rộng hết dòng
    align   'end' (mặc định) | 'between' (start và nhóm phải hai đầu) | 'start'
-->
<script setup>
defineProps({
  sticky: { type: Boolean, default: false },
  stack: { type: Boolean, default: true },
  align: { type: String, default: 'between', validator: (v) => ['end', 'between', 'start'].includes(v) },
})
</script>

<template>
  <div class="action-bar" :class="[`align-${align}`, { sticky, stack }]" role="group">
    <div v-if="$slots.start" class="ab-start"><slot name="start" /></div>
    <div v-if="$slots.note" class="ab-note"><slot name="note" /></div>
    <div v-if="$slots.default" class="ab-end"><slot /></div>
  </div>
</template>

<style scoped>
.action-bar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px 12px;
  margin-top: 12px;
}
.align-between {
  justify-content: space-between;
}
.align-end {
  justify-content: flex-end;
}
.align-start {
  justify-content: flex-start;
}
.ab-start,
.ab-end {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
}
.ab-end {
  margin-left: auto;
  justify-content: flex-end;
}
.ab-note {
  flex: 1 1 auto;
  min-width: 0;
  font-size: 13px;
  color: var(--muted);
}
.sticky {
  position: sticky;
  bottom: 0;
  z-index: 5;
  margin-top: 16px;
  padding: 10px 0 calc(10px + env(safe-area-inset-bottom, 0px));
  background: var(--card);
  border-top: 1px solid var(--border);
}
@media (max-width: 520px) {
  .stack {
    flex-direction: column-reverse; /* nút chính lên trên cùng */
    align-items: stretch;
  }
  .stack .ab-start,
  .stack .ab-end {
    flex-direction: column-reverse;
    align-items: stretch;
    margin-left: 0;
  }
  .stack :deep(.btn) {
    width: 100%;
  }
}
</style>
