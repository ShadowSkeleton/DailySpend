#!/bin/sh
# Builds "DailySpend Test" and installs it beside the App Store app on a
# connected iPhone. See DeviceTest.xcconfig for what keeps it isolated.
#
# Usage: scripts/device-test/install-on-device.sh <device-udid> [Debug|Release]
# List devices with: xcrun devicectl list devices
set -eu

DEVICE="${1:?Pass the device UDID from 'xcrun devicectl list devices'}"
CONFIGURATION="${2:-Debug}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DERIVED="${TMPDIR:-/tmp}/dailyspend-device-test"

cd "$ROOT"
# Always clean: an incremental build can keep compile flags from an earlier
# configuration, and a build without DAILYSPEND_DEVICE_TEST crashes at launch
# because it has no iCloud entitlement.
xcodebuild clean build \
  -project DailySpend.xcodeproj \
  -scheme DailySpend \
  -configuration "$CONFIGURATION" \
  -destination "id=$DEVICE" \
  -derivedDataPath "$DERIVED" \
  -xcconfig scripts/device-test/DeviceTest.xcconfig \
  -allowProvisioningUpdates \
  -quiet

APP="$DERIVED/Build/Products/$CONFIGURATION-iphoneos/DailySpend.app"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
if [ "$BUNDLE_ID" = "com.jackson.LoveLedger" ]; then
  echo "Refusing to install: this build has the App Store bundle ID." >&2
  exit 1
fi

xcrun devicectl device install app --device "$DEVICE" "$APP"
echo "Installed $BUNDLE_ID as \"DailySpend Test\"."
