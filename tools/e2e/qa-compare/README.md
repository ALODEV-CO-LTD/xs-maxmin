# So sánh bản Next.js (web-next) với bản Vue (frontend/) bằng Chrome

Cần: `BE=8631 WEB=8632 VM=8635 tools/e2e/next-stack.sh start` (backend thử + Next), `node tools/e2e/serve.mjs frontend/dist 8633 8631` (Vue), `PPT=<thư mục có node_modules/puppeteer-core>`.
Chạy trong thư mục này: `node seed.mjs` (tạo 2 khách nx/vu, ghi seed.json; đăng ký giới hạn 10 lần/giờ/IP) rồi `FILTER=1 node run.mjs sc_pay.mjs` (mỗi `sc_*.mjs` là một kịch bản chạy trên CẢ HAI bản, in SAME/DIFF theo chữ và lưu ảnh vào `shots/`), `python3 pix.py sc_pay.mjs` (so từng điểm ảnh). Các file còn lại (flow, auth2, lock, sw, mob, tick, blur, mid401, theme) là kịch bản riêng chạy trực tiếp bằng node. Tên đăng nhập admin thử: `1` / `Next-admin-Pass-1`. Cổng và đường dẫn cố định ở đầu `h.mjs`.
