# MAMBA (XS Maxmin) – Tài liệu bàn giao dự án

> Cập nhật: 10/10/2026 · Nhánh làm việc hiện tại: `mask-short` (chứa toàn bộ công việc mới nhất) · Bản đang chạy: https://xs.massagehomeriyadh.com/
>
> **Tài liệu này không chứa mật khẩu, token hay khoá bí mật.** Các giá trị đó được bàn giao riêng (xem mục 10).

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
├─ deploy/             deploy.sh (web + backend), deploy-web.sh (chỉ web) – chạy trong container 501
├─ tools/e2e/          script kiểm thử giao diện/API bằng puppeteer (xem tools/e2e/README.md)
└─ docs/
   ├─ BAN_GIAO.md      tài liệu này
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

**Khách hàng:** đăng ký/đăng nhập 2 lớp (mật khẩu + mật khẩu lớp 2), mã khôi phục dùng một lần, khôi phục tài khoản, đổi mật khẩu, mật khẩu xoá dữ liệu, quản lý thiết bị đang đăng nhập, **nhờ Admin hỗ trợ khôi phục** (gửi yêu cầu → Admin duyệt → mã hỗ trợ một lần 24 giờ → tự đặt mật khẩu mới), nhập số (tay, OCR ảnh, dán tin nhắn; chọn đài, mặc định theo từng khách), nhập kết quả xổ số **Miền Bắc / Miền Trung / Miền Nam theo từng đài** (bảng đài theo thứ trong tuần ở `backend/lib/src/lottery_stations.dart`; kết quả lưu theo (ngày, đài); số liệu cũ không có đài tính là Miền Bắc; OCR ảnh: Miền Bắc một bảng 27 số; Miền Nam/Miền Trung hiện thành **một bảng nhiều đài như tờ kết quả in** (mỗi đài một cột, hàng từ Giải tám ở trên đến Đặc biệt ở dưới), ảnh được đọc rồi điền thẳng vào đúng cột (`frontend/src/lotteryColumns.js`, bỏ phần ngày ở dòng tiêu đề khỏi các giải), ô sai độ dài viền đỏ, một nút lưu cho tất cả cột đã nhập đủ, mỗi cột đã lưu có nút xoá riêng; có thể dán ảnh Ctrl/Cmd+V ở các khu nhập ảnh), tính điểm theo ngày, tổng kết tiền theo khách trong Tính điểm (đầu trang: ba ô tiền gửi / tiền trúng / còn lại, rồi bảng theo ngày; lọc theo miền) ((1) tiền khách gửi: số lô, điểm, quy ra đồng; (2) lô trúng; (3) còn lại = (1) − (2); mỗi loại đánh có "đánh theo điểm" kèm 1 điểm = bao nhiêu đồng, hoặc "đánh theo tiền"), cấu hình loại đánh **theo từng miền** (tab Miền Bắc/Trung/Nam; khoá `loai` = mọi miền, `loai@mb|mt|mn` = riêng một miền; nút "+ Thêm loại đánh" ở mỗi tab tạo loại **chỉ dùng cho miền đó** (khoá `loai@mien` không có `loai`, hàm `typesIn` trong `scoringConfig.js`); trong trang Khách hàng: nút Cấu hình tính điểm mặc định và, ở cột Thao tác của từng khách, nút **Cấu hình tính điểm** (cửa sổ cố định kích thước, chỉ còn đài mặc định và cấu hình) và nút **Sửa** (đổi số điện thoại)), khách hàng, **Ẩn số liệu** (che số trên Nhập số/Khách hàng/Tính điểm, hiện có thời hạn và cần mật khẩu), xoá dữ liệu theo ngày hoặc đặt lịch (một lần/lặp lại), mã ID kết bạn (tự chọn dãy số, nhiều ID ảo), bạn bè + nhắn tin + gọi thoại + huy hiệu chưa đọc, **Phản hồi cho Admin** (popover cạnh nút sáng/tối), gói dịch vụ + chuyển khoản (VietQR) + lịch sử (nằm trong Tài khoản, tab "Gói & Thanh toán"; `/packages` tự chuyển tới đó), khoá tự động.

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

Bảng: `users`, `device_sessions`, `login_attempts`, `security_events`, `data_entries`, `customers`, `customer_codes`, `retired_codes`, `customer_syntax_templates`, `lottery_results`, `friendships`, `direct_messages`, `message_reads`, `messages` (hỗ trợ Admin), `call_logs`, `deletion_schedules`, `payment_requests`, `transactions`, `settings`, `announcements`.

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

