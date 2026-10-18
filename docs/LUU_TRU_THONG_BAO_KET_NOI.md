# MAMBA – Lưu trữ dữ liệu, thông báo, kết nối tin nhắn và cuộc gọi

> Cập nhật: 18/10/2026 · Viết lại từ mã nguồn (không sao chép từ tài liệu cũ). Khi sửa mã ở các chỗ được nêu (đường dẫn kèm theo từng mục), hãy sửa tài liệu này.
> Phiên bản đối chiếu: app 1.4.13 (19), backend/web đang chạy trên máy chủ thật.

## 1. Tổng quan nhanh

| Loại dữ liệu | Nằm ở đâu | Máy chủ đọc được? |
|---|---|---|
| Tài khoản, gói, thanh toán, số liệu nhập, khách hàng, kết quả xổ số, cấu hình tính điểm | **Máy chủ** (SQLite), có bản lưu tạm trên máy để dùng offline | Có (Admin chỉ xem phần được cấp quyền, không đọc số liệu của khách) |
| **Tin nhắn bạn bè và nhóm** (chữ, ảnh, tệp) | **Chỉ trên máy** người gửi và người nhận, mã hoá 2 đầu | **Không**: máy chủ chỉ chuyển tiếp và không lưu |
| **Phản hồi với Admin** (hỗ trợ) | **Máy chủ** (bảng `direct_messages`) | **Có** (không mã hoá 2 đầu) |
| Khoá riêng mã hoá chat | Kho khoá của máy (Keychain / Keystore) hoặc IndexedDB (web, khoá không xuất được) | Không (chỉ có khoá **công khai**) |
| Lịch sử cuộc gọi (ai gọi ai, trạng thái, thời lượng) | **Máy chủ** (`call_logs`) | Có (không có âm thanh) |
| Âm thanh cuộc gọi | Không lưu ở đâu cả (WebRTC trực tiếp giữa hai máy, qua TURN nếu cần) | Không |

## 2. Dữ liệu trên máy chủ

Một file SQLite: `/opt/xs-maxmin/backend/build/data/xoso.db` (quyền 600). Máy chủ thật: container 501 trên host Proxmox `10.5.100.5`.

| Bảng | Nội dung |
|---|---|
| `users` | tên, tên đăng nhập, **mật khẩu băm (bcrypt)** của mật khẩu đăng nhập / lớp hai / xoá dữ liệu, mã khôi phục băm, gói và hạn mức, khoá **công khai** E2EE (`e2ee_public_key`), quyền nhân viên, `tokens_valid_after` |
| `device_sessions` | mỗi lần đăng nhập một dòng: thiết bị, IP, thời điểm, đã thu hồi chưa |
| `login_attempts`, `security_events` | đếm lần sai và khoá tạm; nhật ký bảo mật (không chứa mật khẩu, mã) |
| `data_entries` | số liệu nhập: khách, ngày, số, điểm vào, điểm ra, loại đánh, đài, ghi chú |
| `customers`, `customer_codes`, `retired_codes`, `customer_syntax_templates` | danh sách khách (tên, SĐT, đài mặc định, cấu hình tính điểm riêng), **Mã ID** kết bạn, mẫu cú pháp |
| `lottery_results` | kết quả xổ số **theo từng tài khoản** (ngày, đài) |
| `deletion_schedules` | lịch xoá dữ liệu |
| `friendships` | ai là bạn của ai (hai dòng mỗi cặp) |
| `direct_messages` | **hội thoại khách – Admin** (nội dung chữ + ảnh đính kèm dạng BLOB, tối đa 5 MB). Tin bạn bè cũ trong bảng này đã bị xoá khi chuyển sang mã hoá 2 đầu (11/10/2026) |
| `message_reads` | mốc đã đọc để tính huy hiệu chưa đọc |
| `call_logs` | người gọi, người nhận, trạng thái (nhỡ, từ chối, bận, hoàn tất, lỗi), thời điểm, thời lượng |
| `push_tokens` | mã thiết bị để gửi thông báo đẩy (iOS và Android), gắn với tài khoản |
| `payment_requests`, `transactions`, `packages` | thanh toán, lịch sử mua, danh mục gói |
| `settings`, `announcements` | cấu hình hệ thống (ngân hàng, giá, phiên bản app, chính sách), thông báo bảo trì |
| `recovery_requests` | yêu cầu nhờ Admin hỗ trợ khôi phục |

