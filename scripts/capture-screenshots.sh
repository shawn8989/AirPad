#!/usr/bin/env bash
# Capture App Store screenshots from the iOS Simulator.
#
# RUN THIS ON THE MAC (needs Xcode). AirBridge must be running on the same Mac
# and already paired, because the Simulator shares the host's network — that is
# what lets the app actually connect and show real content instead of an empty
# "Looking for your Mac" screen.
#
# Hand Mouse and AirPop CANNOT be captured here: the Simulator has no camera,
# so Vision never receives a frame. Shoot those two on a real device.
#
#   ./scripts/capture-screenshots.sh              # build, install, launch
#   ./scripts/capture-screenshots.sh shot 01-trackpad
#   ./scripts/capture-screenshots.sh video demo
#
set -euo pipefail

DEVICE="${DEVICE:-iPhone 16 Pro Max}"   # 6.9" — 1320x2868
BUNDLE_ID="com.SOTechy.AirPad"
OUT="docs/screenshots/raw"
DERIVED=".build-sim"

mkdir -p "$OUT"

boot() {
  local udid
  udid=$(xcrun simctl list devices available | grep -m1 "$DEVICE (" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
  if [ -z "$udid" ]; then
    echo "No available simulator named '$DEVICE'." >&2
    echo "Pick one from:" >&2
    xcrun simctl list devices available | grep -E "iPhone|iPad" >&2
    exit 1
  fi
  xcrun simctl boot "$udid" 2>/dev/null || true
  open -a Simulator
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
  # A clean, consistent status bar — Apple's own marketing convention, and it
  # keeps a real battery percentage or carrier name out of your store listing.
  xcrun simctl status_bar "$udid" override \
    --time "9:41" --batteryState charged --batteryLevel 100 \
    --cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3 \
    --operatorName "" 2>/dev/null || true
  echo "$udid"
}

case "${1:-run}" in
  run)
    UDID=$(boot)
    echo "Building for the simulator…"
    xcodebuild -project AirPad.xcodeproj -scheme AirPad \
      -sdk iphonesimulator -configuration Debug \
      -derivedDataPath "$DERIVED" -quiet build
    APP=$(find "$DERIVED/Build/Products" -name "AirPad.app" -maxdepth 3 | head -1)
    xcrun simctl install "$UDID" "$APP"
    xcrun simctl launch "$UDID" "$BUNDLE_ID"
    echo
    echo "Running. Now capture each screen:"
    echo "  ./scripts/capture-screenshots.sh shot 01-trackpad"
    ;;

  shot)
    NAME="${2:-shot-$(date +%s)}"
    xcrun simctl io booted screenshot --type=png "$OUT/$NAME.png"
    echo "Saved $OUT/$NAME.png"
    ;;

  video)
    NAME="${2:-demo}"
    echo "Recording — press Ctrl-C to stop."
    xcrun simctl io booted recordVideo --codec h264 --mask ignore "$OUT/$NAME.mov"
    ;;

  reset-statusbar)
    xcrun simctl status_bar booted clear
    ;;

  *)
    echo "Usage: $0 [run|shot NAME|video NAME|reset-statusbar]" >&2
    exit 1
    ;;
esac
