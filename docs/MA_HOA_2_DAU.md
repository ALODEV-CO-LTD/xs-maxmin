# Kế hoạch mã hoá 2 đầu (E2EE) kiểu Zangi

Quyết định của chủ dự án (10/10/2026): chỉ gửi tin khi cả hai cùng online; đổi máy thì mất lịch sử và tạo khoá mới; phản hồi Admin giữ riêng; chấp nhận mất hạn mức theo bản ghi, lịch xoá chạy ở máy chủ và đồng bộ nhiều thiết bị; số liệu/khách hàng chỉ lưu trên thiết bị khi có app (web giữ nguyên như hiện tại); chống chiếm mã JS tính sau, khi dựng app.

## 0. Trạng thái triển khai

**Đã làm (giai đoạn 1-3, chat bạn bè):**
- `frontend/src/e2ee/crypto.js` (ECDH P-256, HKDF, AES-256-GCM, AAD = người gửi|người nhận|id tin), `db.js` (IndexedDB trên máy), `chat.js` (kho Pinia: khoá, gửi/nhận, trạng thái, chưa đọc, tự xoá trên máy, cảnh báo đổi khoá).
- Máy chủ: `PUT/GET /me/e2ee-key` (chỉ khoá công khai), danh sách bạn trả `publicKey`, relay `e2ee-msg`/`e2ee-ack` qua `/ws/calls` (chia phần, không ghi DB, báo `e2ee-undelivered` nếu người nhận offline), route tin nhắn bạn bè cũ trả 410.
- Khi khởi động lần đầu, lịch sử chat bạn bè cũ (plaintext) bị xoá khỏi DB. Phản hồi Admin không đổi.
- Kiểm thử: `node tools/e2e/e2ee.mjs` (primitives), `node tools/e2e/e2ee-relay.mjs <A> <passA> <secondA> <B> <passB> <secondB>` (relay thật: offline, tệp 5 MB, ack, người lạ bị từ chối).

**Chưa làm:** giai đoạn 4 (số liệu/khách hàng chỉ trên thiết bị, khi có app), mã hoá phản hồi Admin bằng khoá của Admin, khoá tạm/ratchet (forward secrecy), bỏ hẳn bảng và route lịch xoá `chat` phía máy chủ, siêu dữ liệu cuộc gọi (`call_logs`) vẫn ở máy chủ.


## 1. Hiện trạng (đã kiểm tra trong code)

| Dữ liệu | Truyền | Lưu trên máy chủ |
|---|---|---|
| Mọi API | TLS (Cloudflare Tunnel) | - |
| Tin nhắn/tệp bạn bè (`direct_messages`) | TLS | **Plaintext** trong SQLite, kể cả bytes tệp |
| Phản hồi Admin (`direct_messages`) | TLS | **Plaintext** |
| Gọi thoại | WebRTC (DTLS-SRTP, mã hoá 2 đầu); TURN chỉ thấy gói đã mã hoá | Chỉ siêu dữ liệu (`call_logs`) |
| Số liệu nhập, khách hàng, cấu hình tính điểm, lịch xoá | TLS | **Plaintext**; máy chủ tính hạn mức gói và chạy lịch xoá |

Ghi chú: "không lưu trên máy chủ" kéo theo bỏ các tính năng đang chạy ở máy chủ (hạn mức theo số bản ghi, lịch xoá tự động, đồng bộ nhiều thiết bị, tìm kiếm phía máy chủ).

## 2. Thiết kế đề xuất

**Khoá.** Mỗi thiết bị tạo cặp khoá ECDH P-256 bằng WebCrypto, khoá riêng `extractable: false` lưu trong IndexedDB. Khoá công khai (và vân tay) đăng ký lên máy chủ. Khóa riêng không bao giờ rời máy.

**Tin nhắn.** Khoá phiên = HKDF(ECDH(khoá riêng mình, khoá công khai bạn)); mỗi tin dùng AES-256-GCM với IV ngẫu nhiên, gắn id người gửi/nhận làm dữ liệu xác thực. Tệp/ảnh mã hoá trên máy trước khi gửi (đã xoá metadata ảnh, xem `attachments.js`).

