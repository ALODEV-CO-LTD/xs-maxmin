#!/bin/bash
# Run inside container 501. Deploys the new web + backend, rolls back on failure.
set -u
TS=$(date +%Y%m%d-%H%M%S)
OPT=/opt/xs-maxmin
export PATH=$PATH:/root/.pub-cache/bin

echo "== 1) backup ($TS)"
cp -a $OPT/backend $OPT/backend.bak-$TS || exit 1
cp -a $OPT/web $OPT/web.bak-$TS || exit 1
cp -a $OPT/backend/build/data/xoso.db /root/xoso-live-$TS.db || exit 1
sqlite3 /root/xoso-live-$TS.db "select 'users',count(*) from users;" || exit 1

rollback() {
  echo "!! ROLLBACK to $TS"
  systemctl stop xs-maxmin-backend
  rm -rf $OPT/backend && cp -a $OPT/backend.bak-$TS $OPT/backend
  rm -rf $OPT/web && cp -a $OPT/web.bak-$TS $OPT/web
  systemctl start xs-maxmin-backend
  sleep 3; curl -s localhost:9091/; echo
  exit 1
}

echo "== 2) stage new source (service still running)"
rm -rf /root/stage && mkdir -p /root/stage/web /root/stage/backend
tar -xzf /root/web_dist.tar.gz -C /root/stage/web || exit 1
tar -xzf /root/backend_deploy.tar.gz -C /root/stage/backend || exit 1
find /root/stage -name '._*' -delete
test -f /root/stage/web/index.html && test -f /root/stage/backend/routes/api/ws/calls.dart || { echo "bad package"; exit 1; }

echo "== 3) web"
rm -rf $OPT/web/assets $OPT/web/index.html $OPT/web/sw.js
cp -a /root/stage/web/. $OPT/web/ || rollback

echo "== 4) backend source (old lib/routes removed so renamed routes leave no stale files)"
systemctl stop xs-maxmin-backend
rm -rf $OPT/backend/lib $OPT/backend/routes
cp -a /root/stage/backend/. $OPT/backend/ || rollback
cd $OPT/backend || rollback
dart pub get || rollback
dart_frog build || rollback
mkdir -p build/data && cp -a $OPT/backend.bak-$TS/build/data/. build/data/ || rollback
# dart_frog build recreates build/ and drops the native-asset cache of the
# sqlite3 package; this server cannot reach github.com to download it again, so
# carry the cache over from the previous build (same package versions).
mkdir -p build/.dart_tool
for d in hooks_runner native_assets native_assets.yaml lib; do
  [ -e $OPT/backend.bak-$TS/build/.dart_tool/$d ] && cp -a $OPT/backend.bak-$TS/build/.dart_tool/$d build/.dart_tool/
done

echo "== 5) start"
systemctl start xs-maxmin-backend
UP=0
for i in $(seq 1 45); do
  if curl -s localhost:9091/ | grep -q "Welcome to Dart Frog"; then UP=1; break; fi
  sleep 1
done
[ "$UP" = "1" ] || { echo "backend did not come up in 45s"; tail -15 /var/log/xs-maxmin/backend.log | cut -c1-200; rollback; }
systemctl is-active xs-maxmin-backend || rollback
CODE=$(curl -s -o /dev/null -w "%{http_code}" localhost:9091/api/calls/ice-servers)
[ "$CODE" = "401" ] || { echo "new route not live (got $CODE)"; rollback; }
curl -s -H 'content-type: application/json' -d '{"username":"zz-khong-ton-tai","password":"x"}' localhost:9091/api/auth/login; echo
sqlite3 $OPT/backend/build/data/xoso.db "select 'users',count(*) from users union all select 'messages',count(*) from direct_messages;"
curl -s -o /dev/null -w "public https: %{http_code}\n" https://xs.massagehomeriyadh.com
echo "== DONE ($TS) rollback dirs: backend.bak-$TS web.bak-$TS ; db copy /root/xoso-live-$TS.db"
