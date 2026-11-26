#!/usr/bin/env bash
# Builds Spade for the App Store, signs it with Apple's cloud signing and uploads it to
# App Store Connect. Run by .github/workflows/testflight.yml on GitHub's Xcode 27 Mac.
#
#   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8   an App Store Connect API key with Admin access
#   UPLOAD=yes                              send the signed build to App Store Connect
#
# Without UPLOAD=yes it stops after signing. Without the key it only builds the app and
# checks its iCloud permissions are in place (a rehearsal for pull requests).
set -euo pipefail

BUNDLE_ID=com.huzkeymil.spade
WORK="${RUNNER_TEMP:-$(mktemp -d)}/testflight"
ARCHIVE="$WORK/Spade.xcarchive"
APP="$ARCHIVE/Products/Applications/Spade.app"
rm -rf "$WORK" && mkdir -p "$WORK"

# Anyone can read this log on GitHub, so the names Apple prints next to certificates
# and teams ("Apple Distribution: First Last (TEAMID)") and email addresses are hidden.
scrub() {
  sed -E \
    -e 's/((Apple|iPhone|iOS|Cloud Managed)[A-Za-z ]*(Distribution|Development|Developer)): [^(]*\(/\1: [name hidden] (/g' \
    -e "s/([Tt]eam) \"[^\"]*\"/\1 \"[hidden]\"/g" \
    -e "s/([Tt]eam) '[^']*'/\1 '[hidden]'/g" \
    -e 's/[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}/[email hidden]/g' \
    -e "s|$PWD/||g"
}

# The useful lines of a long log (those matching $2), without repeats.
problems() {
  grep -iE "$2" "$1" | scrub | awk '!seen[$0]++' | cut -c1-500 | head -"${3:-80}" || true
}
BUILD_PROBLEMS=": (error|note): "
SIGN_PROBLEMS="error|warning: .*(sign|profile|entitlement)|failed|upload"

step() { echo "::group::$1"; }
done_step() { echo "::endgroup::"; }

# --- The key -------------------------------------------------------------------------
missing=()
for name in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_P8; do
  [[ -n "${!name:-}" ]] || missing+=("$name")
