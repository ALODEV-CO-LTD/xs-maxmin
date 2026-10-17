# MAMBA (XS Maxmin) – Tài liệu bàn giao dự án

> Cập nhật: 13/10/2026 · Nhánh làm việc hiện tại: `mask-short` (chứa toàn bộ công việc mới nhất) · Bản đang chạy: https://xs.massagehomeriyadh.com/
>
> **Tài liệu này không chứa mật khẩu thật, token hay khoá bí mật** (chỉ nhắc mật khẩu mock của dữ liệu seed trong code, mục 4 và 10). Các giá trị thật được bàn giao riêng (xem mục 10).

## 1. Dự án là gì

Ứng dụng tính toán dữ liệu xổ số kèm quản lý khách hàng, bạn bè – nhắn tin – gọi thoại, gói dịch vụ và thanh toán. Tên thương hiệu hiện tại là **MAMBA** (logo vàng, đã áp dụng cho web và biểu tượng cài app). Trong code và hạ tầng vẫn còn tên cũ `xoso` / `xs-maxmin`, chưa đổi vì không ảnh hưởng người dùng.

Hai vai trò:
- **Khách hàng (user):** nhập số, nhập kết quả xổ số, tính điểm, quản lý khách hàng của mình, kết bạn – nhắn tin – gọi thoại, phản hồi cho Admin, mua gói.
- **Admin:** quản lý người dùng, duyệt thanh toán, gia hạn, thống kê, trả lời phản hồi, thông báo bảo trì, sao lưu, cài đặt hệ thống, nhật ký bảo mật.

Hai khái niệm dễ nhầm: **tài khoản** (người đăng nhập, có gói dịch vụ) và **khách hàng** (người mà tài khoản đó ghi số cho – chỉ là một cái tên trong danh sách `customers`, không phải người dùng hệ thống).

## 2. Công nghệ

| Phần | Công nghệ |
|---|---|
| Frontend | Vue 3 (`<script setup>`), Pinia, vue-router, Vite 8. Không dùng UI framework, style tự viết trong `src/styles/tokens.css` và từng component |
| OCR | `tesseract.js` chạy trong trình duyệt, file mô hình được phục vụ từ chính site (`/tesseract/`), không dùng CDN |
| Backend | Dart Frog (Dart), SQLite (`sqlite3`), `bcrypt`, `dart_jsonwebtoken` |
| Realtime | WebSocket `/api/ws/calls` (báo tin nhắn mới + báo hiệu cuộc gọi), WebRTC cho gọi thoại (không có video) |
| Gọi thoại qua mạng ngoài | STUN/TURN. Đang dùng **Cloudflare Realtime TURN** (xem mục 7) |
| Offline | Service worker `public/sw.js` + hàng đợi IndexedDB (`src/offline.js`) |
| App Android + iOS | Flutter, thư mục `app/` (xem mục 9c); thông báo đẩy qua APNs (iOS) và FCM (Android), xem mục 9e, 9f |
| Hạ tầng | Proxmox host `10.5.100.5` → container `501` → nginx + systemd + Cloudflare Tunnel |

## 3. Cấu trúc thư mục

```
xs-maxmin/
├─ backend/            Dart Frog API
│  ├─ routes/          mỗi file = một endpoint (đường dẫn = đường dẫn API, xem mục 5)
│  ├─ lib/src/         logic dùng chung: database.dart (schema + migration), sessions.dart, security.dart,
│  │                   auth_middleware.dart, reauth_limit.dart, password_policy.dart, recovery_codes.dart,
│  │                   data_wipe.dart, deletion_scheduler.dart, customer_codes.dart, push.dart, call_log.dart ...
│  ├─ test/            test đơn vị/route bằng `dart test`
│  └─ schema.sql       bản mô tả schema tham khảo (nguồn thật là lib/src/database.dart)
├─ frontend/
│  ├─ src/views/       các trang (Entries, Results, Scoring, ScoringSettings, Customers, Friends, Packages, Account, admin/*)
│  ├─ src/components/  thành phần dùng chung (AppShell, MaskBar, SupportChat, PrivacyGuard, ...)
│  ├─ src/stores/      Pinia: auth, call, notify, mask, privacy
│  ├─ src/assets/      logo MAMBA (+ bản gốc mamba-logo-original.webp)
│  └─ public/          manifest, icon, service worker, mô hình OCR
├─ app/                App Android + iOS (Flutter): lib/core, lib/features/*, test/ (xem mục 9c)
├─ deploy/             deploy.sh (web + backend), deploy-web.sh (chỉ web) – chạy trong container 501
├─ tools/              e2e/ (script puppeteer, xem tools/e2e/README.md) và seed_demo.py (tạo dữ liệu demo)
└─ docs/
   ├─ BAN_GIAO.md      tài liệu này
   ├─ MA_HOA_2_DAU.md  kế hoạch và thiết kế mã hoá 2 đầu cho chat bạn bè
   └─ yeu_cau/         SRS gốc, SRS thống nhất v2, bảng tiến độ chức năng (csv/xlsx)
```

## 4. Chạy trên máy cá nhân

Yêu cầu: Node 20+, Dart SDK 3.x, `dart_frog_cli` (`dart pub global activate dart_frog_cli`).

```bash
# Backend (cổng 8080). DB tự tạo ở backend/data/xoso.db khi chạy lần đầu, kèm dữ liệu mẫu.
cd backend
dart pub get
export XOSO_JWT_SECRET="$(openssl rand -hex 32)"     # nên đặt cố định để không bị đăng xuất mỗi lần chạy lại
dart_frog dev --port 8080

# Frontend (cổng 5173, tự chuyển /api sang 8080, kể cả WebSocket)
cd frontend
npm install
npm run dev -- --host          # --host để máy khác cùng mạng LAN truy cập được
```

- Mở http://localhost:5173. Tài khoản mẫu có trong `_seed()` của `backend/lib/src/database.dart` (admin `1`/`1234`; khách `2`–`6` mật khẩu `1235`–`1239`).
- Tắt `dart_frog dev` bằng cổng, **đừng dùng `pkill -f dart_frog`** (đã từng giết nhầm server của người khác).
- Trên link LAN (HTTP không phải localhost) trình duyệt không cho dùng micro và thông báo đẩy, nên không thử gọi thoại được; dùng bản thật hoặc HTTPS.
- Chạy test backend: `cd backend && dart test`. Build web: `cd frontend && npm run build` (có bước `prebuild` copy mô hình OCR).

## 5. Tính năng và API chính

Bảng đầy đủ theo từng mã yêu cầu (K01…, A01…, S01…, NFR…) nằm ở `docs/yeu_cau/tien_do_chuc_nang.csv` (96 mục, có cột "thực tế" và "đã lên máy chủ thật chưa"). Tóm tắt:

**Khách hàng:** đăng ký/đăng nhập 2 lớp (mật khẩu + mật khẩu lớp 2), mã khôi phục dùng một lần, khôi phục tài khoản, đổi mật khẩu, mật khẩu xoá dữ liệu, quản lý thiết bị đang đăng nhập, **nhờ Admin hỗ trợ khôi phục** (gửi yêu cầu → Admin duyệt → mã hỗ trợ một lần 24 giờ → tự đặt mật khẩu mới), nhập số (tay, OCR ảnh, dán tin nhắn; chọn đài, mặc định theo từng khách), nhập kết quả xổ số **Miền Bắc / Miền Trung / Miền Nam theo từng đài** (bảng đài theo thứ trong tuần ở `backend/lib/src/lottery_stations.dart`; kết quả lưu theo (ngày, đài); số liệu cũ không có đài tính là Miền Bắc; OCR ảnh: Miền Bắc một bảng 27 số; Miền Nam/Miền Trung hiện thành **một bảng nhiều đài như tờ kết quả in** (mỗi đài một cột, hàng từ Giải tám ở trên đến Đặc biệt ở dưới), ảnh được đọc rồi điền thẳng vào đúng cột (`frontend/src/lotteryColumns.js`, bỏ phần ngày ở dòng tiêu đề khỏi các giải), ô sai độ dài viền đỏ, một nút lưu cho tất cả cột đã nhập đủ, mỗi cột đã lưu có nút xoá riêng; có thể dán ảnh Ctrl/Cmd+V ở các khu nhập ảnh), tính điểm theo ngày, tổng kết tiền theo khách trong Tính điểm (đầu trang: ba ô tiền gửi / tiền trúng / còn lại, rồi bảng theo ngày; lọc theo miền) ((1) tiền khách gửi: số lô, điểm, quy ra đồng; (2) lô trúng; (3) còn lại = (1) − (2); mỗi loại đánh có "đánh theo điểm" kèm 1 điểm = bao nhiêu đồng, hoặc "đánh theo tiền"), cấu hình loại đánh **theo từng miền** (tab Miền Bắc/Trung/Nam; khoá `loai` = mọi miền, `loai@mb|mt|mn` = riêng một miền; nút "+ Thêm loại đánh" ở mỗi tab tạo loại **chỉ dùng cho miền đó** (khoá `loai@mien` không có `loai`, hàm `typesIn` trong `scoringConfig.js`); trong trang Khách hàng: nút Cấu hình tính điểm mặc định và, ở cột Thao tác của từng khách, nút **Cấu hình tính điểm** (cửa sổ cố định kích thước, chỉ còn đài mặc định và cấu hình) và nút **Sửa** (đổi số điện thoại)), khách hàng, **Ẩn số liệu** (che số trên Nhập số/Khách hàng/Tính điểm, hiện có thời hạn và cần mật khẩu), xoá dữ liệu theo ngày hoặc đặt lịch (một lần/lặp lại), mã ID kết bạn (tự chọn dãy số, nhiều ID ảo), bạn bè + nhắn tin + gọi thoại + huy hiệu chưa đọc, **Phản hồi cho Admin** (popover cạnh nút sáng/tối), gói dịch vụ (Admin chỉnh được danh mục gói) + chuyển khoản (VietQR) + lịch sử (nằm trong Tài khoản, tab "Gói & Thanh toán"; `/packages` tự chuyển tới đó), khoá tự động.

**Admin:** chính sách bảo mật và sao lưu (nằm trong **Cài đặt** dạng tab; địa chỉ cũ `/admin/security-policy`, `/admin/backups` tự chuyển vào đó; `backend/lib/src/security_policy.dart`: số lần nhập sai, thời gian khoá, thời hạn đăng nhập, tự khoá mặc định, dấu tên người xem, che màn hình khi bấm phím chụp, **làm mờ khi ẩn trang/mất focus** `blurOnHideEnabled` mặc định tắt), phân quyền nhiều cấp (Admin gốc tạo tài khoản thứ cấp và tích chọn quyền, trang `/admin/staff`, API `/admin/staff`, `backend/lib/src/permissions.dart`), quản lý khách (khoá/mở, đặt lại mật khẩu, cấp lại mã khôi phục, gỡ khoá, thu hồi phiên), hàng đợi yêu cầu khôi phục (`/admin/recovery-requests`), duyệt/từ chối thanh toán (mã tham chiếu, lọc, phân trang, doanh thu, xuất CSV), gia hạn, thống kê, phản hồi khách, thông báo bảo trì (banner), sao lưu DB, cài đặt (ngân hàng, giá), nhật ký bảo mật.

