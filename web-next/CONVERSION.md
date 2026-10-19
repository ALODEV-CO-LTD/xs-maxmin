# Chuyển web từ Vue 3 sang Next.js (đang làm)

Thư mục `frontend/` (Vue 3 + Vite) vẫn là bản đang chạy thật. `web-next/` là bản Next.js 16 (App Router, React 19, TypeScript) chuyển dần từng màn hình. Chỉ thay web; backend Dart và app Flutter giữ nguyên.

## Cách xuất bản
`output: 'export'`: `npm run build` ghi cả trang tĩnh ra `web-next/out`, nginx phục vụ cùng gốc với `/api` y như bản Vue (không cần chạy Node ở máy chủ). Dev: `npm run dev` (chuyển `/api` sang `http://localhost:8080`, đổi bằng `API_PROXY`).
Đường dẫn có tham số bên Vue (`/friends/:friendId`, `/admin/messages/:userId`) thành truy vấn: `/friends?thread=<id>`, `/admin/messages?user=<id>`; nginx cần `rewrite ^/friends/(.+)$ /friends?thread=$1` (và tương tự) cho đường dẫn cũ.

## Đã xong (nền móng)
- Khung dự án, xuất tĩnh, bố cục gốc (giao diện sáng/tối trước khi vẽ, manifest PWA, service worker, font).
- `src/lib/*.js`: toàn bộ module thuần (tính điểm, thống kê tiền, phân tích tin nhắn, mã hoá 2 đầu, offline rules...) chép nguyên từ Vue, **69 test cũ chạy nguyên** (`npm test`).
- `src/lib/authStore.js` (zustand, thay Pinia `stores/auth`), `src/lib/api.js`, `src/lib/lotteryStations.js` (không còn `reactive`), `src/lib/routes.ts` (bảng route + chuyển hướng cũ).
- `AuthGate`: chặn route như `router.beforeEach` (chưa đăng nhập → `/login?redirect=`, admin/khách tách khu vực, quyền admin).
- Mỗi route có `page.tsx` đang là `ScreenStub`; chuyển màn nào thì thay stub bằng màn thật.

## Còn lại (bản đồ Vue → Next)
| Vue | Việc |
|---|---|
| `stores/{mask,notify,policy,privacy,call}.js`, `e2ee/chat.js`, `session.js`, `offline.js`, `theme.js`, `confirm.js`, `packageLabels.js`, `pasteImage.js` | viết lại bằng zustand / hook (chứa `ref`/`reactive`/`computed` của Vue) |
| `components/*.vue` (40 file) | chuyển sang `src/components/*.tsx`; `ModalDialog`, `AppButton`, `AppSelect`, `AppDatePicker`, `AppIcon` làm trước (mọi màn dùng) |
| `views/LoginView`, `RegisterView`, `AuthLayout` | đăng nhập / đăng ký (2 lớp mật khẩu, khôi phục) |
| `components/AppShell` + `App.vue` | khung (thanh trên, menu, popover Phản hồi, thông báo, cuộc gọi, khoá riêng tư) |
| `views/EntriesView` (3.1k dòng), `ResultsView` (1.8k), `ScoringView`, `CustomersView`, `FriendsView` (2k), `AccountView`, `ScoringSettings` | các màn khách |
| `views/admin/*` (7 màn) | khu admin |

Quy ước: mỗi màn chuyển xong phải có test hành vi tương đương bản Vue, rồi mới bỏ `ScreenStub`. Khi toàn bộ xong: đổi `deploy/deploy-web.sh` sang gói `web-next/out`, rồi xoá `frontend/`.
