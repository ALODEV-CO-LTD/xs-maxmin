<!--
  /admin/security-policy - security policy configuration (A09), permission
  `security.policy`. The login throttle, how long a login lasts, the default idle
  auto-lock and the viewer watermark. Applies to the next request / next load;
  every change is written to the security log.
  API: GET/PUT/DELETE /admin/security-policy
-->
<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import { api, ApiError } from '../../api'
import { showConfirm } from '../../confirm'

const loading = ref(true)
const saving = ref(false)
const error = ref('')
const notice = ref('')
const defaults = ref({})
const form = reactive({
  loginFreeAttempts: 5,
  loginBaseLockSeconds: 30,
  loginMaxLockSeconds: 900,
  tokenDays: 30,
  autoLockMinutes: 0,
  watermarkEnabled: true,
  screenshotGuardEnabled: true,
})
let saved = ''

const dirty = computed(() => JSON.stringify(form) !== saved)

function fill(res) {
  Object.assign(form, res.policy)
  defaults.value = res.defaults
  saved = JSON.stringify(form)
}

async function load() {
  try {
    fill(await api.get('/admin/security-policy'))
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không tải được chính sách bảo mật'
  } finally {
    loading.value = false
  }
}
onMounted(load)

const mins = (s) => (s % 60 === 0 && s >= 60 ? `${s / 60} phút` : `${s} giây`)
const lockExample = computed(() => {
  const out = []
  let s = form.loginBaseLockSeconds
  for (let i = 0; i < 4; i++) {
    out.push(mins(Math.min(s, form.loginMaxLockSeconds)))
    s *= 2
  }
  return out.join(' → ')
})

async function save() {
  saving.value = true
  error.value = ''
  notice.value = ''
  try {
    const body = {}
    for (const k of Object.keys(form)) body[k] = typeof form[k] === 'boolean' ? !!form[k] : Number(form[k])
    fill(await api.put('/admin/security-policy', body))
    notice.value = 'Đã lưu chính sách bảo mật.'
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không lưu được'
  } finally {
    saving.value = false
  }
}

async function reset() {
  if (!(await showConfirm({ title: 'Đặt lại mặc định', message: 'Đặt lại toàn bộ chính sách bảo mật về giá trị mặc định?', confirmText: 'Đặt lại' }))) return
  saving.value = true
  error.value = ''
  try {
    fill(await api.del('/admin/security-policy'))
    notice.value = 'Đã đặt lại về mặc định.'
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không đặt lại được'
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div class="page">
    <h1 class="page-title">Chính sách bảo mật</h1>
    <p class="page-subtitle">Áp dụng cho toàn hệ thống. Mọi thay đổi được ghi vào nhật ký bảo mật.</p>

    <div v-if="error" class="alert alert-error">{{ error }}</div>
    <div v-if="notice" class="alert alert-success">{{ notice }}</div>
    <div v-if="loading" class="card">Đang tải...</div>

    <form v-else @submit.prevent="save">
      <section class="card block">
        <h2>Chống đoán mật khẩu</h2>
        <p class="hint">Áp dụng cho đăng nhập, mật khẩu lớp hai và các ô nhập lại mật khẩu. Nhập sai quá số lần cho phép thì bị khoá tạm theo tài khoản và địa chỉ IP; mỗi lần sai tiếp theo, thời gian khoá nhân đôi đến mức tối đa.</p>
        <div class="grid">
          <label>Số lần nhập sai được phép<input v-model.number="form.loginFreeAttempts" type="number" min="3" max="20" /><small>3 đến 20 (mặc định {{ defaults.loginFreeAttempts }})</small></label>
          <label>Khoá lần đầu (giây)<input v-model.number="form.loginBaseLockSeconds" type="number" min="5" max="3600" /><small>5 đến 3600 (mặc định {{ defaults.loginBaseLockSeconds }})</small></label>
          <label>Khoá tối đa (giây)<input v-model.number="form.loginMaxLockSeconds" type="number" min="30" max="86400" /><small>30 đến 86400 (mặc định {{ defaults.loginMaxLockSeconds }})</small></label>
        </div>
        <p class="hint">Các lần khoá liên tiếp: {{ lockExample }}</p>
      </section>

      <section class="card block">
        <h2>Phiên đăng nhập</h2>
        <div class="grid">
          <label>Thời hạn đăng nhập (ngày)<input v-model.number="form.tokenDays" type="number" min="1" max="365" /><small>1 đến 365 (mặc định {{ defaults.tokenDays }}). Chỉ áp dụng cho lần đăng nhập mới; phiên hiện có giữ hạn cũ.</small></label>
          <label>Tự khoá màn hình mặc định (phút)<input v-model.number="form.autoLockMinutes" type="number" min="0" max="240" /><small>0 là tắt. Chỉ dùng cho người chưa tự chọn trong Tài khoản.</small></label>
        </div>
      </section>

      <section class="card block">
        <h2>Đóng dấu màn hình</h2>
        <p class="hint">Web không chặn được chụp màn hình. Dấu tên người xem mờ (tên, tên đăng nhập, giờ, 4 ký tự cuối mã tài khoản) phủ trên mọi màn hình, để ảnh bị lộ truy ra được tài khoản và thời điểm chụp.</p>
        <label class="check"><input v-model="form.watermarkEnabled" type="checkbox" /> Bật đóng dấu tên người xem</label>
        <p class="hint" style="margin-top: 14px">Trên máy tính, màn hình tự bị phủ đen ngay khi giữ tổ hợp phím chụp (Cmd+Shift+3/4/5 trên Mac, Win+Shift+S trên Windows), nên ảnh chụp ra màu đen. PrintScreen chỉ đến được trang sau khi ảnh đã chụp nên chỉ xoá clipboard. Không chặn được chụp bằng điện thoại, nút cứng trên điện thoại hay quay bằng thiết bị khác; muốn chặn thật cần app.</p>
        <label class="check"><input v-model="form.screenshotGuardEnabled" type="checkbox" /> Phủ đen màn hình khi bấm phím chụp màn hình (máy tính)</label>
      </section>

      <div class="actions">
        <button type="button" class="btn btn-ghost" :disabled="saving" @click="reset">Đặt lại mặc định</button>
        <button type="submit" class="btn btn-primary" :disabled="saving || !dirty">{{ saving ? 'Đang lưu...' : 'Lưu chính sách' }}</button>
      </div>
    </form>
  </div>
</template>

<style scoped>
.block {
  margin-bottom: 12px;
  padding: 16px;
  border-radius: 12px;
}
.block h2 {
  margin: 0 0 6px;
  font-size: 16px;
}
.hint {
  margin: 0 0 12px;
  font-size: 13px;
  color: var(--muted);
}
.grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
  gap: 12px;
}
label {
  display: flex;
  flex-direction: column;
  gap: 4px;
  font-size: 14px;
}
small {
  color: var(--muted);
}
input[type='number'] {
  height: 40px;
  padding: 0 12px;
  font: inherit;
  color: var(--text-primary);
  background: var(--surface);
  border: 1px solid var(--input-border);
  border-radius: 10px;
}
.check {
  flex-direction: row;
  align-items: center;
  gap: 8px;
  cursor: pointer;
}
.actions {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
}
</style>