Sao lưu: Admin tạo bản sao ở `data/backups/` (từ màn Cài đặt); ngoài ra cron hằng ngày 03:30 sao ra `/var/backups/xs-maxmin/` (giữ 14 bản, **cùng ổ đĩa**). Xem `deploy/README-ops.md`.

**Xoá dữ liệu tài khoản** (`lib/src/data_wipe.dart`) xoá số liệu, khách, mã ID, kết quả, lịch xoá, hội thoại hỗ trợ; giữ giao dịch đã duyệt, bạn bè và nhật ký bảo mật. Chưa bật `secure_delete`/`VACUUM`, và bản sao lưu không bị xoá theo.

## 3. Dữ liệu trên thiết bị

### 3.1. App (Android / iPhone)

| Nơi lưu | Khoá / tệp | Nội dung |
|---|---|---|
| Kho khoá hệ thống (Keychain / Keystore, `flutter_secure_storage`) | `xoso_token` | mã đăng nhập (JWT) |
| | `mamba_e2ee_identity_<userId>` | **khoá riêng** mã hoá chat của tài khoản này |
| SQLite trong thư mục riêng của app | `mamba-e2ee-<userId>.db` (+ tệp đính kèm đã giải mã trong thư mục app) | **lịch sử chat bạn bè và nhóm đã giải mã**, thông tin khoá bạn bè, cài đặt từng cuộc trò chuyện (ghim, tự xoá, lưu trữ, nhóm: `group:<id>`, báo cáo đã lưu) |
| `shared_preferences` | `xoso_offline_queue` | hàng chờ offline (thêm, sửa, xoá số liệu; thêm, xoá khách) |
| | `entries:<userId>`, `get:<userId>:<đường dẫn>` (trong `xoso_cache:`) | bản sao số liệu, khách, cấu hình tính điểm, kết quả để dùng khi mất mạng |
| | `xoso_results:<userId>` | kết quả xổ số lưu trên máy trước rồi gửi |
| | `xoso_stations_catalog` | bản danh mục đài lấy từ máy chủ (ngoài bản có sẵn trong app) |
| | `xoso_privacy`, `xoso_locked`, `xoso_last_active`, `xoso_mask_*`, `xoso_confirm_copy`, `xoso_dismissed_notices`, `mamba_keep_alive`, `mamba_*_asked`, `update_dismissed_<phiên bản>` | cài đặt riêng của thiết bị, khoá tự động, ẩn số liệu, thông báo đã xem |

Quan trọng:
- **Gỡ app hoặc cài lại = mất lịch sử chat và hàng chờ chưa gửi** (khoá riêng trong Keychain iOS có thể còn, nhưng tin thì mất). Phải **cài đè** khi cập nhật: `tools/install_ios.sh` (iPhone) hoặc `adb install -r` (Android); **không dùng `flutter install`**.
- Đăng xuất / đăng nhập lại **không xoá** lịch sử chat (mỗi tài khoản một file `.db`).
- Android: `allowBackup` đang là mặc định (cho phép Google sao lưu dữ liệu app); đang được sửa thành tắt (xem `docs/KIEM_TOAN_18-10-2026.md`).
- Đọc ảnh (OCR) chạy trên máy bằng ML Kit; ảnh không được gửi đi đâu.

### 3.2. Web

| Nơi lưu | Khoá | Nội dung |
|---|---|---|
| `localStorage` | `xoso_token`, `xoso_role` | mã đăng nhập (JWT) và vai trò. **Token để trong localStorage nên có thể bị đọc nếu có lỗi XSS** (chưa tìm thấy lỗi XSS) |
| | `xoso_theme`, `xoso_privacy`, `xoso_locked`, `xoso_last_active`, `xoso_mask_*`, `xoso_confirm_copy`, `xoso_dismissed_notices`, `xs_voice_fx` | cài đặt giao diện, khoá tự động |
| `sessionStorage` | `entries-prefill`, `calc-sync` | chuyển nội dung giữa các tab Nhập số, Tính điểm |
| IndexedDB `xoso-offline` | | hàng chờ offline và bản sao số liệu, khách, hồ sơ |
| IndexedDB `mamba-e2ee-<userId>` | `identity`, `peers`, `messages`, `meta` | khoá riêng (**không xuất được**), khoá bạn bè, **lịch sử chat đã giải mã**, cài đặt |
| Cache của service worker `mamba-shell-v4` | | chỉ vỏ trang và file tĩnh; **không** cache `/api/` |

