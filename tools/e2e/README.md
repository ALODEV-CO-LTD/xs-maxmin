# Script kiểm thử giao diện / API (puppeteer)

Các script này là ví dụ đã dùng trong quá trình phát triển, **không phải bộ test tự động hoàn chỉnh**. Chạy bằng Node, cần Chrome cài trên máy và `puppeteer-core` (`npm i puppeteer-core` trong thư mục này hoặc thư mục tạm).

## Dựng môi trường cô lập (không đụng DB thật)
1. Sao chép thư mục `backend` sang chỗ khác (ví dụ `/tmp/bt`), chạy:
   `cd /tmp/bt && XOSO_JWT_SECRET=testsecret-0123456789abc dart_frog dev --port 8291 --dart-vm-service-port 8292`
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

Lưu ý: mật khẩu trong script (`Smoke#Test123`, `2468`) chỉ là dữ liệu thử cho backend cô lập.
