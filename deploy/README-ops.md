# Ops notes (xs.massagehomeriyadh.com, container 501)

- Security headers: `nginx-security-headers.conf` is installed at
  `/etc/nginx/xs-maxmin-security-headers.conf` and included from the server block of
  `/etc/nginx/sites-enabled/xs-maxmin.conf`. CSP is Report-Only; review before enforcing.
  Always `nginx -t` before `nginx -s reload`; keep backups outside sites-enabled.
- DB backup: `xs-maxmin-backup.sh` -> `/usr/local/bin/` (chmod 755); `xs-maxmin-backup.cron`
  -> `/etc/cron.d/xs-maxmin-backup`. Uses `sqlite3 .backup` (safe while the service runs),
  verifies integrity, keeps newest 14 in `/var/backups/xs-maxmin` (700/600), logs to
  `/var/log/xs-maxmin/backup.log`.
- Restore: stop xs-maxmin-backend, copy a backup over `xoso.db`, chmod 600, start the service.
- Permissions: DB dir contents are 600 (backend runs as root).

## Đăng APK để app tự nhắc cập nhật (chỉ khi chủ dự án đã đồng ý)

`tools/publish_apk.sh <apk> [--notes "…"]` chạy thử và in kế hoạch, **không gửi gì**. Chỉ khi chủ dự án đã nói đồng ý đăng mới chạy thêm `--yes`: tệp được chép lên `/opt/xs-maxmin/web/downloads/MAMBA-<phiên bản>.apk` (nginx phục vụ ở `https://xs.massagehomeriyadh.com/downloads/…`, **công khai**, giữ 3 bản mới nhất), tải lại để so SHA-256, rồi mới đặt `app_latest_version`, `app_download_url`, `app_release_notes` trong bảng `settings` (app đọc từ `GET /api/app-version`). Các lần deploy web không xoá thư mục `downloads/`. Lưu ý: APK ký bằng khoá debug (chưa có khoá phát hành) chỉ cập nhật đè được lên bản đã cài cùng khoá.
