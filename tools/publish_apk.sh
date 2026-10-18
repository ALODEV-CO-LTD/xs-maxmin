#!/bin/bash
# Publish an APK so the app's update card ("Có phiên bản mới" -> "Tải bản mới") can download it.
#
#   tools/publish_apk.sh <apk> [--notes "Ghi chú phát hành"]          DRY RUN: prints the plan, sends NOTHING
#   tools/publish_apk.sh <apk> [--notes "..."] --yes                  uploads and switches the update card on
#
# SAFETY: this puts a file on the PUBLIC internet (anyone with the link can download it). Only run with --yes after the
# owner has said "đồng ý đăng". What --yes does, in order:
#   1. copies the APK to the server as /opt/xs-maxmin/web/downloads/MAMBA-<version>.apk (served by nginx at
#      https://xs.massagehomeriyadh.com/downloads/MAMBA-<version>.apk), keeping only the newest 3 files there;
#   2. downloads it back over HTTPS and compares the SHA-256 with the local file;
#   3. only then sets the Admin settings app_latest_version / app_download_url (/ app_release_notes), which is what the
#      app reads from the public GET /api/app-version.
# The release APK is signed with the debug key unless android/key.properties exists: an update only installs over an
# existing install that was signed with the SAME key.
set -euo pipefail
HOST=root@10.5.100.5
CT=501
SITE=https://xs.massagehomeriyadh.com
APK=${1:?usage: tools/publish_apk.sh <apk> [--notes "..."] [--yes]}; shift || true
NOTES=""; YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) YES=1 ;;
    --notes) NOTES="${2:?--notes needs text}"; shift ;;
    *) echo "unknown option $1"; exit 2 ;;
  esac
  shift
done
[ -f "$APK" ] || { echo "no such file: $APK"; exit 2; }
AAPT=$(ls "$HOME"/Library/Android/sdk/build-tools/*/aapt 2>/dev/null | tail -1)
[ -n "$AAPT" ] || { echo "aapt not found (Android SDK build-tools)"; exit 2; }
BADGE=$("$AAPT" dump badging "$APK" | grep -m1 '^package:')
PKG=$(echo "$BADGE" | sed -E "s/^package: name='([^']+)'.*/\1/")
VER=$(echo "$BADGE" | sed -E "s/.* versionName='([^']+)'.*/\1/")
CODE=$(echo "$BADGE" | sed -E "s/.* versionCode='([^']+)'.*/\1/")
[ "$PKG" = "vn.mamba.mamba_app" ] || { echo "refusing: package is $PKG, expected vn.mamba.mamba_app"; exit 2; }
echo "$VER" | grep -qE '^[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}$' || { echo "refusing: versionName '$VER' is not x.y.z"; exit 2; }
SHA=$(shasum -a 256 "$APK" | cut -d' ' -f1)
SIZE=$(stat -f%z "$APK")
NAME="MAMBA-$VER.apk"
URL="$SITE/downloads/$NAME"
echo "APK        : $APK"
echo "Package    : $PKG  version $VER (build $CODE)  size $((SIZE/1024/1024)) MB"
echo "SHA-256    : $SHA"
echo "Will upload: $HOST (container $CT) -> /opt/xs-maxmin/web/downloads/$NAME  (keep newest 3)"
echo "Public URL : $URL"
echo "Will set   : app_latest_version=$VER  app_download_url=$URL  app_release_notes=${NOTES:-<unchanged>}"
if [ "$YES" -ne 1 ]; then
  echo
  echo "DRY RUN: nothing was sent. Re-run with --yes ONLY after the owner has approved publishing."
  exit 0
fi
echo "--> publishing"
scp -q -o BatchMode=yes "$APK" "$HOST:/tmp/$NAME"
ssh -o BatchMode=yes "$HOST" "pct exec $CT -- mkdir -p /opt/xs-maxmin/web/downloads && pct push $CT /tmp/$NAME /opt/xs-maxmin/web/downloads/$NAME --perms 644 && rm -f /tmp/$NAME && pct exec $CT -- bash -c 'cd /opt/xs-maxmin/web/downloads && ls -1t MAMBA-*.apk | tail -n +4 | xargs -r rm -f'"
TMP=$(mktemp)
curl -fsSL "$URL" -o "$TMP"
GOT=$(shasum -a 256 "$TMP" | cut -d' ' -f1); rm -f "$TMP"
if [ "$GOT" != "$SHA" ]; then echo "!! downloaded file differs from the local APK (sha $GOT); NOT switching the update card on"; exit 1; fi
echo "downloaded back OK, sha matches"
SQL="insert into settings(key,value) values('app_latest_version','$VER') on conflict(key) do update set value=excluded.value; insert into settings(key,value) values('app_download_url','$URL') on conflict(key) do update set value=excluded.value;"
if [ -n "$NOTES" ]; then
  ESC=$(printf %s "$NOTES" | sed "s/'/''/g")
  SQL="$SQL insert into settings(key,value) values('app_release_notes','$ESC') on conflict(key) do update set value=excluded.value;"
fi
printf %s "$SQL" | ssh -o BatchMode=yes "$HOST" "pct exec $CT -- sqlite3 /opt/xs-maxmin/backend/build/data/xoso.db"
curl -fsS "$SITE/api/app-version"; echo
echo "published $NAME"