Xoá dữ liệu trình duyệt = mất lịch sử chat web. Web chưa xoá IndexedDB khi đăng xuất.

## 4. Kết nối thời gian thực (tin nhắn và cuộc gọi)

**Một đường duy nhất:** `wss://xs.massagehomeriyadh.com/api/ws/calls?token=<JWT>`.
- Đi qua Cloudflare Tunnel → nginx (có `Upgrade`) → backend `127.0.0.1:9091` (`routes/api/ws/calls.dart`).
- Mã JWT nằm trong **địa chỉ** (trình duyệt không gửi được header cho WebSocket), nên có thể lọt vào log máy chủ trung gian. Đã ghi nhận để đổi sang vé một lần.
- Máy chủ kiểm tra phiên (`sessionIsActive`) lúc bắt tay. Admin cũng giữ kênh này để nhận sự kiện phản hồi của khách, nhưng không nhắn tin bạn bè hay gọi. Máy chủ ping 10 giây; app ping 20 giây; app tự nối lại với độ trễ tăng dần từ 1 giây đến 30 giây (có ngẫu nhiên) và nối lại ngay khi mở lại app; web nối lại tương tự.
- Mỗi tin mang địa chỉ người nhận `to`; máy chủ **đổi `to` thành `from` = id của người gửi**, nên không thể mạo danh.

### 4.1. Tin nhắn bạn bè (mã hoá 2 đầu)
1. Mỗi máy có cặp khoá ECDH P-256. **Khoá công khai** được đưa lên máy chủ (`PUT /me/e2ee-key`), khoá riêng không rời máy.
2. Gửi tin: máy tính khoá chung với bạn (ECDH + HKDF), mã hoá bằng AES-256-GCM, kèm AAD `from|to|id`, rồi gửi khung `e2ee-msg {id, iv, ct, part/parts, ts}`. Tệp/ảnh lớn được cắt tối đa 8 phần, mỗi phần ≤ 2 MB.
3. Máy chủ **chỉ chuyển tiếp nếu hai người là bạn và người nhận đang online**. Nếu không: trả `e2ee-undelivered` cho người gửi (tin hiện "chưa gửi", có nút Gửi lại). Máy chủ không giữ gì.
4. Người nhận giải mã, lưu vào kho chat trên máy, trả `e2ee-ack`; người gửi thấy "đã nhận". Không trả ack trong 15 giây thì người gửi coi là lỗi.
5. **Nhóm chat:** nhóm chỉ tồn tại trên máy các thành viên; tin nhóm được mã hoá riêng cho từng thành viên và gửi như tin 1-1, kèm phần mô tả nhóm (`g`). Thành viên phải là bạn của người tạo.
6. Đổi khoá của bạn (cài lại, đổi máy) sẽ hiện cảnh báo "khoá đã đổi". Hiện vẫn gửi được sau cảnh báo (đang chờ quyết định có chặn không).

### 4.2. Cuộc gọi thoại (không có video)
1. **Báo hiệu** qua cùng WebSocket: `call-invite` → (`call-ringing` / `call-unavailable` nếu người kia không online) → `call-accept` → `offer` / `answer` / `ice` → `call-end` / `call-reject`. Chỉ cho gọi giữa bạn bè, không gọi Admin; giới hạn 6 lời mời mỗi phút; máy chủ từ chối mọi yêu cầu có video.
2. **Âm thanh** đi trực tiếp giữa hai máy (WebRTC). Máy lấy danh sách STUN/TURN từ `GET /api/calls/ice-servers`: STUN của Cloudflare, và **TURN của Cloudflare Realtime** (thông tin đăng nhập TURN tạm thời, có hạn). TURN chỉ được dùng khi hai máy không nối trực tiếp được (khác mạng).
3. Chuông đổ 30 giây; hết hạn thì cuộc gọi nhỡ. Nếu một bên rớt kết nối mà chưa kết thúc, máy chủ **tự gửi `call-end` (`disconnected`)** cho bên kia.
4. Máy chủ ghi một dòng `call_logs` cho mỗi cuộc gọi (trạng thái, thời lượng), không có nội dung.
5. Người nhận **đang offline hoặc app đã bị tắt hẳn**: không có chuông; chỉ có thể có **thông báo đẩy** (mục 5.3). Mở app lên thì cuộc gọi thường đã kết thúc và hiện là cuộc gọi nhỡ.