**Chuyển tiếp, không lưu.** Qua WebSocket `/api/ws/calls`: máy chủ chỉ chuyển gói `{to, from, id, iv, ct}` nếu người nhận đang online, không ghi DB. Người nhận offline thì máy chủ báo lại và người gửi thấy "Chưa gửi, bạn bè đang offline". Có xác nhận đã nhận.

**Lưu trên máy.** Lịch sử chat nằm trong IndexedDB của từng thiết bị. Số chưa đọc, tự xoá theo thời gian (`ChatRetentionPanel`) và nhật ký cuộc gọi chuyển sang phía máy.

**Đổi máy / xoá dữ liệu trình duyệt.** Mất lịch sử, tạo khoá mới. Bạn bè được báo "khoá bảo mật của X đã thay đổi" và có thể đối chiếu vân tay.

**Dữ liệu cá nhân (số liệu, khách hàng, cấu hình).** Cần quyết định riêng, xem mục 4.

## 3. Các giai đoạn

1. Thư viện mã hoá + đăng ký khoá công khai + test (không đụng chức năng cũ).
2. Chat bạn bè: relay WebSocket, kho IndexedDB, tệp/ảnh mã hoá, chỉ báo "offline", báo đổi khoá.
3. Chuyển số chưa đọc, tự xoá, nhật ký cuộc gọi sang phía máy; xoá bảng và route tin nhắn cũ trên máy chủ.
4. Dữ liệu cá nhân (theo quyết định ở mục 4).
5. Phản hồi Admin (xem 4.3), rà soát, viết lại `BAN_GIAO.md`.

## 4. Điểm cần chốt trước khi làm giai đoạn 4-5

1. **Dữ liệu cá nhân chỉ ở trình duyệt thì dễ mất sạch.** Safari iOS có thể xoá IndexedDB sau vài ngày không dùng; xoá dữ liệu trình duyệt hay đổi máy là mất toàn bộ số liệu kinh doanh. Hai hướng: (a) chỉ lưu trên máy, chấp nhận rủi ro, nên có xuất/nhập tệp sao lưu mã hoá; (b) vẫn lưu trên máy chủ nhưng đã mã hoá bằng khoá chỉ nằm ở máy khách (máy chủ không đọc được, vẫn đồng bộ nhiều thiết bị). Đề xuất (b) cho số liệu, vẫn đúng tinh thần "máy chủ không biết nội dung".
2. **Hạn mức gói** hiện do máy chủ đếm bản ghi. Với (a) không đếm được; với (b) đếm được số bản ghi mã hoá.
3. **Phản hồi Admin.** Admin là người vận hành và cần đọc, thường offline. Đề xuất để riêng, vẫn qua máy chủ (có thể mã hoá bằng khoá của Admin), không áp dụng "chỉ gửi khi cả hai online".
4. **Siêu dữ liệu vẫn lộ** (ai nhắn ai, giờ nào, ai gọi ai) vì máy chủ phải chuyển tin. Chỉ nội dung được che.

## 5. Giới hạn trung thực của E2EE trên web

- Máy chủ cũng là nơi phát mã JavaScript, nên nếu máy chủ bị chiếm có thể phát mã lấy khoá. Zangi là app cài sẵn nên không có điểm yếu này. Chống triệt để cần app (Capacitor, xem `BAN_GIAO.md` mục 9) hoặc băm mã để kiểm chứng.
- Không có bí mật chuyển tiếp hoàn hảo (forward secrecy) ở bước đầu vì dùng khoá tĩnh theo thiết bị; thêm khoá tạm cho từng tin hoặc Double Ratchet là bước sau.
- Lần đầu kết bạn nếu không đối chiếu vân tay thì vẫn tin máy chủ khi phát khoá công khai (rủi ro tráo khoá).
- Chụp màn hình, người dùng chép tin ra ngoài: ngoài phạm vi E2EE.