done
if [[ ${#missing[@]} -eq 3 && "${UPLOAD:-}" != yes ]]; then
  HAVE_KEY=no
  echo "No App Store Connect key in this run, so this is a rehearsal: build and check only."
elif [[ ${#missing[@]} -gt 0 ]]; then
  echo "::error::Missing repository secrets: ${missing[*]}. Add them under Settings → Secrets and variables → Actions (ios/README.md, \"Sending builds to TestFlight from GitHub\")."
  exit 1
else
  HAVE_KEY=yes
  ASC_KEY_ID=$(printf %s "$ASC_KEY_ID" | tr -d '[:space:]')
  ASC_ISSUER_ID=$(printf %s "$ASC_ISSUER_ID" | tr -d '[:space:]')
  export ASC_KEY_ID ASC_ISSUER_ID
  KEY_FILE="$WORK/AuthKey_$ASC_KEY_ID.p8"
  # shellcheck disable=SC2153  # ASC_KEY_P8 comes from the workflow's secrets
  (umask 077 && printf '%s\n' "$ASC_KEY_P8" | tr -d '\r' > "$KEY_FILE")
  trap 'rm -f "$KEY_FILE"' EXIT
  grep -q "BEGIN PRIVATE KEY" "$KEY_FILE" || {
    echo "::error::ASC_KEY_P8 should be the whole .p8 file, including the -----BEGIN PRIVATE KEY----- and -----END PRIVATE KEY----- lines."
    exit 1
  }

  step "Check the key with App Store Connect"
  TEAM_ID=$(python3 ios/ci/asc_team.py "$KEY_FILE" "$BUNDLE_ID")
  echo "::add-mask::$TEAM_ID"
  echo "Apple accepted the key and found $BUNDLE_ID."
  done_step
fi

# --- Build ---------------------------------------------------------------------------
BUILD_NUMBER=$(date -u +%y%m%d%H%M)   # always higher than the last build, like Codemagic's
VERSION=$(grep -m1 -oE "MARKETING_VERSION = [0-9.]+" ios/Spade.xcodeproj/project.pbxproj | awk '{print $3}')
step "Build Spade $VERSION ($BUILD_NUMBER)"
xcodebuild -version
# Built unsigned, then signed below: GitHub's Mac has no certificates of its own.
xcodebuild -project ios/Spade.xcodeproj -scheme Spade -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" archive > "$WORK/archive.log" 2>&1 || {
  done_step
  problems "$WORK/archive.log" "$BUILD_PROBLEMS" 120
  echo "::error::The app didn't build. The lines above say why."
  exit 1
}
echo "Built."
done_step

# --- iCloud permissions --------------------------------------------------------------
# An unsigned app carries no permissions (entitlements). Apple's signing copies them from
# the app it is given, so the app is first signed "ad hoc" with Spade's own list. Without
# this, the TestFlight build would have no iCloud and families couldn't sync.
step "Add Spade's iCloud permissions"
ENTITLEMENTS="$WORK/Spade.entitlements"
# shellcheck disable=SC2016  # $(APS_ENVIRONMENT) is Xcode's, not the shell's
sed 's/$(APS_ENVIRONMENT)/production/' ios/Config/Spade.entitlements > "$ENTITLEMENTS"
# shellcheck disable=SC2016
if grep -q '\$(' "$ENTITLEMENTS"; then
  echo "::error::ios/Config/Spade.entitlements uses a setting this script doesn't fill in:"
  # shellcheck disable=SC2016
  grep '\$(' "$ENTITLEMENTS"
  exit 1
fi
# Anything with its own code inside the app is signed first, innermost first.
while IFS= read -r -d '' inner; do
  codesign --force --sign - --timestamp=none "$inner"
done < <(find "$APP" -mindepth 1 -depth \( -name "*.framework" -o -name "*.appex" -o -name "*.dylib" \) -print0)
codesign --force --sign - --timestamp=none --generate-entitlement-der \
  --entitlements "$ENTITLEMENTS" "$APP"
codesign -d --entitlements - --xml "$APP" 2>/dev/null > "$WORK/check.plist"
for want in aps-environment com.apple.developer.icloud-container-identifiers com.apple.developer.icloud-services; do
  grep -q "<key>$want</key>" "$WORK/check.plist" || {
    echo "::error::The app is missing the $want permission."
    exit 1
  }
done
plutil -p "$WORK/check.plist"
done_step

if [[ "$HAVE_KEY" == no ]]; then
  echo "Rehearsal OK: Spade $VERSION builds and carries its iCloud permissions."
  echo "Add the three secrets to sign and upload (ios/README.md)."
  exit 0
fi

# --- Sign, then upload ---------------------------------------------------------------
DESTINATION="export"
[[ "${UPLOAD:-}" == yes ]] && DESTINATION="upload"
cat > "$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$DESTINATION</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

if [[ "$DESTINATION" == upload ]]; then
  step "Sign with Apple's cloud signing and upload to App Store Connect"
else
  step "Sign with Apple's cloud signing (no upload in a rehearsal)"
fi
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$WORK/export" \
  -exportOptionsPlist "$WORK/ExportOptions.plist" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_FILE" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" > "$WORK/export.log" 2>&1 || {
  done_step
  problems "$WORK/export.log" "$SIGN_PROBLEMS" 120
  echo
  if grep -qiE "permission|not allowed|role|cloud signing|cloud-managed|cloud managed" "$WORK/export.log"; then
    echo "::error::Apple wouldn't let this key sign. Cloud signing needs a key with Admin access (ios/README.md, step G1)."
  elif grep -qiE "No suitable application records" "$WORK/export.log"; then
    echo "::error::App Store Connect has no app record for $BUNDLE_ID (ios/README.md, step 3)."
  elif grep -qiE "bundle version must be higher|CFBundleVersion.*(higher|already)" "$WORK/export.log"; then
    echo "::error::A build with a later build number is already uploaded. Press the button again."
  elif grep -qiE "icloud|aps-environment|entitlement" "$WORK/export.log"; then
    echo "::error::Apple's profile doesn't match Spade's iCloud permissions. Check iCloud and Push Notifications are ticked on the App ID (ios/README.md, \"Turning on iCloud\")."
  else
    echo "::error::Signing or uploading failed. The lines above say why."
  fi
  exit 1
}
problems "$WORK/export.log" "$SIGN_PROBLEMS" 30
done_step

if [[ "$DESTINATION" == upload ]]; then
  {
    echo "### Spade $VERSION ($BUILD_NUMBER) is on its way to TestFlight"
    echo
    echo "Apple checks each build before it appears in TestFlight. That usually takes 10 to 30 minutes."
  } >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
  echo "Uploaded Spade $VERSION ($BUILD_NUMBER). It appears in TestFlight once Apple has processed it."
else
  IPA=$(find "$WORK/export" -name "*.ipa" | head -1)
  [[ -n "$IPA" ]] || { echo "::error::Signing finished but made no .ipa file."; exit 1; }
  (cd "$WORK" && unzip -q -o "$IPA" "Payload/*")
  codesign -d --entitlements - --xml "$WORK/Payload/Spade.app" 2>/dev/null | plutil -p - | scrub
  echo "Rehearsal OK: Spade $VERSION signs. Press the button in the Actions tab to upload."
fi
