#!/bin/bash
# Runs the built app in the iPhone Simulator and saves screenshots of its screens.
#
#   SCREENS        the demo screens to capture on a current, full-size iPhone
#                  (see DemoMode in the app for the names)
#   SMALL_SCREENS  demo screens to capture again on the smallest iPhone available,
#                  to check that nothing is squeezed off a short screen
#   WAIT           seconds to let each screen settle before the picture is taken
set -euo pipefail

BUNDLE_ID=com.huzkeymil.spade
SCREENS=${SCREENS:-launch}
SMALL_SCREENS=${SMALL_SCREENS:-}
WAIT=${WAIT:-7}

APP=$(find build/Build/Products -maxdepth 2 -name "Spade.app" | head -1)
[ -n "$APP" ] || { echo "Spade.app was not found in build/"; exit 1; }
mkdir -p shots

# Prints the id of a simulator: "big" picks the newest full-size iPhone,
# "small" picks an iPhone SE or mini if one is installed.
pick_device() {
  xcrun simctl list devices available -j | python3 -c '
import json, sys
want = sys.argv[1]
runtimes = json.load(sys.stdin)["devices"]
phones = []
for runtime in runtimes:
    if "iOS" not in runtime:
        continue
    for device in runtimes[runtime]:
        name = device["name"]
        if not name.startswith("iPhone"):
            continue
        small = "SE" in name or "mini" in name
        if small == (want == "small"):
            phones.append((runtime, "Pro" not in name, name, device["udid"]))
if not phones:
    sys.exit(0)
phones.sort(reverse=True)
runtime, _, name, udid = phones[0]
sys.stderr.write("simulator: %s on %s\n" % (name, runtime.split(".")[-1]))
print(udid)
' "$1"
}

# capture <device id> <file prefix> <screen names...>
capture() {
  local device=$1 prefix=$2
  shift 2
  xcrun simctl boot "$device" 2>/dev/null || true
  xcrun simctl bootstatus "$device" -b >/dev/null
  xcrun simctl install "$device" "$APP"
  for name in "$@"; do
    xcrun simctl terminate "$device" "$BUNDLE_ID" >/dev/null 2>&1 || true
    xcrun simctl launch "$device" "$BUNDLE_ID" -demo "$name" >/dev/null
    sleep "$WAIT"
    xcrun simctl io "$device" screenshot "shots/$prefix$name.png" >/dev/null 2>&1
    # A smaller copy, for sharing.
    sips -Z 1300 -s format jpeg -s formatOptions 70 "shots/$prefix$name.png" --out "shots/$prefix$name.jpg" >/dev/null
    local running
    running=$(xcrun simctl spawn "$device" launchctl list 2>/dev/null || true)
    if grep -q "$BUNDLE_ID" <<<"$running"; then
      echo "captured $prefix$name"
    else
      echo "WARNING: the app was not running after '$prefix$name'. It may have crashed."
    fi
  done
  echo "--- app log on this simulator (errors and faults) ---"
  # Reading the simulator's log can be slow, so it gets one minute at most.
  perl -e 'alarm shift; exec @ARGV' 60 xcrun simctl spawn "$device" log show --last 3m --style compact \
    --predicate 'process == "Spade" AND (messageType == error OR messageType == fault)' 2>/dev/null \
    | grep -v -E "UIFocus|app_launch_measurement|^Timestamp" | cut -c1-260 | awk '{ $1=""; $2=""; $4=""; print }' | sort | uniq -c | sort -rn | head -12 || true
  xcrun simctl shutdown "$device" >/dev/null 2>&1 || true
}

BIG=$(pick_device big)
[ -n "$BIG" ] || { echo "no iPhone simulator is available"; exit 1; }
# shellcheck disable=SC2086
capture "$BIG" "" $SCREENS

if [ -n "$SMALL_SCREENS" ]; then
  SMALL=$(pick_device small)
  if [ -n "$SMALL" ]; then
    # shellcheck disable=SC2086
    capture "$SMALL" "small-" $SMALL_SCREENS
  else
    echo "No small iPhone simulator is installed, so the small-screen check was skipped."
  fi
fi