**Deploy cả backend** (**khởi động lại backend ⇒ mọi người bị đăng xuất một lần** vì chưa đặt `XOSO_JWT_SECRET` cố định):
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
| `XOSO_JWT_SECRET` | Khoá ký token (≥16 ký tự). Không đặt thì mỗi lần khởi động tạo khoá ngẫu nhiên ⇒ đăng xuất toàn bộ | **Chưa đặt trên máy chủ** (nên đặt) |
| `XOSO_CF_TURN_KEY_ID`, `XOSO_CF_TURN_API_TOKEN` | Khoá Cloudflare Realtime TURN | Đã đặt (file `turn.conf`, quyền 600) |
| `XOSO_STUN_URLS`, `XOSO_TURN_URLS`, `XOSO_TURN_SECRET` / `XOSO_TURN_USERNAME` + `XOSO_TURN_CREDENTIAL` | Phương án TURN tự dựng (coturn) thay cho Cloudflare | Không dùng |

TURN của Cloudflare: tạo khoá ở Dashboard → Realtime → TURN (hoặc API `POST /accounts/{id}/calls/turn_keys`; **mã bí mật `secret` chỉ hiện đúng một lần lúc tạo**). Kiểm tra: đăng nhập rồi gọi `GET /api/calls/ice-servers` – phải thấy `"turn": true`.

## 8. Kiểm thử

- Backend: `cd backend && dart test` (xác thực, xoá dữ liệu, lịch xoá lặp lại, mã ID, tìm kiếm không dấu, nhật ký cuộc gọi, quyền riêng tư).
- Giao diện/API: `tools/e2e/*.mjs` (puppeteer + Chrome cài trên máy). Cách dựng môi trường cô lập ở `tools/e2e/README.md`. Mỗi lần kiểm thử nên chạy backend riêng (bản sao thư mục `backend` + `XOSO_JWT_SECRET` riêng) để không đụng DB thật.
- Chưa có CI. Kiểm thử trên Android/iOS thật chưa làm (mới có web).

## 9. Tình trạng công việc

**Đã xong và đã lên máy chủ thật:** toàn bộ các mục ở mục 5 (nhánh `mask-short` đã deploy đến commit mới nhất ngày 08/10/2026).

**Chưa làm hẳn / làm một phần** (chi tiết từng mã trong `tien_do_chuc_nang.csv`):
- Chưa làm: mã hoá đầu cuối cho phản hồi Admin và dữ liệu số liệu/khách hàng (K28; chat bạn bè đã mã hoá, xem `docs/MA_HOA_2_DAU.md`), đổi giọng nói đầy đủ (K30; hiện mới có nút "Méo giọng" trong cuộc gọi), chính sách lưu trữ trên app (A08: web như hiện tại, app lưu trên máy và xoá sạch được), quản lý quyền camera/vị trí/thông báo (K39), quản lý phiên bản app (A17), tách dịch vụ (NFR-08), app Android/iOS, Face ID.
- Một phần: bảo vệ chụp màn hình (K33 – mới có Ẩn số liệu), xác thực lớp 2/mật khẩu dữ liệu riêng, mã hoá dữ liệu khi lưu (SQLite chưa mã hoá), đồng bộ/offline (đã có hàng đợi nhập số, chưa phủ hết), quản lý thanh toán (A18 đã mở rộng, chưa có đối soát tự động với ngân hàng).

**Đề xuất chống chụp màn hình** (đã trao đổi, chưa làm): web chỉ giảm rủi ro – "giữ để xem" + watermark động + nhật ký; chặn thật cần app: Android `FLAG_SECURE`, iOS phát hiện chụp/quay và che, PC (Electron) `setContentProtection`. Hướng nhanh nhất là bọc web bằng Capacitor.

**Quyết định còn mở (cần người phụ trách chốt):**
1. Kết quả xổ số (`lottery_results`) hiện dùng chung và **bất kỳ tài khoản nào cũng ghi được** – nên chuyển sang theo tài khoản hay chỉ Admin?
2. Mật khẩu lớp 2 hiện bắt buộc khi đăng ký mới (≥4 ký tự) nhưng các tài khoản tạo sẵn từ seed không có – có ép tất cả tài khoản cũ phải đặt không.
3. Kết bạn: có cần bên kia chấp nhận không (hiện thêm bằng mã ID là thành bạn ngay).
4. Tự xoá dữ liệu sau n lần nhập sai (YC4) – làm hay không.
5. Gộp PR #1 trên GitHub và đẩy các nhánh mới lên (chưa đẩy).
6. Các điểm DC01–DC04 trong bảng tiến độ (vai trò nhân viên hỗ trợ, tiêu chí nghiệm thu, ma trận kiểm thử, phạm vi pháp lý).

## 9b. Nhật ký thay đổi gần đây (10/10/2026)

Mỗi dòng là một nhóm commit (mới nhất ở trên). Các commit đến `95915dc` đã deploy lên máy chủ thật; `6cfb9b9` bật làm mờ mặc định rồi đã tắt lại (xem dòng mới nhất).

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

## 10. Việc cần làm ngay khi nhận bàn giao

1. **Đặt `XOSO_JWT_SECRET` cố định** trên máy chủ (drop-in như mục 7) để các lần deploy sau không đăng xuất mọi người.
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