### 4.3. Phản hồi Admin
Dùng REST (`/me/messages`, `/admin/messages/...`), **không** qua mã hoá 2 đầu, lưu ở máy chủ. Khi có tin mới, máy chủ đẩy sự kiện `new-message` qua WebSocket để app hiện thông báo; ngoài ra app/web tự đối chiếu `/me/unread` mỗi 10 giây (dự phòng khi WebSocket bị chặn).

## 5. Thông báo

### 5.1. Khi đang mở app / trang web
- **Huy hiệu số đỏ** và danh sách cập nhật theo `new-message` và `/me/unread`; số chưa đọc nằm ở máy chủ (`message_reads`) cho phản hồi Admin, và trên máy cho chat bạn bè.
- **Toast** trong app/web, **âm báo**, rung (điện thoại), và với web khi tab ẩn: `Notification` của trình duyệt (cần người dùng cho phép) và tiêu đề tab nhấp nháy khi có cuộc gọi.
- App Android/iPhone: thông báo cục bộ qua các kênh `mamba_messages`, `mamba_calls_incoming_v2` (cuộc gọi đến, đủ màn hình), `mamba_calls_incoming_inapp`, `mamba_calls_missed`. **Nội dung tin không hiện** trên thông báo (chỉ tên người gửi).

### 5.2. App chạy nền
Mặc định tắt. Bật "Giữ kết nối khi thoát app" thì app chạy dịch vụ nền (foreground service) giữ WebSocket sống: nhận được tin và cuộc gọi khi app ở nền, **tốn pin**, và một số hãng máy có thể tự tắt.

### 5.3. Khi app bị tắt hẳn (thông báo đẩy)
- Máy chủ chỉ gửi khi người nhận **không online**: `notifyOfflineRecipient` (`lib/src/push_notify.dart`), tối đa **1 thông báo mỗi (người gửi, người nhận, loại) mỗi 60 giây**.
- **Android: Firebase Cloud Messaging** (dự án `mamba-99e37`, khoá dịch vụ trên máy chủ). **iPhone: APNs của Apple** — **chưa cấu hình khoá Apple trên máy chủ nên iPhone chưa nhận được thông báo đẩy**.
- Nội dung thông báo chỉ có: tên hiển thị người gửi, loại (tin / cuộc gọi) và id người gửi (để mở đúng cuộc trò chuyện): tin "Đang nhắn tin cho bạn. Mở MAMBA để nhận." hoặc "Cuộc gọi đến". **Không bao giờ có nội dung tin.**
- Thông báo chỉ **đánh thức**: tin vẫn không được lưu ở đâu. Người gửi thấy "chưa gửi" và bấm Gửi lại sau khi người nhận mở app.
- Mã thiết bị lưu ở `push_tokens`. App đăng ký sau khi khách đăng nhập và gỡ khi đăng xuất. (Phần máy chủ tự xoá mã khi thu hồi phiên đang được sửa.)

### 5.4. Thông báo hệ thống
Admin đăng thông báo bảo trì hoặc chính sách (`announcements`), hiện thành banner cho người dùng; người dùng bấm "Đã hiểu" thì ẩn (`xoso_dismissed_notices`).

## 6. Những điều cần biết và còn mở
1. **Phản hồi Admin không mã hoá 2 đầu** và nằm ở máy chủ (bản thiết kế hiện tại; chat bạn bè thì có).
2. **Tin nhắn bạn bè không có bản dự phòng ở đâu**: mất app, đổi máy, xoá dữ liệu trình duyệt là mất. Đây là cam kết quyền riêng tư, không phải lỗi.
3. Chưa có hàng đợi tin mã hoá cho người đang offline (chỉ cả hai cùng online mới nhận được tin).
4. Thông báo đẩy iPhone chờ khoá APNs; thông báo Android đã chạy (đã thử 1 thông báo thật).
5. Sao lưu máy chủ chưa có bản ngoài ổ đĩa; bản sao Admin và cron nằm cùng máy.
