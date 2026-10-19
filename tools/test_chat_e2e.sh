#!/bin/bash
# Kiểm thử chat giữa hai thiết bị bằng mã app thật + máy chủ thật, trên một máy chủ THỬ cô lập (bản sao backend, DB mới,
# cổng 8597): hai tài khoản mới, kết bạn, gửi/nhận/ack/offline/gửi lại. Không đụng dữ liệu thật. ~1 phút.
#   tools/test_chat_e2e.sh
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export PATH="$PATH:$HOME/.pub-cache/bin"
PORT=${PORT:-8597}
WORK=$(mktemp -d /tmp/mamba-chat-e2e.XXXXXX)
mkdir -p "$WORK/be"
(cd "$ROOT/backend" && tar --exclude=./data --exclude=./build -cf - .) | (cd "$WORK/be" && tar xf -)
cd "$WORK/be" || exit 1
XOSO_JWT_SECRET=e2e-secret-0123456789abcdef XOSO_ADMIN_PASSWORD='E2e-admin-pass-1' \
  dart_frog dev --port "$PORT" --dart-vm-service-port $((PORT + 1)) >"$WORK/server.log" 2>&1 &
SERVER=$!
cleanup() { kill "$SERVER" 2>/dev/null; sleep 1; pkill -P "$SERVER" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT
for _ in $(seq 1 90); do curl -s -o /dev/null "http://localhost:$PORT/api/auth/login" && break; sleep 1; done
curl -s -o /dev/null "http://localhost:$PORT/api/auth/login" || { echo "máy chủ thử không khởi động được:"; tail -20 "$WORK/server.log"; exit 1; }
cd "$ROOT/app" && flutter test test_e2e/chat_two_devices_test.dart --dart-define=API_BASE="http://localhost:$PORT"
