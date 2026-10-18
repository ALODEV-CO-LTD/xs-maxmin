# Script kiểm thử giao diện / API (puppeteer)

Các script này là ví dụ đã dùng trong quá trình phát triển, **không phải bộ test tự động hoàn chỉnh**. Chạy bằng Node, cần Chrome cài trên máy và `puppeteer-core` (`npm i puppeteer-core` trong thư mục này hoặc thư mục tạm).

## Dựng môi trường cô lập (không đụng DB thật)
1. Sao chép thư mục `backend` sang chỗ khác (ví dụ `/tmp/bt`), chạy:
   `cd /tmp/bt && XOSO_JWT_SECRET=testsecret-0123456789abc XOSO_SEED_DEMO=1 XOSO_ADMIN_PASSWORD='<mật khẩu thử bạn tự đặt>' dart_frog dev --port 8291 --dart-vm-service-port 8292`
   Backend không còn mật khẩu admin cố định: không đặt `XOSO_ADMIN_PASSWORD` thì mật khẩu admin ngẫu nhiên được in một lần ra log. `XOSO_SEED_DEMO=1` mới tạo các khách demo (chỉ dùng cho backend thử, không bao giờ bật trên máy chủ thật).
2. Build web: `cd frontend && npm run build`.
3. Phục vụ web đã build và chuyển `/api` sang backend thử: `node tools/e2e/serve.mjs frontend/dist 4173 8291`.
4. Chạy script, ví dụ `node tools/e2e/sup.mjs` (cổng 4173 và 8291 đang được mã hoá cứng ở đầu từng file – sửa nếu đổi).

## Các script
| File | Kiểm tra |
|---|---|
| `sup.mjs` | Popover Phản hồi: nút, số đỏ, tin mới ở trên, đóng bằng Esc/bấm ngoài, điện thoại |
| `mask2.mjs` | Ẩn số liệu trên Khách hàng và Nhập số (cần user mẫu `histk3pca` có khách "Khach A" – tự tạo trong DB thử) |
| `tabs.mjs` | Các tab trang Tài khoản |
| `recov.mjs` | Admin hỗ trợ khôi phục: đặt lại mật khẩu, mã khôi phục mới, gỡ khoá, nhật ký |
| `msgui.mjs` | Huy hiệu chưa đọc, thứ tự cuộc trò chuyện |
| `integ.mjs` | Luồng đăng ký/đăng nhập/đổi mật khẩu/khôi phục (có giới hạn 20 lần/IP nên chạy lặp nhiều có thể lỗi giả) |

Các script đăng nhập admin (`integ.mjs`, `recov.mjs`, `sup.mjs`) đọc mật khẩu từ biến môi trường `E2E_ADMIN_PASSWORD` (không có giá trị mặc định; thiếu thì script dừng). Đặt nó trùng `XOSO_ADMIN_PASSWORD` của backend thử, ví dụ:
`E2E_ADMIN_PASSWORD='<cùng mật khẩu>' node tools/e2e/recov.mjs`

Lưu ý: mật khẩu trong script (`Smoke#Test123`, `2468`) chỉ là dữ liệu thử cho backend cô lập.
