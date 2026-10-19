#!/bin/bash
# Deploy the Next.js web (web-next/out) to /opt/xs-maxmin/web INSIDE container 501. Backend is not touched.
# Needs /root/web_dist.tar.gz = `tar -czf ... -C web-next/out .`  (from a CLEAN checkout: see docs/BAN_GIAO.md).
# What it does beyond deploy-web.sh: replaces the WHOLE web folder (the Vue build and Next build share no file names),
# and updates the nginx site once so /entries -> entries.html (`try_files $uri $uri.html ...`) and the old thread paths
# /friends/<id>, /admin/messages/<id> land on /friends?thread=<id>, /admin/messages?user=<id>. Everything (web + nginx
# site) is backed up first and restored automatically when a check fails.
set -u
TS=$(date +%Y%m%d-%H%M%S); OPT=/opt/xs-maxmin; SITE=/etc/nginx/sites-enabled/xs-maxmin.conf
cp -a $OPT/web $OPT/web.bak-$TS || exit 1
cp -a "$(readlink -f $SITE)" /root/xs-maxmin.conf.bak-$TS || exit 1
rm -rf /root/stage-web && mkdir -p /root/stage-web && tar -xzf /root/web_dist.tar.gz -C /root/stage-web 2>/dev/null
find /root/stage-web -name '._*' -delete
test -f /root/stage-web/login.html && test -f /root/stage-web/entries.html && test -d /root/stage-web/_next \
  && test -f /root/stage-web/tesseract/lang/eng.traineddata.gz || { echo "bad package (is it web-next/out?)"; exit 1; }

rollback() {
  echo "!! ROLLBACK to $TS"
  rm -rf $OPT/web && cp -a $OPT/web.bak-$TS $OPT/web
  cp -a /root/xs-maxmin.conf.bak-$TS "$(readlink -f $SITE)"
  nginx -t >/dev/null 2>&1 && systemctl reload nginx
  exit 1
}

# 1) files
rm -rf $OPT/web/* && cp -a /root/stage-web/. $OPT/web/ || rollback

# 2) nginx site (idempotent)
CONF=$(readlink -f $SITE)
if ! grep -q 'xs-next-web' "$CONF"; then
  python3 - "$CONF" <<'PY' || rollback
import sys,re
p=sys.argv[1]; s=open(p).read()
old="""    location / {
        try_files $uri $uri/ /index.html;
    }
"""
new="""    # xs-next-web: Next.js static export (/entries -> entries.html); old thread addresses become query strings
    location ~ ^/friends/([^/]+)$ { return 302 /friends?thread=$1; }
    location ~ ^/admin/messages/([^/]+)$ { return 302 /admin/messages?user=$1; }
    location /_next/static/ {
        add_header Cache-Control "public, max-age=31536000, immutable";
        include /etc/nginx/xs-maxmin-security-headers.conf;
    }
    location / {
        try_files $uri $uri.html $uri/ /index.html;
    }
"""
if old not in s: sys.exit(1)
open(p,'w').write(s.replace(old,new,1))
PY
fi
nginx -t 2>&1 | tail -1 | grep -q successful || rollback
systemctl reload nginx || rollback

# 3) checks through nginx (Host header of the site)
H="Host: xs.massagehomeriyadh.com"
sleep 2 # the graceful reload hands over to the new workers a moment after systemctl returns
for path in /login /entries /scoring /account /admin/stats /friends; do
  for try in 1 2 3 4 5; do
    code=$(curl -s -o /dev/null -w "%{http_code}" -H "$H" http://127.0.0.1$path); [ "$code" = "200" ] && break; sleep 1
  done
  echo "$path -> $code"
  [ "$code" = "200" ] || rollback
done
curl -s -o /dev/null -w "/friends/abc -> %{http_code} %{redirect_url}\n" -H "$H" http://127.0.0.1/friends/abc
curl -sI -H "$H" http://127.0.0.1/tesseract/lang/eng.traineddata.gz | grep -iE "^HTTP|content-type|content-encoding" | tr -d '\r' | tr '\n' ' '; echo
echo "api still up: $(curl -s localhost:9091/)"; systemctl is-active xs-maxmin-backend nginx
echo "DONE $TS (rollback: web.bak-$TS and /root/xs-maxmin.conf.bak-$TS)"
