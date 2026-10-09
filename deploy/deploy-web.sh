#!/bin/bash
# Web-only deploy: backend is not touched or restarted.
set -u
TS=$(date +%Y%m%d-%H%M%S); OPT=/opt/xs-maxmin
cp -a $OPT/web $OPT/web.bak-$TS || exit 1
rm -rf /root/stage-web && mkdir -p /root/stage-web && tar -xzf /root/web_dist.tar.gz -C /root/stage-web 2>/dev/null
find /root/stage-web -name '._*' -delete
test -f /root/stage-web/index.html && test -f /root/stage-web/tesseract/lang/eng.traineddata.gz || { echo "bad package"; exit 1; }
rollback() { echo "!! ROLLBACK"; rm -rf $OPT/web && cp -a $OPT/web.bak-$TS $OPT/web; exit 1; }
rm -rf $OPT/web/assets $OPT/web/index.html $OPT/web/sw.js $OPT/web/tesseract
cp -a /root/stage-web/. $OPT/web/ || rollback
curl -s -o /dev/null -w "local index: %{http_code}\n" -H "Host: xs.massagehomeriyadh.com" http://127.0.0.1/ 
curl -sI -H "Host: xs.massagehomeriyadh.com" http://127.0.0.1/tesseract/lang/eng.traineddata.gz | grep -iE "^HTTP|content-type|content-encoding|content-length" | tr -d '\r' | tr '\n' ' '; echo
echo "api still up: $(curl -s localhost:9091/)"; systemctl is-active xs-maxmin-backend
echo "DONE $TS (rollback: web.bak-$TS)"