**Nhóm endpoint** (`backend/routes/api/`): `auth/*` (login, step2, register, recover, recovery-request, recover-with-ticket, confirm-wipe) · `me/*` (hồ sơ, mật khẩu, phiên, entries, customers, friends, messages, unread, calls, deletion-schedules, scoring-settings, packages, payment-requests, customer-codes…) · `admin/*` · `calls/ice-servers` · `lottery-results` · `announcements` · `ws/calls`.

**Quy ước quan trọng:**
- Token JWT có `sid` (phiên thiết bị) và `type`; mọi request kiểm tra phiên còn hiệu lực. Đổi mật khẩu/khôi phục/khoá tài khoản thu hồi mọi phiên (`tokens_valid_after`).
- Các endpoint "nhập lại mật khẩu" (`/me/verify-password`, xoá dữ liệu, tắt ẩn số liệu…) trả **403** khi sai (không phải 401, để client không tự đăng xuất) và **429** khi bị khoá tạm (`reauth_limit.dart`).
- Đăng nhập sai khoá tạm tăng dần 30 giây → 15 phút (`sessions.dart`), có chống dò tên đăng nhập.
- Mật khẩu (đăng nhập, lớp hai, xoá dữ liệu) đặt tuỳ ý: không giới hạn dưới (chỉ không để trống), tối đa 72 byte vì bcrypt chỉ dùng 72 byte đầu (`password_policy.dart`). Chỉ còn ràng buộc: tên đăng nhập không trùng; mật khẩu xoá dữ liệu phải khác mật khẩu lớp hai và mật khẩu đăng nhập (vì nhập ở bước 2 sẽ kích hoạt xoá).
- Tin nhắn mới đẩy qua WebSocket; ngoài ra client tự đối chiếu `/me/unread` mỗi 10 giây (dự phòng khi mạng chặn WebSocket).
- Lỗi 401 ở client → `api.js` xoá phiên → `App.vue` chuyển về `/login?redirect=...`. Đăng xuất chủ động thì không giữ `redirect`.

## 6. Cơ sở dữ liệu

SQLite một file. Local: `backend/data/xoso.db`. Máy chủ: `/opt/xs-maxmin/backend/build/data/xoso.db`.

Bảng: `users`, `device_sessions`, `login_attempts`, `security_events`, `data_entries`, `customers`, `customer_codes`, `retired_codes`, `customer_syntax_templates`, `lottery_results` (theo tài khoản, `user_id`), `friendships`, `direct_messages`, `message_reads`, `messages` (hỗ trợ Admin), `call_logs`, `deletion_schedules`, `payment_requests`, `transactions`, `packages`, `settings`, `announcements`.

Migration: thêm cột bằng `_ensureColumn(...)` trong `lib/src/database.dart` (tự chạy khi khởi động). SQLite không sửa được ràng buộc `CHECK` – nếu cần đổi, phải tạo lại bảng. Seed (admin + 5 tài khoản mẫu) chỉ chạy khi DB trống.

## 7. Triển khai và vận hành

```
Internet ── Cloudflare Tunnel (cloudflared-xs-massage) ── nginx :80 (xs-maxmin.conf)
                                                          ├─ /       → /opt/xs-maxmin/web (file tĩnh)
                                                          └─ /api/   → 127.0.0.1:9091 (xs-maxmin-backend, có WebSocket)
```

- Host Proxmox `10.5.100.5`, container **501**. Truy cập: `ssh root@10.5.100.5 'pct exec 501 -- <lệnh>'`.
- **Container này còn chạy các site khác** (`demo3`, `henho`, `mamba-xs`, `mamba-api`, `hh-mamba`). Chỉ động vào `xs-maxmin-backend`, `cloudflared-xs-massage` và `xs-maxmin.conf`.
- Backend: service systemd `xs-maxmin-backend` (`WorkingDirectory=/opt/xs-maxmin/backend/build`, `PORT=9091`), log ở `/var/log/xs-maxmin/backend.log`.

**Deploy chỉ web** (không đăng xuất ai):
```bash
cd frontend && npm run build
COPYFILE_DISABLE=1 tar --no-xattrs --no-mac-metadata --exclude='._*' -czf /tmp/web_dist.tar.gz -C dist .
scp /tmp/web_dist.tar.gz deploy/deploy-web.sh root@10.5.100.5:/tmp/
ssh root@10.5.100.5 'pct push 501 /tmp/web_dist.tar.gz /root/web_dist.tar.gz; pct push 501 /tmp/deploy-web.sh /root/deploy-web.sh; pct exec 501 -- bash /root/deploy-web.sh'
```

**Deploy cả backend** (từ 13/10/2026 `XOSO_JWT_SECRET` đã đặt cố định trên máy chủ nên khởi động lại không còn đăng xuất mọi người; lần đặt đầu tiên thì có):
```bash
cd backend && tar --no-xattrs --no-mac-metadata --exclude='._*' -czf /tmp/backend_deploy.tar.gz lib routes pubspec.yaml pubspec.lock schema.sql
# gửi backend_deploy.tar.gz + web_dist.tar.gz + deploy/deploy.sh vào /root của container 501 như trên, rồi:
ssh root@10.5.100.5 'pct exec 501 -- bash /root/deploy.sh'
```
`deploy.sh` tự sao lưu `backend`, `web` và DB trước khi làm, build lại bằng `dart_frog build`, khởi động lại, kiểm tra và **tự quay lại bản cũ nếu lỗi**. Lưu ý đã gặp: file `._*` của macOS làm hỏng gói (đã lọc bằng cờ ở trên), và thư mục `.dart_tool` chứa cache native của `sqlite3` được sao chép từ bản trước vì máy chủ không tải được từ GitHub.

Quay lại thủ công: `systemctl stop xs-maxmin-backend; rm -rf /opt/xs-maxmin/backend; cp -a /opt/xs-maxmin/backend.bak-<mã giờ> /opt/xs-maxmin/backend; (tương tự cho web); systemctl start xs-maxmin-backend`. Các thư mục `*.bak-*` và `/root/xoso-*.db` đang tích luỹ, nên dọn định kỳ.

**Biến môi trường backend** (đặt qua drop-in `/etc/systemd/system/xs-maxmin-backend.service.d/*.conf`, sau đó `systemctl daemon-reload && systemctl restart xs-maxmin-backend`):

| Biến | Ý nghĩa | Trạng thái |
|---|---|---|
| `XOSO_JWT_SECRET` | Khoá ký token (≥16 ký tự). Không đặt thì mỗi lần khởi động tạo khoá ngẫu nhiên ⇒ đăng xuất toàn bộ | **Đã đặt (13/10/2026)** trong drop-in `jwt.conf` (quyền 600); đừng xoá, mất khoá là đăng xuất toàn bộ |
| `XOSO_CF_TURN_KEY_ID`, `XOSO_CF_TURN_API_TOKEN` | Khoá Cloudflare Realtime TURN | Đã đặt (file `turn.conf`, quyền 600) |
| `XOSO_FCM_CREDENTIALS_PATH`, `XOSO_FCM_PROJECT_ID` (và khoá APNs, xem mục 9e) | Thông báo đẩy Android (FCM) / iOS (APNs) | **Chưa cấu hình trên máy chủ**, chi tiết cách bật ở mục 9e, 9f |
| `XOSO_STUN_URLS`, `XOSO_TURN_URLS`, `XOSO_TURN_SECRET` / `XOSO_TURN_USERNAME` + `XOSO_TURN_CREDENTIAL` | Phương án TURN tự dựng (coturn) thay cho Cloudflare | Không dùng |

TURN của Cloudflare: tạo khoá ở Dashboard → Realtime → TURN (hoặc API `POST /accounts/{id}/calls/turn_keys`; **mã bí mật `secret` chỉ hiện đúng một lần lúc tạo**). Kiểm tra: đăng nhập rồi gọi `GET /api/calls/ice-servers` – phải thấy `"turn": true`.

## 8. Kiểm thử

- Backend: `cd backend && dart test` (xác thực, xoá dữ liệu, lịch xoá lặp lại, mã ID, tìm kiếm không dấu, nhật ký cuộc gọi, quyền riêng tư).
- Giao diện/API: `tools/e2e/*.mjs` (puppeteer + Chrome cài trên máy). Cách dựng môi trường cô lập ở `tools/e2e/README.md`. Mỗi lần kiểm thử nên chạy backend riêng (bản sao thư mục `backend` + `XOSO_JWT_SECRET` riêng) để không đụng DB thật.
- App Flutter: `cd app && flutter test` (176 test lúc viết mục 9c) và `flutter analyze`. Đã cài thử APK trên Android và iPhone; các mục chưa thử trên máy thật được liệt kê ở 9c và 9g.
- Bộ đọc tin nhắn: `cd frontend && npm test` (16 test `node:test` trong `frontend/tests/messageParser.test.mjs`, không cần cài thêm).
- Chưa có CI.

## 9. Tình trạng công việc

**Đã xong và đã lên máy chủ thật:** toàn bộ các mục ở mục 5; lần deploy gần nhất 13/10/2026 (xem 9g). Sửa `screenshotGuard.js` (báo chụp màn hình khi tắt che màn hình) đã commit và deploy web 13/10.

