#!/bin/bash
# Runs the built app in the iPhone Simulator and saves screenshots of its main screens.
#
#   SCREENS  the demo screens to capture (see DemoMode in the app)
#   PRINT    which of them to also print into the log as small base64 JPEGs,
#            for reading the result without downloading the artifact
set -euo pipefail

BUNDLE_ID=com.huzkeymil.spade
SCREENS=${SCREENS:-launch}
PRINT=${PRINT:-}
WAIT=${WAIT:-8}

APP=$(find build/Build/Products -maxdepth 2 -name "Spade.app" | head -1)
[ -n "$APP" ] || { echo "Spade.app was not found in build/"; exit 1; }

# Pick the newest available iPhone that isn't an SE.
DEVICE=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
runtimes = json.load(sys.stdin)["devices"]
phones = []
for runtime in sorted(runtimes, reverse=True):
    if "iOS" not in runtime:
        continue
    for device in runtimes[runtime]:
        name = device["name"]
        if name.startswith("iPhone") and "SE" not in name:
            phones.append((runtime, name, device["udid"]))
phones.sort(key=lambda p: (p[0], "Pro" not in p[1], p[1]), reverse=True)
if not phones:
    sys.exit("no iPhone simulator available")
print(phones[0][2])
sys.stderr.write("simulator: %s on %s\n" % (phones[0][1], phones[0][0].split(".")[-1]))
')

xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b >/dev/null
xcrun simctl install "$DEVICE" "$APP"
mkdir -p shots

for name in $SCREENS; do
  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl launch "$DEVICE" "$BUNDLE_ID" -demo "$name" >/dev/null
  sleep "$WAIT"
  xcrun simctl io "$DEVICE" screenshot "shots/$name.png" >/dev/null 2>&1
  if xcrun simctl spawn "$DEVICE" launchctl list | grep -q "$BUNDLE_ID"; then
    echo "captured $name"
  else
    echo "WARNING: the app was not running after '$name'. It may have crashed."
  fi
done

for name in $PRINT; do
  sips -Z 560 -s format jpeg -s formatOptions 42 "shots/$name.png" --out "shots/$name.small.jpg" >/dev/null
  echo "BEGIN_IMAGE $name"
  base64 -b 76 -i "shots/$name.small.jpg"
  echo "END_IMAGE $name"
done

echo "--- app log (errors and faults) ---"
xcrun simctl spawn "$DEVICE" log show --last 4m --style compact \
  --predicate 'process == "Spade" AND (messageType == error OR messageType == fault)' 2>/dev/null | tail -40 || true
