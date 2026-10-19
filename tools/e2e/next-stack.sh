#!/bin/bash
# Dựng bản web Next.js (web-next/out) cạnh một backend THỬ cô lập (bản sao backend, DB mới, không đụng dữ liệu thật):
#   tools/e2e/next-stack.sh start   -> backend :8591, web :8592 (SITE=http://127.0.0.1:8592), in ra mật khẩu admin thử
#   tools/e2e/next-stack.sh stop
# Admin thử: tài khoản "1", mật khẩu in ra bởi `start` (XOSO_ADMIN_PASSWORD) và mật khẩu lớp hai là chính nó.
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 PATH="$PATH:$HOME/.pub-cache/bin"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# Đổi cổng bằng biến môi trường khi nhiều phiên chạy cùng lúc, ví dụ: BE=8611 WEB=8612 VM=8615 tools/e2e/next-stack.sh start
BE=${BE:-8591}; WEB=${WEB:-8592}; VM=${VM:-8595}
WORK=/tmp/mamba-next-stack-$BE
case "$1" in
  start)
    "$0" stop >/dev/null 2>&1
    rm -rf "$WORK"; mkdir -p "$WORK/be"
    (cd "$ROOT/backend" && tar --exclude=./data --exclude=./build -cf - .) | (cd "$WORK/be" && tar xf -)
    [ -d "$ROOT/web-next/out" ] || (cd "$ROOT/web-next" && npm run build) || exit 1
    (cd "$WORK/be" && XOSO_JWT_SECRET=next-stack-secret-0123456789 XOSO_ADMIN_PASSWORD='Next-admin-Pass-1' XOSO_SEED_DEMO=1 \
      nohup dart_frog dev --port $BE --dart-vm-service-port $VM >"$WORK/backend.log" 2>&1 &)
    (nohup node "$ROOT/tools/e2e/serve.mjs" "$ROOT/web-next/out" $WEB $BE >"$WORK/web.log" 2>&1 &)
    for _ in $(seq 1 90); do curl -s -o /dev/null "http://127.0.0.1:$BE/api/auth/login" && break; sleep 1; done
    curl -s -o /dev/null "http://127.0.0.1:$BE/api/auth/login" || { echo "backend không khởi động:"; tail -20 "$WORK/backend.log"; exit 1; }
    echo "SITE=http://127.0.0.1:$WEB  API=http://127.0.0.1:$WEB/api  admin=1 / Next-admin-Pass-1 (lớp hai: cùng mật khẩu)" ;;
  stop)
    for p in $BE $VM $WEB; do lsof -ti "tcp:$p" -sTCP:LISTEN 2>/dev/null | xargs kill 2>/dev/null; done
    sleep 1; rm -rf "$WORK" ;;
  *) echo "usage: $0 start|stop"; exit 1 ;;
esac