**Đối chiếu bản đang chạy với mã nguồn (16/10/2026, commit `a0c43b3`):** web khớp **21/21 tệp** (so từng tệp trong `frontend/dist` với https://xs.massagehomeriyadh.com/). Backend khớp **115/116 tệp** `.dart` trong `lib/` và `routes/`; tệp duy nhất khác là `backend/lib/src/database.dart`: máy chủ còn bản cũ, trong đó đoạn dọn lịch sử chat bạn bè cũ nằm ở bước tạo bảng; bản mới (commit `a16679d`) chuyển đoạn đó ra sau để tạo được DB trống. Khác biệt này **không ảnh hưởng DB đang chạy**, chỉ lộ khi dựng máy chủ mới từ DB rỗng. Vì vậy mọi tính năng trong bảng tiến độ ở trạng thái "Đã lên máy chủ thật" thực sự đang chạy; deploy backend lần sau sẽ đưa nốt thay đổi này lên.

**Chưa làm hẳn / làm một phần** (chi tiết từng mã trong `tien_do_chuc_nang.csv`):
- Chưa làm: mã hoá đầu cuối cho phản hồi Admin và dữ liệu số liệu/khách hàng (K28; chat bạn bè đã mã hoá, xem `docs/MA_HOA_2_DAU.md`), đổi giọng nói đầy đủ (K30; hiện mới có nút "Méo giọng" trong cuộc gọi), chính sách lưu trữ trên app (A08: web như hiện tại, app lưu trên máy và xoá sạch được), quản lý quyền camera/vị trí/thông báo (K39), tách dịch vụ (NFR-08), Face ID. (Phân quyền Admin A07, quản lý phiên bản app A17 và app Android/iOS đã làm: xem 9b–9d.)
- Một phần: bảo vệ chụp màn hình (K33 – web: Ẩn số liệu, che khi bấm phím chụp, dấu tên người xem; app: Android FLAG_SECURE, iOS screen_protector, chưa thử iOS thật; xem 9g), xác thực lớp 2/mật khẩu dữ liệu riêng, mã hoá dữ liệu khi lưu (SQLite chưa mã hoá), đồng bộ/offline (đã có hàng đợi nhập số, chưa phủ hết), quản lý thanh toán (A18 đã mở rộng, chưa có đối soát tự động với ngân hàng).

**Chống chụp màn hình:** web chỉ giảm rủi ro (không chặn được); chặn thật ở app (Android `FLAG_SECURE`, iOS `screen_protector`). Còn chờ quyết định: trên Android không thể vừa chặn chụp vừa báo bạn chat khi bị chụp (xem 9g). PC (Electron `setContentProtection`) chưa làm.

**Quyết định còn mở (cần người phụ trách chốt):**
1. ~~Kết quả xổ số dùng chung~~ — **đã chốt: theo từng tài khoản** (`lottery_results.user_id`, duy nhất theo tài khoản + ngày + đài). Tài khoản khác không thấy và không ghi đè. Bản dùng chung cũ giữ ở bảng `lottery_results_shared_legacy` và được sao cho mọi tài khoản khách hàng khi nâng cấp. App lưu kết quả trên máy trước rồi tự đồng bộ khi có mạng.
2. Mật khẩu lớp 2 hiện bắt buộc khi đăng ký mới (≥4 ký tự) nhưng các tài khoản tạo sẵn từ seed không có – có ép tất cả tài khoản cũ phải đặt không.
3. Kết bạn: có cần bên kia chấp nhận không (hiện thêm bằng mã ID là thành bạn ngay).
4. Tự xoá dữ liệu sau n lần nhập sai (YC4) – làm hay không.
5. Gộp PR #1 trên GitHub và đẩy các nhánh mới lên (chưa đẩy).
6. Các điểm DC01–DC04 trong bảng tiến độ (vai trò nhân viên hỗ trợ, tiêu chí nghiệm thu, ma trận kiểm thử, phạm vi pháp lý).

## 9b. Nhật ký thay đổi gần đây (10/10/2026)

Mỗi dòng là một nhóm commit (mới nhất ở trên). **Đã deploy lên máy chủ thật đến `b2fd4e1`** (11/10/2026, bản sao lưu `backend.bak-20261011-071119`).

- `b2fd4e1` (Admin) Gói dịch vụ chỉnh được (bảng `packages` trong DB, API `/admin/packages`, tạo tự động khi khởi động và nạp từ giá cũ), thống kê có biểu đồ (`StatsChart.vue`), tách quyền `maintenance.manage` (route `/admin/maintenance`), gộp Duyệt thanh toán và Gia hạn thành một trang. `tools/seed_demo.py` tạo dữ liệu demo.
- `1153f10`, `c7eac0f`, `da8df57` Khách hàng: **"+ Thêm khách hàng" mở cửa sổ nhỏ** (tên, SĐT, đài mặc định; cấu hình tính điểm đặt sau); bảng khách các cột đều nhau, căn giữa; bảng Nhập số các cột đều nhau, nhãn đài ngắn.
- `24dcaff` Tài khoản: tab Mật khẩu gộp vào Hồ sơ, ba nút (Đổi mật khẩu, lớp hai, xoá dữ liệu) mở hộp thoại; `?tab=security` mở Hồ sơ.
- `a1a4fba`, `f0cf88e` Nhập kết quả: danh sách Điểm ra chỉ hiện số liệu của ngày đang nhập, **tự tính theo công thức từng khách và tự lưu** khi lưu kết quả xổ số (không nhập tay).
- `abb029b`, `404b6ff`, `7f3abec`, `34e333d`, `73d7c13` Giao diện: ô chọn thay cho dãy nút lọc (trạng thái thanh toán, khoảng thời gian ở Tính điểm), tab Tài khoản là nút rời, Cài đặt Admin chỉ hiển thị và bấm **Sửa** mới chỉnh (Thanh toán, Giá gói, Giới hạn ID, Chính sách bảo mật), Chính sách bảo mật và Sao lưu nằm trong Cài đặt.
- `f648f98`, `ef6f14f`, `d0e8be0` Nhập kết quả: kết quả đã lưu hoặc vừa đọc từ ảnh chỉ hiển thị, nút **Sửa** cạnh Xoá form; ô nhập có viền, ghi số ô và số chữ số, chỉ nhận chữ số; nút ngày trước/sau.
- `25adcec` Bảng Khách hàng cân cột.
- Làm mờ khi ẩn trang **tắt mặc định** (`blurOnHideEnabled=false`); Admin bật ở Chính sách bảo mật khi cần. Code giữ nguyên.
- `6cfb9b9` Làm mờ khi ẩn trang bật mặc định; Admin tắt được ở Chính sách bảo mật, mỗi người tắt được ở Tài khoản (`policy.blurOnHideEnabled`, `/me/policy`, `stores/privacy.js`).
- `95915dc` Nhập kết quả Miền Nam/Trung: một bảng nhiều đài như ảnh mẫu; ảnh điền thẳng vào bảng; sửa lỗi ngày ở tiêu đề ảnh bị đọc thành giải.
- `a9be429` Cấu hình tính điểm: gọn và khoá kích thước (đổi miền không giật); loại đánh riêng từng miền; cửa sổ khách chỉ còn đài mặc định + cấu hình; bỏ 4 ô thống kê, hàng sao chép và nút xoá trong cửa sổ; nút "Xem chi tiết" đổi thành "Cấu hình tính điểm"; thêm nút "Sửa" số điện thoại; bỏ dòng chú thích dưới nút cấu hình mặc định.
- `05b0160` Bỏ nút lưu hàng loạt thừa ở khu đọc ảnh nhiều đài.
- `a38a8c1` Khôi phục làm mờ (commit gốc `8f2f28e` đã gỡ nó) và chuyển thành chính sách Admin.
- `76f81a3` Làm lại cấu hình tính điểm theo miền và tab Tính điểm (tổng kết trước, chi tiết sau).
- `403cdc3`, `8d399aa` Nhập kết quả Miền Trung/Nam theo đài, đọc ảnh nhiều đài, dán ảnh.
- `c3f1597` Tổng kết tiền theo khách (tiền gửi, lô trúng, còn lại).
- Trước đó trong cùng đợt: cấu hình tính điểm chuyển sang trang Khách hàng, thêm/sửa/xoá loại đánh, bảng khách có số điện thoại, biểu đồ tài khoản, xoá metadata ảnh, hỗ trợ khôi phục tài khoản, mã hoá 2 đầu cho chat, chính sách bảo mật của Admin, chống chụp màn hình trên máy tính, gói & thanh toán chuyển vào Tài khoản (xem `git log`).

Việc kiểm tra tay trong đợt này: chuyển tab Miền Bắc/Trung/Nam trong cấu hình không đổi kích thước (hộp 955px, danh sách 272px, mỗi dòng 144px ở khung 1300×800); dán ảnh mẫu XSMN 07/10 và XSMT 09/10 điền đúng 100% số. Chưa thử: bấm Lưu bảng nhiều đài với dữ liệu thật, giao diện cấu hình trên điện thoại thật.

## 9c. Ứng dụng Android (Flutter) - thư mục `app/`

Bản app khách hàng cho Android, dùng chung API với bản web. Chạy: `cd app && flutter pub get && flutter run --dart-define=API_BASE=http://10.0.2.2:8080` (emulator + backend local) hoặc `flutter run` (máy chủ thật). Build: `flutter build apk --release`; cần cài Android SDK (Android Studio). Lúc viết mục này máy phát triển chưa có SDK nên chưa build được; về sau đã build APK `MAMBA.apk` và cài thử trên Android + iPhone (xem 9g).

- Cấu trúc: `lib/core` (API client, phiên đăng nhập, theme, đài/miền, cấu hình tính điểm, Ẩn số liệu), `lib/features/{entries,customers,results,scoring,friends,account,auth,shell}`, `lib/app.dart` (router + providers).
- Đã có: đăng nhập 2 lớp, đăng ký, khôi phục (kể cả nhờ Admin), Nhập số (tay, dán tin nhắn, ảnh bằng ML Kit, hàng đợi offline), Khách hàng và cấu hình tính điểm theo miền, Nhập kết quả (Miền Bắc, bảng Miền Nam/Trung, đọc ảnh), Tính điểm (tổng kết tiền), Bạn bè (chat mã hoá 2 đầu tương thích bản web, ảnh, gọi thoại WebRTC), Tài khoản (hồ sơ, mật khẩu, thiết bị, gói và thanh toán, thống kê), chống chụp màn hình (FLAG_SECURE), tự khoá, làm mờ theo chính sách.
- **Khu Admin trong cùng app** (`lib/features/admin/`, ngăn kéo theo quyền như bản web): Thống kê (biểu đồ), Khách hàng (khoá, thiết bị, đặt lại mật khẩu, khôi phục), Thanh toán & gia hạn, Phản hồi (hộp thư hỗ trợ), Thông báo & bảo trì, Cài đặt (thanh toán, gói, giới hạn ID, nhật ký, chính sách bảo mật, sao lưu; chỉ hiển thị, bấm Sửa mới chỉnh), Phân quyền (Admin gốc). App tự chọn giao diện khách hàng hoặc Admin theo vai trò tài khoản đăng nhập.
- **Nhắn tin và gọi chạy toàn app** (`MessagingHost`, `lib/features/friends/`): kết nối WebSocket giữ suốt khi đã đăng nhập tài khoản khách hàng, cuộc gọi đến hiện trên mọi màn hình (chuông, rung, nhận/từ chối), huy hiệu tin chưa đọc, thông báo Android (không lộ nội dung tin), tuỳ chọn "Giữ kết nối khi thoát app" (dịch vụ nền, mặc định tắt, tốn pin). Tin nhắn mã hoá 2 đầu không lưu trên máy chủ nên vẫn chỉ nhận được khi tiến trình app còn sống.
- Chưa có: dấu tên người xem, lịch xoá dữ liệu, "méo giọng" (thư viện WebRTC không cho xử lý micro), (đã bổ sung sau: thông báo đẩy FCM/APNs, bản iOS, xem 9e–9g). Chưa thử trên điện thoại thật: chuông cuộc gọi, thông báo, dịch vụ nền, âm thanh WebRTC giữa hai máy.
- Cần kiểm tra trên máy thật: camera/ML Kit, gọi thoại, FLAG_SECURE, phát hiện chụp màn hình (Android 14+), minSdk của ML Kit.

## 9d. Quản lý phiên bản ứng dụng (A17)

Admin đặt trong **Cài đặt > Phiên bản ứng dụng** (web: `components/AppVersionPanel.vue`; app Admin: `features/admin/settings/settings_appversion.dart`; chỉ hiển thị, bấm Sửa mới chỉnh): phiên bản mới nhất, phiên bản tối thiểu còn được dùng (dạng `x.y.z`, tối thiểu ≤ mới nhất), đường dẫn tải (bắt buộc `https://`), ghi chú (≤ 500 ký tự). Lưu trong bảng `settings` (khoá `app_latest_version`, `app_min_version`, `app_download_url`, `app_release_notes`; các khoá này không hiện ở "Khoá khác"). API: `GET/PUT /api/admin/app-version` (quyền `settings.manage`, ghi nhật ký bảo mật `app_version_changed`) và `GET /api/app-version` **công khai** (app hỏi trước khi đăng nhập). Code: `backend/lib/src/app_version.dart`.

App Android (`features/shell/update_gate.dart`, `core/app_version.dart`) hỏi khi mở và khi quay lại sau hơn 1 giờ: thấp hơn bản mới nhất thì hiện thẻ nhắc (bấm "Để sau" thì nhớ theo từng phiên bản), thấp hơn bản tối thiểu thì chặn toàn màn hình tới khi cập nhật, nút "Tải bản mới" mở đường dẫn. Không kết nối được máy chủ thì **không chặn**. Khi phát hành bản mới: sửa `version` trong `app/pubspec.yaml` và `AppConfig.appVersionName/appBuild` trong `app/lib/core/config.dart` cho khớp, rồi đặt phiên bản mới nhất trong Cài đặt.

## 9e. Thông báo đẩy iOS

**Thiết kế.** Tin nhắn bạn bè mã hoá 2 đầu và **không lưu trên máy chủ** (xem `MA_HOA_2_DAU.md`); cuộc gọi báo qua cùng WebSocket. Trước đây iPhone đóng app thì không nhận được gì. Bây giờ khi người nhận **đang offline**, `routes/api/ws/calls.dart` gọi `notifyOfflineRecipient` (`backend/lib/src/push_notify.dart`) để gửi một push APNs tới các iPhone của họ:

- tin nhắn: tiêu đề `<tên người gửi>`, nội dung "Đang nhắn tin cho bạn. Mở MAMBA để nhận."
- cuộc gọi (lời mời gọi tới người offline): tiêu đề "Cuộc gọi đến", nội dung "<tên người gửi> đang gọi bạn".
- Tối đa **1 push / (người gửi, người nhận, loại) / 60 giây** (bộ nhớ trong). Không đổi giao thức WebSocket và không đổi phản hồi người gửi nhận được.

Code: `backend/lib/src/apns.dart` (`PushSender`, `ApnsSender`: HTTP/2 tới `api.push.apple.com`, hoặc `api.sandbox.push.apple.com` khi `XOSO_APNS_SANDBOX=true`; JWT ES256 ký bằng khoá .p8, cache ~50 phút; gặp 410 / `BadDeviceToken` / `Unregistered` thì xoá token), `push_tokens.dart`, route `POST/DELETE /api/me/push-token` (chỉ khách hàng, Admin nhận 403; bảng `push_tokens`, một token thuộc đúng một tài khoản, đăng ký lại cho tài khoản khác thì chuyển sang tài khoản đó, xoá tài khoản thì xoá token). Gói thêm: `http2` (backend). Không đặt biến môi trường nào thì bộ gửi **không làm gì** (ghi một dòng log lúc đầu) và mọi thứ khác chạy như cũ.

**Quy tắc riêng tư.** Payload và log chỉ có tên hiển thị của người gửi, loại (`message`/`call`) và id người gửi (để mở đúng cuộc trò chuyện). **Không bao giờ** có nội dung tin, khoá, tên tệp. Payload: `{"aps":{"alert":{title,body},"sound":"default","thread-id":<id người gửi>},"friendId":..,"kind":..}`; cuộc gọi hết hạn sau 30 giây, tin nhắn sau 1 giờ, cả hai `apns-priority: 10`.

**Tin nhắn vẫn có thể mất.** Push chỉ **đánh thức** người nhận. Tin vẫn không được lưu: người gửi thấy "chưa gửi được" và bấm **"Gửi lại"** sau khi người nhận mở app. Cuộc gọi chuông qua push không có (chỉ là thông báo; mở app thì cuộc gọi đã kết thúc và hiện là cuộc gọi nhỡ).

**App.** `app/ios/Runner/Runner.entitlements` (`aps-environment`), `UIBackgroundModes: remote-notification` trong `Info.plist`, `AppDelegate.swift` đăng ký APNs và nói chuyện với Dart qua MethodChannel `vn.mamba/push`; `app/lib/features/friends/push_registrar.dart` xin quyền thông báo (có hộp thoại giải thích), gửi token lên máy chủ sau khi khách hàng đăng nhập (và khi token đổi), xoá token khi đăng xuất (trước khi xoá phiên, qua `AuthStore.logout`), bấm vào thông báo thì mở `/friends/chat/<id>` (cuộc gọi cũng mở cuộc trò chuyện). Đang mở app và đã thấy cùng thông tin trong app thì không hiện banner hệ điều hành. Phiên bị thu hồi từ nơi khác thì token cũ còn trên máy chủ tới khi APNs báo hỏng hoặc có tài khoản khác đăng ký lại thiết bị đó.

**Cách bật (người vận hành).**
1. Apple Developer > Certificates, Identifiers & Profiles > **Keys** > dấu **+** > đặt tên, tick **Apple Push Notifications service (APNs)** > Continue > Register > **tải file `AuthKey_<KeyID>.p8` (chỉ tải được một lần)**. Ghi lại **Key ID** (10 ký tự) và **Team ID** (`MKG3V4B3M7`). Identifier `vn.mamba.mambaApp` phải bật capability **Push Notifications** (Xcode tự bật khi mở project và đăng nhập đúng team).
2. Chép file .p8 vào container 501, ngoài thư mục web, quyền chặt: ví dụ `pct push 501 AuthKey_XXXX.p8 /etc/xs-maxmin/apns/AuthKey.p8` rồi `chmod 700 /etc/xs-maxmin/apns; chmod 600 /etc/xs-maxmin/apns/AuthKey.p8; chown` cho user chạy service.
3. Tạo drop-in như `XOSO_JWT_SECRET` ở mục 7, ví dụ `/etc/systemd/system/xs-maxmin-backend.service.d/apns.conf` (chmod 600):
```
[Service]
Environment=XOSO_APNS_KEY_PATH=/etc/xs-maxmin/apns/AuthKey.p8
Environment=XOSO_APNS_KEY_ID=<KeyID>
Environment=XOSO_APNS_TEAM_ID=MKG3V4B3M7
Environment=XOSO_APNS_TOPIC=vn.mamba.mambaApp
Environment=XOSO_APNS_SANDBOX=false
```
4. `systemctl daemon-reload && systemctl restart xs-maxmin-backend` (**khởi động lại ⇒ mọi người bị đăng xuất một lần** nếu chưa đặt `XOSO_JWT_SECRET`). Kiểm tra log không còn dòng "[apns] not configured".
5. Môi trường: bản build ký bằng **Development** (chạy từ Xcode / `flutter run` trên máy) dùng **sandbox** ⇒ `XOSO_APNS_SANDBOX=true`, entitlements `development` (mặc định trong repo). Bản **TestFlight / App Store** dùng **production** ⇒ `XOSO_APNS_SANDBOX=false`; khi Archive với Distribution profile Xcode tự đổi `aps-environment` thành `production` (nếu ký thủ công thì đổi tay trong `Runner.entitlements`). Token sandbox và production là hai thế giới khác nhau: một máy chủ chỉ phục vụ được một loại tại một thời điểm.

| Biến | Ý nghĩa |
|---|---|
| `XOSO_APNS_KEY_PATH` | đường dẫn file .p8 |
| `XOSO_APNS_KEY_ID` | Key ID của khoá |
| `XOSO_APNS_TEAM_ID` | Team ID (`MKG3V4B3M7`) |
| `XOSO_APNS_TOPIC` | bundle id, mặc định `vn.mamba.mambaApp` |
| `XOSO_APNS_SANDBOX` | `true` = máy chủ sandbox của Apple |

**Chưa kiểm chứng được** (không có tài khoản Apple khi làm): gửi thật tới APNs, nhận push trên iPhone, quyền thông báo, bấm thông báo khi khởi động nguội, kết nối HTTP/2 thật (`Http2ApnsTransport`). Các phần còn lại có unit test (`backend/test/push_*_test.dart`, `app/test/push_registrar_test.dart`) với bộ gửi/đường truyền giả. Server build cần tải được gói `http2` từ pub.dev (xem lưu ý `.dart_tool` ở mục 7).

## 9f. Thông báo đẩy Android (FCM)

**Thiết kế.** Giống hệt iOS (mục 9e) nhưng đi qua Firebase Cloud Messaging (HTTP v1). Khi người nhận **đang offline**, `notifyOfflineRecipient` gửi tới **mọi** token của họ (iPhone qua APNs, Android qua FCM; bộ giới hạn 60 giây tính **một lần cho mỗi (người gửi, người nhận, loại)**, không tính riêng từng nền tảng). Bảng `push_tokens` nay cho `platform` là `'ios'` hoặc `'android'` (bảng chưa deploy ở đâu nên đã sửa thẳng định nghĩa; `ensurePushTokensTable` trong `push_tokens.dart` tự dựng lại bảng và chép dữ liệu nếu DB dev còn bản chỉ-iOS). Token Android là chuỗi FCM 100..400 ký tự gồm chữ, số, `-`, `_`, `:` (**phân biệt hoa thường**, không bị đổi sang chữ thường như token iOS). `POST/DELETE /api/me/push-token` dùng chung cho cả hai (`{platform:'ios'|'android', token, deviceLabel?}`).

Code máy chủ: `backend/lib/src/fcm.dart` (`FcmConfig`, `FcmSender`, đường truyền HTTP tiêm được như APNs), `push_message.dart` (`PushMessage`, `PushSender`, `CompositePushSender`), `apns.dart` (ghép các bộ gửi theo cấu hình). `FcmSender` ký JWT RS256 (`iss`=`client_email`, `scope`=`https://www.googleapis.com/auth/firebase.messaging`, `aud`=`token_uri`, hiệu lực 1 giờ) bằng khoá trong file service account, đổi lấy access token OAuth2 (`urn:ietf:params:oauth:grant-type:jwt-bearer`), lưu cache tới khi còn ~5 phút, rồi `POST https://fcm.googleapis.com/v1/projects/<project_id>/messages:send` với `Authorization: Bearer ...`. Lỗi 404 / `UNREGISTERED` / `INVALID_ARGUMENT` do token sai thì **xoá token đó**. Dùng `dart:io HttpClient`, không thêm gói backend nào.

**Quy tắc riêng tư (như iOS).** Thông điệp chỉ có tên hiển thị người gửi, loại và id người gửi; **không bao giờ** có nội dung tin, khoá, tên tệp, kể cả trong log. Dạng thông điệp: `notification:{title,body}` (khối thông báo hệ thống, nên Android tự hiện khi app đã đóng, không cần mã Dart), `data:{friendId,kind}`, `android:{priority:HIGH, ttl:"30s" (cuộc gọi) | "3600s" (tin nhắn), notification:{channel_id:"mamba_calls" | "mamba_messages", sound:"default"}}`.

**Tin nhắn vẫn có thể mất** (cùng ngữ nghĩa như iOS): push chỉ đánh thức người nhận; tin không được lưu, người gửi thấy "chưa gửi được" và bấm "Gửi lại". Cuộc gọi qua push chỉ là thông báo (mở app thì cuộc gọi đã kết thúc, hiện là cuộc gọi nhỡ). Lựa chọn **"Giữ kết nối"** (dịch vụ nền, mục 9c) vẫn còn như phương án thay thế/bổ sung: khi app còn kết nối WebSocket thì máy chủ coi là online và không gửi push.

**App.** `push_registrar.dart` dùng chung cho iOS và Android; Android dùng `fcm_push_port.dart` (`firebase_core`, `firebase_messaging`): `Firebase.initializeApp()` (**lỗi khi build thiếu `google-services.json` ⇒ bỏ qua âm thầm, không xin quyền, không gọi máy chủ**), xin `POST_NOTIFICATIONS` (Android 13+, qua hộp thoại giải thích có sẵn; bỏ qua hộp thoại nếu đã được cấp), lấy token, `POST /me/push-token {platform:'android'}` sau khi **khách hàng** đăng nhập và khi `onTokenRefresh`, `DELETE` trước khi đăng xuất (`auth.beforeLogout`). Bấm thông báo: `getInitialMessage()` (khởi động nguội) và `onMessageOpenedApp` ⇒ `/friends/chat/<friendId>` (cuộc gọi cũng mở cuộc trò chuyện). Đang mở app thì **không** hiện banner FCM (không nghe `onMessage`; app có socket, banner và chuông riêng). Kênh thông báo `mamba_messages` và `mamba_calls` (chuông điện thoại) được tạo lúc khởi động trong `notifications.dart` để thông báo do hệ điều hành vẽ dùng đúng kênh (lưu ý: `mamba_messages` đã tồn tại từ trước với độ ưu tiên cao nên giữ nguyên). Gradle: plugin `com.google.gms.google-services` chỉ được áp dụng **nếu có** `app/android/app/google-services.json` (`settings.gradle.kts` khai báo `apply false`, `app/build.gradle.kts` áp dụng có điều kiện), nên build chạy được cả khi có lẫn không có file. Trong `android/build.gradle.kts` có thêm một đoạn nhỏ cho plugin `screen_protector` (bật Kotlin cho riêng nó, vì dự án đang tắt `android.builtInKotlin`), nếu không build APK lỗi `cannot find symbol ScreenProtectorPlugin`.

**Trạng thái (13/10/2026): ĐÃ CẤU HÌNH.** Dự án Firebase `MAMBA` (ID `mamba-99e37`, tài khoản Google của chủ dự án) có app Android `vn.mamba.mamba_app`; máy chủ có `/etc/xs-maxmin/fcm/service-account.json` (quyền 600) và drop-in `fcm.conf` (`XOSO_FCM_CREDENTIALS_PATH`, `XOSO_FCM_PROJECT_ID`). Đã kiểm tra: khoá đổi được token OAuth và FCM nhận yêu cầu (từ chối token giả đúng như mong đợi). **Chưa thử gửi thật tới điện thoại**: cần cài APK **1.4.4 (10) trở lên** (có `google-services.json`; file này không nằm trong git, chép vào `app/android/app/` mỗi lần build). Các APK trước đó không có push. Mỗi lần tạo khoá mới ở Firebase là thêm một khoá hợp lệ; chỉ giữ khoá đang dùng.

**Cách bật (người vận hành).**
1. Vào https://console.firebase.google.com > **Add project** (tạo dự án Firebase, ví dụ "MAMBA"; Google Analytics có thể tắt).
2. Trong dự án: **Add app > Android**, **Android package name = `vn.mamba.mamba_app`** (đúng chữ, không đổi), bỏ trống SHA-1, Register.
3. **Tải `google-services.json`** và đặt vào `app/android/app/google-services.json`. Đây là cấu hình phía **client** (không phải khoá bí mật như service account; API key trong đó nằm sẵn trong mọi APK), nên có thể commit; nếu không muốn commit thì cứ để ngoài git và chép vào mỗi lần build. **Không có file này app vẫn build và chạy bình thường, chỉ là không có push Android.** Bỏ qua các bước "Add Firebase SDK" của console (đã làm trong repo).
4. Firebase console > **Project settings > Service accounts > Generate new private key** ⇒ tải file JSON. **Đây là bí mật**: không commit, không dán vào chat/ticket. Chép lên máy chủ, ngoài thư mục web, quyền chặt: ví dụ `pct push 501 firebase-sa.json /etc/xs-maxmin/fcm/service-account.json` rồi `chmod 700 /etc/xs-maxmin/fcm; chmod 600 /etc/xs-maxmin/fcm/service-account.json; chown` cho user chạy service. Xoá bản trên máy cá nhân.
5. Tạo drop-in như `XOSO_JWT_SECRET` ở mục 7, ví dụ `/etc/systemd/system/xs-maxmin-backend.service.d/fcm.conf` (chmod 600):
```
[Service]
Environment=XOSO_FCM_CREDENTIALS_PATH=/etc/xs-maxmin/fcm/service-account.json
Environment=XOSO_FCM_PROJECT_ID=<project id Firebase>
```
`XOSO_FCM_PROJECT_ID` có thể bỏ (mặc định lấy `project_id` trong file JSON).
6. `systemctl daemon-reload && systemctl restart xs-maxmin-backend` (**khởi động lại ⇒ mọi người bị đăng xuất một lần** nếu chưa đặt `XOSO_JWT_SECRET`). Kiểm tra log không còn dòng "[push] not configured" (dòng này xuất hiện khi cả APNs lẫn FCM đều chưa cấu hình; thiếu/hỏng file FCM thì FCM bị bỏ qua âm thầm).
7. **Dựng lại APK với file `google-services.json` đã có** (`cd app && flutter build apk --release`) và cài lại. Các bản APK cũ không có push.
8. Thử: đăng nhập khách hàng A trên điện thoại Android (chấp nhận hộp thoại thông báo), kiểm tra bảng `push_tokens` có một dòng `android` (`sqlite3 data/xoso.db "select platform,device_label,substr(token,1,12) from push_tokens"`). Vuốt tắt hẳn app (hoặc khoá máy), từ tài khoản B nhắn tin/gọi cho A ⇒ A thấy thông báo trong vài giây; bấm vào mở đúng cuộc trò chuyện. Đăng xuất A rồi gửi lại ⇒ không có thông báo. Chạy thử sau khi cài mới: nếu thông báo không hiện, kiểm tra Cài đặt > Ứng dụng > MAMBA > Thông báo (kênh `mamba_messages` / `mamba_calls`) và tối ưu pin của hãng máy.

| Biến | Ý nghĩa |
|---|---|
| `XOSO_FCM_CREDENTIALS_PATH` | đường dẫn file JSON service account (bắt buộc để bật FCM) |
| `XOSO_FCM_PROJECT_ID` | tuỳ chọn, mặc định `project_id` trong file JSON |

**Chưa kiểm chứng được** (không có tài khoản Firebase khi làm, và không được liên lạc Google): gửi thật tới FCM và đổi token OAuth thật, nhận push trên máy Android thật, hành vi kênh thông báo/chuông cuộc gọi trên máy thật, plugin google-services với file thật (chỉ thử với file giả: plugin áp dụng và build qua, sau đó đã xoá), bấm thông báo khi khởi động nguội, và `firebase_messaging` cùng AppDelegate APNs tự viết trên iOS (build iOS vẫn qua; app iOS không khởi tạo Firebase). Phần còn lại có unit test (`backend/test/push_fcm_test.dart`, `push_token_test.dart`, `app/test/fcm_push_test.dart`) với đường truyền/FCM giả; khoá RSA trong test là khoá sinh riêng cho test, không phải khoá Google.

## 9g. Nhật ký đợt 11–13/10/2026 (app, offline, kết quả theo tài khoản)

**Đã deploy lên máy chủ thật** (web + backend) lần cuối **16/10/2026 đến commit `badcb98`** (bản sao lưu `backend.bak-20261016-101552`, `web.bak-20261016-101552`, DB `/root/xoso-live-20261016-101552.db`; gồm cả mục 9h: Bạn bè/tin nhắn, đối chiếu giải mã, báo cáo kết quả, Nhập kết quả cùng form + thêm ô/đài, bàn phím ẩn). Lần deploy trước: 16/10/2026 đến commit `45e1c97` (bản sao lưu `backend.bak-20261016-101352`, `web.bak-20261016-101352`, DB `/root/xoso-live-20261016-101352.db`): có bảng cấu hình tính điểm (nhóm, giá tiền/giá trúng, lấy số, thêm/sửa/xoá), tab Cấu hình tính điểm, giao diện trắng xanh và cột `customers.home_region`. Bản deploy lần đó build từ checkout sạch của commit nên chưa gồm phần Bạn bè/giải mã/Nhập kết quả (đã lên ở lần `badcb98`). Cách làm: `git archive HEAD` ra thư mục tạm, chép `backend/pubspec.lock` (không nằm trong git) vào đó rồi đóng gói web + backend như mục 7. App hiện hành trong code: **1.4.6 (12)** (chưa build APK/iPhone). Lần deploy trước: 12/10/2026 (web được deploy lại 13/10 kèm sửa `screenshotGuard.js`, và hiện khớp commit `a0c43b3` gồm thẻ Phiên bản ứng dụng) (bản sao lưu `backend.bak-20261012-095507`, DB `/root/xoso-live-20261012-095507.db`). App hiện hành: **1.4.5 (11)** (1.4.3: hỏi trước khi ghi đè Điểm ra + Hoàn tác; 1.4.4: kèm cấu hình Firebase; 1.4.5: thẻ Phiên bản ứng dụng ở Tài khoản và menu Admin). Kết quả theo tài khoản và lưu-trên-máy-trước có từ 1.4.2 (8). Phiên bản app phải khớp ở hai chỗ: `app/pubspec.yaml` và `app/lib/core/config.dart`.

- **Kết quả xổ số theo từng tài khoản** (`d94382a`): trước đây bảng `lottery_results` dùng chung cho mọi tài khoản. Nay có cột `user_id`, duy nhất theo (tài khoản, ngày, đài); GET/POST/DELETE `/lottery-results` chỉ tác động lên tài khoản đang đăng nhập; xoá dữ liệu tài khoản cũng xoá kết quả. "Tài khoản khách hàng" khác "khách hàng trong tài khoản": kết quả thuộc tài khoản và áp cho mọi khách trong đó. Nâng cấp một chiều: bảng cũ giữ nguyên tên `lottery_results_shared_legacy`, các dòng dùng chung được sao cho **mọi tài khoản khách hàng** (kể cả 91 kết quả ảo của dữ liệu thử, Admin có thể xoá từng ngày).
- **App lưu kết quả trên máy trước** (`65fbc0d`): Lưu kết quả ghi vào máy, rồi gửi; mất mạng thì báo đang offline và tự gửi khi có mạng (mỗi lần mở một ngày ở Nhập kết quả, hoặc khi Nhập số tự đồng bộ). Tính điểm dùng luôn kết quả trên máy. Điểm ra tự lưu đi qua hàng chờ offline của Nhập số. Xoá kết quả vẫn cần mạng, trừ khi kết quả đó chưa từng gửi. Code: `OfflineStore.saveResult/lotteryResult/dayResults/_flushResults`.
- **Tính điểm và Nhập kết quả chạy offline** (`3b33f14`, `544c0f8`): số liệu, khách hàng, tỉ lệ ăn, kết quả từng ngày đã xem được lưu trên máy theo tài khoản; offline hiện thanh "Đang offline: …"; ngày chưa từng mở khi có mạng thì chưa có kết quả và không bị ghi nhớ nhầm là "không có kết quả". Mở app lần đầu khi offline và chưa lưu gì thì báo rõ.
- **Sửa đọc ảnh Miền Nam thiếu số** (web `lotteryColumns.js` + app `lottery_columns.dart`): một dấu "/" lẻ làm đường cắt ngày tiêu đề bị đẩy cao; nay chỉ lấy từ ngày thật đầu tiên ở 35% trên của ảnh, và cột đủ 18 số được gán theo vị trí giải.
- **Nhập số (web)**: một ô "nhập nhanh" tự giãn dài dùng cho cả dán tin nhắn lẫn ảnh (Chọn ảnh / Dán ảnh / kéo thả, xem lại ảnh đã gửi), có thông báo sau khi thêm. **Nhập kết quả**: thông báo không nhảy giữa Miền Bắc/Trung/Nam. **Hỗ trợ chat**: tin cũ ở trên, mới ở dưới (cả khách lẫn Admin). **Hộp thoại**: nút ← và ✕ đồng bộ (`ModalDialog` có `back` và `closeButton`). Cài đặt Admin chỉ hiển thị, bấm Sửa mới chỉnh.
- **App Android + iOS** (một app, giao diện theo vai trò): đã có khu Admin, nhắn tin/gọi toàn app, thông báo đẩy (APNs, FCM), quản lý phiên bản (mục 9d), nút Đăng xuất ở Tài khoản khách và Admin, hiện "Phiên bản x (n)". Android chặn chụp bằng FLAG_SECURE; iOS bằng `screen_protector`. Chi tiết xem mục 9c–9f.
- **Phát hiện chụp màn hình để báo bạn chat** (kiểm tra 13/10): bên nhận (web và app) đã hiển thị thông báo; chỗ yếu là bên chụp. **Web**: bắt phím Cmd+Shift+3/4/5, PrintScreen, Win+Shift+S; **đã sửa** để vẫn báo khi Admin tắt chế độ che màn hình (`screenshotGuard.js`, commit `2dc11a7`, đã deploy web). **Android**: khi FLAG_SECURE bật (bản phát hành) hệ thống chặn chụp trước khi app nhận được tín hiệu `ScreenCaptureCallback` (thử trên giả lập Android 17: tắt FLAG_SECURE thì callback chạy, bật thì không), và Android dưới 14 không có tín hiệu này ⇒ **không báo được khi đang chặn chụp**; cần chọn giữa "chặn chụp" và "cho chụp + báo" ở màn chat (chờ quyết định). **iOS**: theo thiết kế chạy được, chưa thử trên máy thật.
- **Việc còn mở**: đồng bộ dữ liệu ảo lên bản live (đã dừng vì quyền ghi vào máy chủ; chưa làm); dọn 91 kết quả ảo sau nâng cấp ở trên; cấu hình khoá APNs/Firebase thật (mục 9e, 9f); "méo giọng" không làm được với flutter_webrtc; iOS simulator không build được (ML Kit thiếu arm64 simulator) nên thử trên iPhone thật; chưa kiểm tra tay trên máy thật: thông báo đẩy, cuộc gọi, chặn chụp iOS, đồng bộ kết quả offline.

## 9h. Nhật ký 16/10/2026: luồng tin nhắn theo tài liệu khách (đã commit `377bb8f`, `badcb98` và deploy; các dòng ghi "chỉ local, chưa commit/deploy" bên dưới đã cũ, nay đã lên máy chủ thật)

Theo ba tài liệu khách mới thêm (giao diện kiểu Telegram: danh sách chat, khung chat, chọn tin, giải mã, chọn đài, kết quả). **Bạn bè và tin nhắn là một chức năng**: yêu cầu mới được áp thẳng vào trang Bạn bè, không có trang riêng.

- **Giao diện trang Bạn bè** (`frontend/src/views/FriendsView.vue`): sáng cố định (nền trắng, viền xanh mảnh, chữ đen, phụ xám nhạt, không xanh dương/gradient), ghi đè biến màu ngay trong trang nên các trang khác không đổi. Hàng đầu `Sửa | Tìm kiếm | Thêm` (Sửa mới hiện nút Xoá). Avatar tròn. Đầu khung chat: Quay lại, avatar, tên, ⚙ (cùng cỡ icon gọi), gọi. ⚙ mở hộp: Tên hiển thị riêng (lưu trong `localStorage` khoá `chat-prefs:<id>`, chỉ trên máy này), Mã bảo mật, Cài đặt tự xoá, Tắt tự xoá. Nút "Nhập số liệu" cạnh ô nhập tin bật hộp chọn tin; chọn từ 1 tin thì thành "Tính toán" (hiện mới chỉ báo, chưa mở màn hình giải mã).
- **Bảng màu toàn web theo trang chat** (16/10, chỉ local, chưa commit/deploy): `frontend/src/styles/tokens.css` đổi sang nền trắng, chữ đen, viền xanh lá mảnh `#d9e8dd`, nút và viền ô nhập `#16a34a`, bỏ tím và đổ bóng; chế độ tối vẫn còn nhưng dùng xanh lá thay tím. Mọi trang dùng token nên không sửa từng trang. `surface` để `#f6faf7` (xanh rất nhạt) thay vì trắng hẳn để hover và tiêu đề bảng còn thấy. App Flutter chưa đổi màu.
- **Cấu hình tính điểm là một tab riêng** (16/10, chỉ local, chưa commit/deploy): mục menu "Cấu hình tính điểm" (route `/scoring-settings`, `ScoringSettingsView.vue`) hiện cấu hình mặc định của tài khoản thành một trang; nút "Cấu hình tính điểm mặc định" ở Khách hàng vẫn mở hộp cùng nội dung, cấu hình riêng từng khách vẫn ở nút trong danh sách.
- ~~Cấu hình tính điểm của từng khách gọn lại~~ (bản ẩn bớt trường, đã được thay bằng bảng cấu hình bên dưới: cả cấu hình mặc định lẫn từng khách đều là bảng Kiểu đánh / Ký hiệu / Giá tiền / Giá trúng, không còn so khớp, tính theo hay chọn giải).
- **Menu tin nhắn và đối chiếu giải mã** (16/10, web, chỉ local, chưa commit/deploy): nhấn giữ (điện thoại) hoặc chuột phải một tin: **Trả lời** (gửi kèm dòng trích `↪ …`, không đổi định dạng gói tin nên app/bản cũ vẫn đọc được), **Sao chép**, **Ghim** (ghim lưu trên máy trong IndexedDB `meta` khoá `pin:<bạn>`, hiện thanh 📌 trên đầu), **Chuyển tiếp** (chọn bạn, gửi lại chữ + ảnh), **Xoá** (chỉ trên máy này), **Chọn** (bật ô tích). Chọn tin rồi nút **Nhập số liệu** thành **Tính toán** → màn **Đối chiếu** (`components/ChatDecodeDialog.vue`): tin gốc bên trái (chỉ đọc), giải mã bên phải sửa từng dòng, Khôi phục từng dòng, Giải mã lại, **Lưu bản sửa** (khoá `decode:<id>`, tin gốc không đổi), **Dùng cho Nhập số** (chuyển sang trang Nhập số qua `sessionStorage['entries-prefill']`, điền vào ô nhập nhanh, chọn khách rồi bấm Phân tích). Giải mã dùng loại đánh và ký hiệu của tài khoản (`decodeMessage` + `kindSymbolsFor`, miền Bắc); chưa tính điểm đầu/3-4 càng/xiên và công thức kết quả (chờ chủ dự án chốt). Mới thử bằng tay một tin trong một cuộc trò chuyện; chưa thử nhấn giữ trên điện thoại thật.
- **Chọn đài/ngày khi đối chiếu và sửa lỗi tải lại khung chat** (16/10, web, chỉ local, chưa commit/deploy): màn Đối chiếu có ô **Ngày** và **Đài** (Miền Bắc, cả vùng, hoặc một đài trong các đài quay hôm đó theo lịch `stationsOn`); ngày có từ hai đài trở lên thì hiện gợi ý "chọn một đài hoặc cả vùng". "Dùng cho Nhập số" mang cả ngày và đài sang Nhập số (`sessionStorage['entries-prefill']` dạng JSON `{text, date, station}`), đài chọn ở chat không bị đài mặc định của khách ghi đè và nội dung được phân tích sẵn. Cùng đợt sửa một lỗi có từ trước: tải lại trang đúng địa chỉ `/friends/<id>` thì khung chat trống vì đọc tin trước khi kho cục bộ mở xong; nay đọc lại khi `chat.ready`. **Chưa làm: "tự lấy kết quả thực tế của đài"** (cần chốt nguồn dữ liệu kết quả xổ số và máy chủ có ra Internet không). Các mục còn lại của tài liệu (phân tích cú pháp, ký hiệu theo khách, lưu kết quả theo đài và ngày, cấu trúc giải theo miền và lịch quay) đã có.
- **Chọn đài → Kết quả tính toán → Lưu / Copy / Gửi** (16/10, web, chỉ local, chưa commit/deploy; tài liệu "Mô tả từ màn hình tin nhắn đến màn hình kết quả"): ở màn Đối chiếu bấm **Tính toán** (tự lưu bản sửa) → `components/ChatCalcDialog.vue`. **Chọn đài**: mỗi đài quay trong ngày là một thẻ lớn "Dùng kết quả đài X" (tài liệu chỉ nêu Quảng Nam/Khánh Hòa, nay lấy theo lịch quay của ngày), không tự chọn, chọn lại thì bỏ đài cũ, có ô chọn cấu hình giá (mặc định tài khoản hoặc một khách). **Xác nhận chọn đài** → lấy kết quả ĐÚNG đài + ngày của tài khoản (`GET /lottery-results`); chưa có thì báo và cho Thử lại, không dùng số mẫu hay đài khác, tiền trúng và lợi nhuận hiện "Chưa đủ dữ liệu". **8 mục** (`src/chatReport.js`, test `tests/chatReport.test.mjs`): lô, đầu đuôi, 3 càng, xiên 2, xiên 3 (mỗi mục: điểm đánh × giá, điểm trúng → tiền, còn lại), tổng tiền khách đánh, tổng tiền khách trúng, tổng lợi nhuận = đánh − trúng (âm hiện rõ). Kiểu đánh khác (vd. 4 càng, trượt, tài/xỉu) vẫn cộng vào 3 tổng cuối và liệt kê riêng; dòng còn nghi ngờ (`uncertain`) KHÔNG được tính và được nêu tên. **Lưu**: trên máy này (`meta` khoá `report:<id>` + `reports:index`), id theo nội dung nên lưu lại không tạo bản trùng, mở lại ở "Báo cáo đã lưu". **Copy**: đúng nội dung báo cáo (BÁO CÁO KẾT QUẢ, đài, ngày, 5 mục, 3 tổng). **Gửi cho khách hàng**: chọn người nhận, xem trước, gửi đúng nội dung đã tính qua chat mã hoá; báo thành công/thất bại theo trạng thái tin thật. Đã thử bằng tay: chưa có kết quả thì báo thiếu; có kết quả thì ra 8 mục; lưu 2 lần chỉ ra 1 bản; xem trước và gửi (bạn offline nên báo chưa gửi được). **Chưa thử**: nút Copy trong trình duyệt thật (khung thử chặn clipboard), điện thoại thật. **Còn chờ chốt**: công thức "(điểm − điểm trúng) × giá" trong ví dụ của tài liệu (đang hiển thị đánh và trúng riêng, rồi lợi nhuận = đánh − trúng như mục 8), cách tính xiên 3 / 3 càng khi tài liệu chưa nêu hệ số, tài/xỉu và chẵn/lẻ chưa có mục riêng trong 8 mục. Báo cáo lưu trên máy, chưa có bảng trên máy chủ.
- **Luồng nối liền tin nhắn → đối chiếu → Nhập số → Tính điểm** (16/10, web, chỉ local, chưa commit/deploy): sau "Dùng cho Nhập số" và bấm "Xác nhận và lưu" (lưu hết, không dòng nào lỗi) trang tự chuyển sang **Tính điểm** (`/scoring?customer=&date=&added=`): mở sẵn đúng khách và đúng ngày vừa nhập, hiện thông báo "Đã thêm N số liệu cho X ngày D", rồi bỏ tham số khỏi địa chỉ. Chỉ áp cho số liệu đến từ khung chat (cờ `fromChat` trong `EntriesView.vue`); nhập tay bình thường không bị chuyển trang. Đã thử trên bản local: số liệu ABC 16/10 ra Tiền khách gửi 13.800.000đ, Tiền khách trúng 230.000.000đ, còn lại −216.200.000đ, trùng với màn Kết quả tính toán trong chat (cùng cấu hình cũ). Lỗi gặp khi thử: backend dev cũ trả 500 cho mọi lần thêm số liệu, hết sau khi khởi động lại; không phải lỗi mã.
- **Bắt buộc chọn khách cho số liệu; ẩn thanh dưới cùng trên web** (16/10, web, chỉ local, chưa commit/deploy): màn Đối chiếu có ô **"Khách hàng của số liệu này *"** (khách trong tài khoản); chưa chọn thì "Dùng cho Nhập số" và "Tính toán" không đi tiếp và báo "Hãy chọn khách hàng cho số liệu đã nhập". Khách đã chọn được mang sang Nhập số (chọn sẵn khách đó) và sang màn Chọn đài / Kết quả tính toán (tính theo cấu hình giá của khách; ô chọn cấu hình giá riêng đã bỏ). Thanh Danh bạ | Cuộc gọi | Tin nhắn | Cài đặt **ẩn trên web** bằng hằng `SHOW_BOTTOM_NAV = false` trong `FriendsView.vue` (code giữ nguyên, đổi `true` để hiện lại; dành cho app): danh sách bên trái hiện lại mọi bạn bè như trước, "Mới > Danh bạ mới" chỉ đưa con trỏ vào ô tìm kiếm.
- **Màn trò chuyện mở ra với bàn phím ẩn** (16/10, web, chỉ local, chưa commit/deploy): mở một cuộc trò chuyện thì ô nhập CHƯA được chọn (không con trỏ, `document.activeElement` là trang), không có bàn phím ảo của app (`kbOpen` mặc định `false`; nút ⌨ mới bật) và không tự gọi bàn phím hệ thống; nội dung tin nhắn chiếm hết chỗ giữa thanh tiêu đề và thanh nhập. Chạm vào ô nhập thì bàn phím hệ thống hiện như thường. Đã bỏ việc tự focus khi mở / đổi cuộc trò chuyện (chỉ còn focus khi bấm Trả lời hoặc bật ⌨). Cùng đợt: bong bóng tin nhắn giữ xuống dòng (`white-space: pre-wrap`) nên báo cáo kết quả gửi qua chat không còn dính thành một đoạn. Đã thử ở khung 375×812. Chưa thử trên điện thoại thật (hành vi bàn phím khi chạm vào ô nhập).
- **Đủ mọi đài ở Miền Trung / Miền Nam** (16/10, web, chỉ local, chưa commit/deploy): dãy nút đài hiện các đài QUAY trong ngày theo lịch; thêm ô chọn **"+ Đài khác (N)"** liệt kê mọi đài còn lại của miền (danh mục có 14 đài Miền Trung, 21 đài Miền Nam), chọn thì thêm một nút đài và nhập như bình thường. Đài có kết quả lưu trong ngày nhưng không nằm trong lịch tự hiện lại khi mở ngày đó (có ✓). Backend đã nhận mọi đài trong danh mục sẵn, không đổi. Đã thử tay: thêm Cà Mau vào ngày 16/10 (không nằm lịch), nhập, lưu, tải lại vẫn thấy có ✓, rồi xoá. Đọc ảnh nhiều đài vẫn chỉ tự khớp với các đài theo lịch của ngày; đài ngoài lịch phải thêm tay.
- **Thêm ô khi kết quả nhiều số hơn** (16/10, web + backend, chỉ local, chưa commit/deploy): số ô mỗi giải của miền (`structure`) nay là TỐI THIỂU, không cố định. Ở form nhập, mỗi giải dạng danh sách (từ Giải nhì trở xuống) có nút **+** thêm một ô và **−** bớt ô vừa thêm (chỉ khi đang sửa); ô thêm không bắt buộc, ô thêm bỏ trống thì bị bỏ khi lưu, số ô gốc vẫn phải nhập đủ. Đặc biệt và Giải nhất giữ 1 số. Backend `POST /lottery-results` nhận từ `count` đến `count + 20` số cho mỗi giải dạng danh sách (lỗi: "… phải có ít nhất N số (tối đa M)"). Mở lại kết quả đã lưu hiện đủ số ô. Đã thử tay: Bình Dương Giải tư 8 ô, lưu, tải lại vẫn 8 ô (khoá, không còn nút +/−), rồi xoá. Tính điểm đọc mọi số trong danh sách nên tự tính cả ô thêm. **App Flutter chưa biết ô thêm**: form app vẫn theo đúng `structure`, nên một kết quả có ô thêm mở trong app có thể hiện trống ở giải đó và lưu lại từ app sẽ làm mất ô thêm; cần sửa app khi làm tiếp.
- **Nhập kết quả: ba miền cùng cấu trúc Miền Bắc cũ** (16/10, web, chỉ local, chưa commit/deploy; `ResultsView.vue`): theo yêu cầu "giữ cấu trúc các tab giống Miền Bắc trước đó", cả ba miền dùng MỘT form dọc như Miền Bắc (từng giải một hàng, Đặc biệt trên cùng, nhãn "n ô · d số", nút "Nhập tay các giải" thu gọn, hàng nút Xoá kết quả này / Sửa / Xoá form / Lưu kết quả). Miền Trung / Miền Nam: dãy nút đài (kèm dấu ✓ khi đã lưu) phía trên, bấm đài nào thì nhập form đó cho đài ấy; "Lưu kết quả" lưu mọi đài đã nhập đủ. Khung "Đọc kết quả từ ảnh" giống nhau ở cả ba miền (ảnh nhiều đài vẫn điền đúng từng đài). Dữ liệu Miền Bắc ở `lotteryForm`, đài ở `board[st]`, các hàm `col*`/`curCol` ẩn sự khác nhau đó. Bảng nhiều cột đã bỏ khỏi giao diện (CSS `.board` còn nhưng không dùng). Đã thử tay: Miền Nam xem đúng form như Miền Bắc, nhập 18 ô cho Bình Dương, lưu (có ✓), xoá. Chưa thử đọc ảnh sau khi đổi, màn hình điện thoại; app Flutter chưa đổi.
- **Việc kế tiếp (yêu cầu 16/10): làm lại phần Bạn bè/tin nhắn trên APP Flutter** theo đúng các mục 9h bên dưới (thanh Danh bạ | Cuộc gọi | Tin nhắn | Cài đặt, Sửa chọn nhiều để Lưu trữ/Xoá, nút Mới, màn trò chuyện, bảng màu trắng + xanh lá). **Web đã đủ, chưa cần sửa thêm.** Nhóm chat thật vẫn chờ chốt yêu cầu.
- **Màn hình trò chuyện theo tài liệu** (16/10, chỉ local, chưa commit/deploy): đầu khung là nút tròn ←, avatar + tên (bấm mở hộp thông tin/cài đặt), ⚙, gọi thoại; ô nhập được chọn ngay khi mở; trên điện thoại màn trò chuyện chiếm trọn màn hình (tin nhắn cuộn ở giữa, ô nhập + bàn phím sát đáy). **Bàn phím ảo** `components/ChatKeyboard.vue`: QWERTY, Shift, Backspace, Space, ?123/ABC, ký hiệu 2 trang, Enter = Gửi, bảng emoji, 🌐 chuyển **VI/EN**, hàng dưới cùng 😊 | ?123 (rộng) | 🌐. VI gõ **Telex** (`src/vietnameseInput.js`, đặt dấu kiểu mới `hoà`, `thuý`; test `tests/vietnameseInput.test.mjs`); EN gõ thẳng. Nút ⌨ ẩn/hiện bàn phím; khi hiện, ô nhập dùng `inputmode="none"` nên bàn phím hệ thống không bật. Phím ghim 📎 dùng bộ chọn ảnh có sẵn (chỉ nhận JPG/PNG/WebP, không đổi). Bàn phím chèn/xoá ở cuối nội dung ô nhập (chưa theo con trỏ). Chưa thử trên điện thoại thật và chưa thử gửi thật (bạn kia offline).
- **Hoàn thiện Bạn bè theo tài liệu** (16/10, chỉ local, chưa commit/deploy; `FriendsView.vue`, `chat.deleteConversation` trong `e2ee/chat.js`): thanh dưới cùng **Danh bạ | Cuộc gọi | Tin nhắn | Cài đặt**. Tin nhắn = người đã có tin, mới nhất trên; **Sửa** chọn nhiều cuộc trò chuyện rồi **Lưu trữ** (ẩn, lưu trên máy theo tài khoản, khoá `chat-archive:<id>`, có mục "Đã lưu trữ" và Bỏ lưu trữ) hoặc **Xoá** (xoá nội dung cuộc trò chuyện khỏi máy này, bạn bè vẫn còn). Danh bạ = mọi bạn bè theo tên. Cuộc gọi = lịch sử gọi gần đây của mọi bạn (`GET /me/calls`). Cài đặt = lối tắt (lưu trữ, bảo mật tài khoản, ID). Nút **Mới** (trước là Thêm): Tin nhắn mới (chọn bạn), Nhóm mới (hộp có sẵn, vẫn chưa tạo được), Danh bạ mới (tìm theo tên/ID để kết bạn). "Xoá khỏi bạn bè" chuyển vào hộp ⚙ của từng cuộc trò chuyện. Chưa làm: nhóm chat thật, thử trên điện thoại, gửi tin thật giữa hai tài khoản (người kia offline nên chưa thử).
- **Bộ đọc tin nhắn** (`frontend/src/messageParser.js`): thêm cú pháp liền `20lo100 70lo500 54lo300` (lo/l/lô/x = bao lô; d/đầu = đầu; c/cuối = đuôi; số chữ số quyết định 2/3/4 càng; xiên bằng `.` hoặc `x`). Một dòng chỉ đi đường mới khi MỌI cụm đều đọc được, nếu không giữ đường cũ nên định dạng cũ không đổi. `decodeMessage` trả bản chuẩn từng dòng (chỉ đổi ký hiệu, giữ số và khoảng trắng, báo phần không nhận ra). Loại chưa có trong cấu hình hoặc xiên luôn bị đánh dấu "cần kiểm tra".
- **Chưa làm:** màn hình giải mã so sánh (bản gốc/bản giải mã, sửa, khôi phục, giải mã lại); chọn đài theo lịch trong ngày (Quảng Nam/Khánh Hòa theo ví dụ tài liệu); màn kết quả 8 mục và nút Lưu/Copy/Gửi cho khách; tính điểm đầu, 3-4 càng, xiên; nhóm chat; nút 📎 riêng (đang dùng nút ảnh có sẵn).
- **Cần chủ dự án chốt:** (1) ví dụ "70 thành 10" trong tài liệu không có quy tắc, bộ đọc hiện không đổi số; (2) công thức kết quả (mục 1–5 ra 6–8) và 70.000 tiền trả; (3) nguồn tin của khách (đang suy ra là chat mã hoá bạn bè, chưa xác nhận) và "Gửi cho khách" gửi qua đâu; (4) nhóm chat: số người tối đa, ai được thêm/xoá; (5) ví dụ chọn đài có Quảng Nam và Khánh Hòa cùng ngày nhưng lịch thật không trùng; (6) miền Trung chủ nhật có Huế.
- **Bài học:** nhớ khai báo biến trước mọi `watch(..., { immediate: true })` trong `<script setup>` (đã gây trang trắng); biến màu thật của giao diện là `--card`, `--text-primary`, `--primary`, `--border`... (không phải `--surface-2`, `--text`).

- **Bảng cấu hình tính điểm theo tài liệu khách** (16/10, chỉ local, chưa commit/deploy): cấu hình (mặc định và từng khách) là bảng **Kiểu đánh | Ký hiệu | Giá tiền/1 điểm | Giá trúng/1 điểm**, tách theo Miền Bắc/Trung/Nam (`ScoringConfigEditor.vue`, `scoringConfig.js`). Tiền xác = điểm × giá tiền; tiền trúng = số lần trúng × điểm × giá trúng; lợi nhuận = xác − trúng. Mỗi dòng lưu `{kind, price, payout}` (kèm `rate = payout/price`, `tiers`, `digits`, `unit: 'point'`, `pointValue = price` để code cũ tính cùng kết quả); cấu hình cũ (không có `kind`) vẫn tính như trước và hiện trong bảng bằng `toTableRow`. Cách xác định trúng cố định theo `kind` (`scoringSummary.js`, `tableDetail`): **lo** bao lô (2/3/4 số theo độ dài số, so mọi lô đủ dài, về nhiều lô thì nhân); **dau** Nam/Trung = giải tám, Bắc = giải nhất (khách Bắc, 1 lô = 1 điểm) hoặc 4 giải bảy với tiền xác ×4 (khách miền Nam/Trung); **duoi** = 2 số cuối giải đặc biệt; **cang3/cang4** = 3/4 số cuối **chỉ giải đặc biệt**; **xien2/3/4** = xiên thật (cả các số cùng về, chỉ tính 1 lần; xác = điểm × N × giá). "Kiểu đánh khác" (tên + ký hiệu + so với giải đặc biệt/tất cả + số cuối) dùng luật cũ. Mặc định theo tài liệu: bao lô Nam/Trung 12.600/70.000 (Bắc 21.600/70.000), đầu và đuôi 1.000/70.000, 3 càng 12.600/500.000; **4 càng (12.600/5.000.000) là giá tạm do mình đặt, xiên giá trúng để 0 = "Chưa nhập"** vì tài liệu không ghi. Thêm cột `customers.home_region` ('mb' | 'mn' | null) + PATCH `homeRegion` + ô "Khách thuộc miền nào" trong cửa sổ cấu hình khách. Backend: `scoring_rates.dart` (`kind`, `price`, `payout`, `defaultTableRates`); tài khoản chưa lưu gì nhận bảng mặc định. Bảng gom theo **nhóm = kiểu đánh, trong nhóm nhiều cách đánh** (`TABLE_GROUPS` trong `scoringConfig.js`): **Lô** (bao lô 2 / 3 / 4 số); **Đề** (đầu, đuôi, 3 càng, 4 càng); **Xiên** (2, 3, 4); **Lô trượt** (trượt xiên 4 / 8 / 10: trúng khi không số nào về, một lần, xác = điểm × N × giá); **Thần tài** (tài/xỉu: đuôi giải đặc biệt 00-49 xỉu, 50-99 tài; chẵn/lẻ: số cuối giải đặc biệt); Kiểu đánh khác. **Mỗi miền có cách lấy số riêng** (hiện dưới từng dòng bằng `kindSource`): Bắc 27 lô (bao lô 3 số = 23 lô, 4 số = 20 lô; đầu = giải nhất cho khách Bắc hoặc 4 giải bảy ×4 cho khách Nam/Trung), Nam/Trung 18 lô (3 số = 17, 4 số = 16; đầu = giải tám). Giá mặc định của bao lô 3/4 số suy ra từ 700đ/lô (Nam, Trung) và 800đ/lô (Bắc); giá trúng của mọi cách chưa có trong tài liệu để 0 = "Chưa nhập" (hiện đỏ). Giải dùng cho tài/xỉu và chẵn/lẻ là giải đặc biệt (tài liệu nói "giải đặc biệt hoặc giải tám", mình chọn đặc biệt). Xiên quay chưa có công thức. Mỗi cách đánh có tham số **"Lấy số"** chỉnh được (nút "Chỉnh lấy số" khi Sửa): **giải nào** (tick theo từng giải của miền, kèm số lô × số chữ số), **vị trí** (cuối = đuôi / đầu), **bao nhiêu số** (1-6) và **lô thứ mấy** của giải (trống = mọi lô). Lưu trong `source` của dòng ({tiers, position, digits, pick}; chỉ lưu khi khác mặc định, dòng tuỳ chỉnh luôn lưu), engine `sourceNumbers`/`tableDetail` đọc số theo đó; `dau` ở đài Bắc với khách Nam/Trung chỉ tự dùng 4 giải bảy ×4 khi chưa chỉnh lấy số. Thần tài chỉ chọn giải + lô thứ, xiên/trượt chỉ chọn giải (so 2 số cuối). Chế độ Sửa có đủ **thêm / sửa / xoá từng cách đánh**: mỗi nhóm có "+ Thêm cách đánh" (khôi phục một cách đã xoá hoặc tạo cách mới tự đặt tên + ký hiệu + so với giải đặc biệt/tất cả + số cuối, thuộc nhóm đó), mỗi dòng có Xoá (dòng chuẩn bị xoá được ghi `{disabled:true}` vào khoá `kind@miền` và ẩn đi, số liệu cũ vẫn tính theo mặc định; ở cấu hình riêng của khách chỉ dòng tuỳ chỉnh có Xoá, dòng chuẩn dùng công tắc Dùng). Bảng không còn cố định chiều cao, hàng nút Lưu/Huỷ dính đáy màn hình. Bảng chỉ hiển thị, bấm **Sửa** mới sửa được giá và ký hiệu (Huỷ để bỏ, Lưu xong tự về chế độ xem). Ký hiệu của bao lô/đầu/đuôi sửa được (cách nhau bằng dấu phẩy, lưu trong `symbols` của dòng) và bộ đọc tin nhắn (`parseMessage`, `kindSymbols` từ `kindSymbolsFor`) hiểu thêm các ký hiệu đó. Test: `npm test` (36), `dart test` (107), `flutter test` (347). **App Flutter đã chuyển theo** (`scoring_config.dart`, `scoring_logic.dart`, `features/customers/scoring_config_editor.dart`, `scoring_editor_model.dart`, ô "Khách thuộc miền" ở `customer_config_screen.dart`): cùng bảng, cùng chế độ xem/Sửa, cùng ký hiệu, cùng engine; chưa chạy trên máy ảo/thiết bị, chưa có test luồng Lưu với API thật, và **bộ đọc tin nhắn của app chưa có cú pháp liền** (`20lo100`, `20dau10`, xiên) nên ký hiệu tuỳ chỉnh chưa tác dụng ở app (có sẵn `kindSymbolsFor`). Chưa làm: giá trúng của xiên, ví dụ "70lo500 → 10lô500", lô trượt, tài/xỉu, chẵn/lẻ, xiên quay (chờ khách chốt).

- **Bộ khung nút chức năng** (16/10, web): `frontend/src/components/AppButton.vue` (variant primary / secondary / ghost / danger, size md / sm, icon, iconOnly + label, loading khoá nút và hiện vòng quay, block, mặc định type="button") và `ActionBar.vue` (hàng nút chuẩn: slot `start` = nút phụ/nguy hiểm bên trái, `note` = chữ nhỏ ở giữa, mặc định = Huỷ rồi nút chính ngoài cùng bên phải; `sticky` dính đáy màn hình, trên màn hẹp tự xếp dọc với nút chính ở trên). Các class `.btn ...` cũ vẫn dùng được cho nút lẻ. Đã áp dụng cho: footer bảng cấu hình tính điểm, hộp thêm khách, hộp nhập mật khẩu, hộp xoá số liệu; các màn khác chuyển dần. App Flutter có bản tương ứng (`AppButton`, `ActionBar` trong `app/lib/core/widgets/`, xem mục app).

- **Cập nhật 17/10/2026:** web đã deploy lại (chỉ web, `web.bak-20261017-014951`) đến commit `b464fa3`: bộ khung nút `AppButton`/`ActionBar` áp dụng cho 159 nút, bỏ dòng hướng dẫn ở bảng cấu hình. Backend không đổi. **App 1.4.6 (12)** (commit `455b498`): giao diện sáng xanh lá cố định, thanh dưới 5 mục (Tổng quan | Tính toán | Bạn bè | Cấu hình | Tài khoản), Hỗ trợ từ Admin, banner thông báo, ô nhập nhanh, Nhập kết quả giống web, bộ đọc ký hiệu liền, chat (nhấn giữ, ghim, trả lời, chuyển tiếp, lưu trữ), Đối chiếu giải mã, Tính toán và báo cáo từ chat, 244 nút theo bộ khung mới. APK release `MAMBA.apk` trên Desktop; iOS build qua nhưng chưa cài (iPhone không kết nối). Test: web 40, backend 107, app 429. **Chưa kiểm chứng:** gửi tin thật giữa web và app (định dạng trả lời `↪` đã đối chiếu mã), màn chat và đợt 3 trên máy thật; giá trúng của xiên/trượt/thần tài/bao lô 3-4 số chờ khách điền.

## 10. Việc cần làm ngay khi nhận bàn giao

1. ~~Đặt `XOSO_JWT_SECRET` cố định~~ — **đã làm 13/10/2026** (drop-in `jwt.conf` trên máy chủ). Hãy sao lưu giá trị này ở nơi an toàn nếu cần dựng lại máy chủ.
2. **Đổi mật khẩu mặc định:** admin `1` (mật khẩu seed `1234`) và các tài khoản demo `2`–`6` (mật khẩu seed `1235`–`1239`) – đều là mật khẩu mock trong `_seed()` của `backend/lib/src/database.dart`, chỉ dùng thử. Seed chỉ chạy khi DB trống nên tài khoản đã có trên máy chủ thật giữ mật khẩu cũ (admin vẫn có thể là `1`/`1`). Trước khi cho khách thật dùng phải đổi hết.
3. **Thu hồi token Cloudflare đã từng gửi qua chat** (ba token) và tạo token riêng cho người mới nếu cần. Khoá TURN hiện dùng nằm trong file cấu hình trên máy chủ, không nằm trong code.
4. Xác nhận quyền truy cập: SSH vào `root@10.5.100.5`, repo GitHub `trancongthangvn/xs-maxmin`, tài khoản Cloudflare chứa tunnel `xs.massagehomeriyadh.com`.
5. Dọn các thư mục sao lưu cũ trong `/opt/xs-maxmin` và các file `/root/xoso-*.db` khi đã yên tâm.

## 11. Bẫy đã gặp (đỡ mất thời gian)

- `dart_frog dev` hot-reload; nếu cổng bị chiếm thì giải phóng bằng `lsof -ti :<cổng> | xargs kill`, không `pkill -f`.
- macOS: `sed -i` cần `''`; `tar` phải có cờ lọc `._*`; không có lệnh `timeout`.
- Puppeteer: ô chọn tuỳ biến (`AppSelect`) cần click thật, không gán giá trị; script không đóng trình duyệt sẽ treo.
- Python `urllib` bị Cloudflare chặn (403) khi gọi API của họ – dùng `curl`.
- Tên người dùng `1` là admin mặc định; nhập mật khẩu xoá (`confirm-wipe`) ở bước 2 sẽ xoá dữ liệu thật – cẩn thận khi demo.
- `.gitignore` gốc bỏ qua `build/`, `web/`, `*.db`, `*.tar.gz`: đừng mong những thứ đó có trong git.
- Cloudflare tunnel của site này chạy bằng service riêng (`cloudflared-xs-massage`); tunnel cũ của `xs.maxmin.vn` đã ngắt.
