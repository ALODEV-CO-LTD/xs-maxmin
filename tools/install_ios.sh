#!/bin/bash
# Install the built app on an iPhone IN PLACE (an update, not a reinstall): the old copy is NOT uninstalled, so the chat
# history, the encryption key and the offline queue on the phone are kept. (`flutter install` uninstalls first and wipes them.)
#   tools/install_ios.sh <device id>        e.g. 00008101-0019496E2260001E  (see `xcrun devicectl list devices`)
set -e
DEVICE=${1:?usage: tools/install_ios.sh <device id>}
cd "$(dirname "$0")/../app"
flutter build ios --release
xcrun devicectl device install app --device "$DEVICE" build/ios/iphoneos/Runner.app
