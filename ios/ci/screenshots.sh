#!/bin/bash
# Runs the built app in the iPhone Simulator and saves screenshots of its screens.
#
#   SCREENS        the demo screens to capture on a current, full-size iPhone
#                  (see DemoMode in the app for the names)
#   SMALL_SCREENS  demo screens to capture again on the smallest iPhone available,
#                  to check that nothing is squeezed off a short screen
#   WAIT           seconds to let each screen settle before the picture is taken
#
# It also checks that the 3D scene really was drawn on the screens that show it,
# and fails if any of them came out blank.
set -euo pipefail

BUNDLE_ID=com.huzkeymil.spade
SCREENS=${SCREENS:-launch}
SMALL_SCREENS=${SMALL_SCREENS:-}
WAIT=${WAIT:-7}
HERE=$(cd "$(dirname "$0")" && pwd)
# The screens where the scene is in full view (the others have a sheet over it).
SCENE_SCREENS=" launch roles quests hero satchel feats dig level smooth family childboard "
FAILED=0

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

# Makes a small iPhone simulator if none is installed, and prints its id.
make_small_device() {
  local runtime
  runtime=$(xcrun simctl list runtimes available -j | python3 -c '
import json, sys
found = [r for r in json.load(sys.stdin)["runtimes"] if "iOS" in r["name"]]
found.sort(key=lambda r: [int(p) for p in r["version"].split(".")])
print(found[-1]["identifier"] if found else "")')
  [ -n "$runtime" ] || return 0
  # Try the smallest models first; not every iOS version supports every model.
  xcrun simctl list devicetypes -j | python3 -c '
import json, sys
names = [t for t in json.load(sys.stdin)["devicetypes"] if "iPhone SE" in t["name"] or "mini" in t["name"]]
for t in sorted(names, key=lambda t: t["name"], reverse=True):
    print(t["identifier"])' | while read -r kind; do
    if id=$(xcrun simctl create "Spade small" "$kind" "$runtime" 2>/dev/null); then
      echo "simulator: made a ${kind##*.}" >&2
      echo "$id"
      break
    fi
  done
}

# A family link from Tess, as her phone would send it to the demo parent ("-demo openlink").
# Opening it checks that spade:// links are registered to the app: iOS asks
# "Open in Spade?" first, which is the screenshot. ("-demo report" shows what
# the app does with the link once it is opened.)
openlink_payload() {
  python3 -c '
import base64, json
note = {"v": 1, "child": {"familyId": "fam_demo", "childId": "kid_tess", "childName": "Tess", "done": [
    {"key": "2026-01-01:fq_dishes", "questId": "fq_dishes", "title": "Do the dishes after dinner",
     "allowance": 100, "doneAt": 0, "status": "waiting"}]}}
raw = json.dumps(note, separators=(",", ":")).encode()
print(base64.urlsafe_b64encode(raw).decode().rstrip("="))'
}

# How much of the scene area of a screenshot is drawn on, as a percentage.
scene_drawn() {
  python3 "$HERE/lit.py" "$1" 2>/dev/null || echo 0
}

# capture <device id> <file prefix> <screen names...>
capture() {
  local device=$1 prefix=$2
  shift 2
  xcrun simctl boot "$device" 2>/dev/null || true
  xcrun simctl bootstatus "$device" -b >/dev/null
  xcrun simctl install "$device" "$APP"
  for name in "$@"; do
    local file="shots/$prefix$name.png" note=""
    xcrun simctl terminate "$device" "$BUNDLE_ID" >/dev/null 2>&1 || true
    xcrun simctl launch "$device" "$BUNDLE_ID" -demo "$name" >/dev/null
    if [ "$name" = openlink ]; then
      sleep 5
      xcrun simctl openurl "$device" "spade://family#$(openlink_payload)"
    fi
    sleep "$WAIT"
    xcrun simctl io "$device" screenshot "$file" >/dev/null 2>&1
    if [[ "$SCENE_SCREENS" == *" $name "* ]]; then
      local drawn
      drawn=$(scene_drawn "$file")
      if [ "$drawn" -lt 50 ]; then
        # A cold simulator can be slow to draw its first frame. Give it one more chance.
        sleep 12
        xcrun simctl io "$device" screenshot "$file" >/dev/null 2>&1
        drawn=$(scene_drawn "$file")
        note=", on the second look"
      fi
      note=" (scene $drawn% drawn$note)"
      if [ "$drawn" -lt 50 ]; then
        echo "FAILED: the 3D scene did not appear on '$prefix$name'."
        FAILED=1
      fi
    fi
    # A smaller copy, for sharing.
    sips -Z 1300 -s format jpeg -s formatOptions 70 "$file" --out "shots/$prefix$name.jpg" >/dev/null
    local running
    running=$(xcrun simctl spawn "$device" launchctl list 2>/dev/null || true)
    if grep -q "$BUNDLE_ID" <<<"$running"; then
      echo "captured $prefix$name$note"
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
  [ -n "$SMALL" ] || SMALL=$(make_small_device || true)
  if [ -n "$SMALL" ]; then
    # shellcheck disable=SC2086
    capture "$SMALL" "small-" $SMALL_SCREENS
  else
    echo "No small iPhone simulator could be set up, so the small-screen check was skipped."
  fi
fi

exit "$FAILED"
