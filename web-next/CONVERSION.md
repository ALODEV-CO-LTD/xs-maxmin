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

## Đã xong (giai đoạn 2: store, thành phần dùng chung, khung app, đăng nhập)
- Store (zustand, trong `src/lib`, giữ tên hàm của bản Vue): `maskStore`, `notifyStore` (getter là selector: `useNotifyStore(totalOf)`), `policyStore`, `privacyStore`, `session.js` (`teardownSession`), `theme.js`, `confirm.js`, `packageLabels.js` (+ `usePackageLabel`), `pasteImage.js` (`usePasteImage` hook), `offline.js` (`useSyncStore`/`syncState`), `useStations.js` (hook trên `lotteryStations`).
- `src/lib/hooks.js` là chỗ cắm cho phần chưa chuyển (call store, e2ee/chat): `registerTeardown`, `hooks.inCall`, `hooks.markFriendRead`, `registerShellStart` (vd. `call.connect()`), `registerUserReady` (vd. `chat.init(user)`), `registerShellOverlay` (CallOverlay), và `navigate()` / `currentLocation()` thay router. Địa chỉ toast là chuỗi (`/friends?thread=<id>`, `/admin/messages?user=<id>`, `/feedback` = mở popover Phản hồi).
- `src/components`: ModalDialog, ConfirmDialog, AppButton, AppSelect (onChange nhận giá trị, con là `<option>`), AppDatePicker, AppIcon, PasswordInput, MaskedValue, ThemeToggle, ActionBar, SyncStatus, AnnouncementBanner, ScreenWatermark, PrivacyGuard, PasswordPromptDialog, MessageToast, RecoveryCodeDisplay/Panel, AttachmentPreview, ChatAttachButtons, MessageAttachment, SupportChat, AuthLayout, AppShell. CSS của mỗi thành phần lấy nguyên từ file .vue (global, tên lớp có tiền tố nên không đụng nhau).
- `Providers` bọc `<div id="app">` (PrivacyGuard làm `inert` phần này khi khoá), bật chặn chụp màn hình khi đăng nhập, gọi `teardownSession()` khi phiên kết thúc, và đặt `AppShell` quanh mọi route không công khai. Trang `/login`, `/register` là `LoginScreen`/`RegisterScreen`, logic thuần ở `lib/authFlow.js`. Sau đăng nhập `AuthGate` chuyển tới `?redirect=` (chỉ đường dẫn trong trang) hoặc trang chủ.
- Test: `tests/stores.test.mjs`, `tests/auth.test.mjs` (không cần trình duyệt; `tests/stubs.mjs` giờ cho phép import không đuôi `.js`).

## Còn lại (bản đồ Vue → Next)
| Vue | Việc |
|---|---|
| `stores/call.js`, `e2ee/chat.js` | viết lại bằng zustand rồi cắm vào `lib/hooks.js` (xem trên) |
| `components/*.vue` còn lại (AccountStats, AddBetTypeDialog, AdminChatPane, AdminRecoveryRequests, AppVersionPanel, CallOverlay, ChatCalcDialog, ChatDecodeDialog, ChatRetentionPanel, DeleteDataDialog, DeletionSchedules, PrivacySettings, ScoringConfigEditor, ScoringSummary, StatsChart) | chuyển cùng màn dùng chúng |
| `views/EntriesView` (3.1k dòng), `ResultsView` (1.8k), `ScoringView`, `CustomersView`, `FriendsView` (2k), `AccountView`, `ScoringSettings` | các màn khách |
| `views/admin/*` (7 màn) | khu admin |

Quy ước: mỗi màn chuyển xong phải có test hành vi tương đương bản Vue, rồi mới bỏ `ScreenStub`. Khi toàn bộ xong: đổi `deploy/deploy-web.sh` sang gói `web-next/out`, rồi xoá `frontend/`.
