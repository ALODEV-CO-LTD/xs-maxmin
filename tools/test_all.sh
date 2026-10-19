#!/bin/bash
# Chạy toàn bộ kiểm thử tự động bằng MỘT lệnh, không cần cài app lên máy/simulator, rồi in bảng đạt / lỗi.
#   tools/test_all.sh            app (phân tích + test) + web (test + build) + backend (test)
#   tools/test_all.sh app|web|backend   chỉ một phần
# Thoát 0 nếu tất cả đạt, 1 nếu có phần lỗi. Log từng phần ở /tmp/mamba-test-<phần>.log.
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WANT=${1:-all}
declare -a NAMES RESULTS DETAILS
fail=0

run() { # name, dir, command...
  local name=$1 dir=$2; shift 2
  local log=/tmp/mamba-test-$name.log
  local t0=$SECONDS
  if (cd "$ROOT/$dir" && "$@") >"$log" 2>&1; then r=ĐẠT; else r=LỖI; fail=1; fi
  NAMES+=("$name"); RESULTS+=("$r"); DETAILS+=("$(summary "$name" "$log") ($((SECONDS - t0))s)")
}

summary() { # name, log -> a short count line
  case $1 in
    app-test) grep -oE "\+[0-9]+( -[0-9]+)?: (All tests passed|Some tests failed)" "$2" | tail -1 ;;
    web-test) grep -E "^ℹ (pass|fail) " "$2" | tr '\n' ' ' ;;
    backend-test) grep -oE "\+[0-9]+( -[0-9]+)?: (All tests passed|Some tests failed)" "$2" | tail -1 ;;
    *) tail -1 "$2" ;;
  esac
}

if [[ $WANT == all || $WANT == app ]]; then
  run app-analyze app dart analyze lib test
  run app-test app flutter test
fi
if [[ $WANT == all || $WANT == web ]]; then
  run web-test frontend npm test
  run web-build frontend npm run build
fi
if [[ $WANT == all || $WANT == backend ]]; then
  run backend-test backend dart test
fi

echo
printf '%-16s %-6s %s\n' PHẦN KẾT-QUẢ CHI-TIẾT
printf '%-16s %-6s %s\n' ---------------- ------ ----------------------------
for i in "${!NAMES[@]}"; do printf '%-16s %-6s %s\n' "${NAMES[$i]}" "${RESULTS[$i]}" "${DETAILS[$i]}"; done
echo
if [[ $fail == 0 ]]; then echo "TẤT CẢ ĐẠT"; else echo "CÓ LỖI - xem log /tmp/mamba-test-<phần>.log"; fi
exit $fail
