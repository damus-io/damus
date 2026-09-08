#!/bin/bash
# Archive damus and upload it to TestFlight from this machine, with no GUI.
#
# This is the local path. It needs a distribution signing identity, which
# -allowProvisioningUpdates will create as a cloud-managed certificate given an
# App Store Connect API key. See docs/HEADLESS_RELEASE.md for the one-time
# setup and for why the Xcode Cloud path is usually the better choice.
#
#   ASC_KEY_ID=ABC123DEF4 ASC_ISSUER_ID=<uuid> \
#     ./devtools/release/testflight-upload.sh --internal-only
#
# By default it stops after exporting the .ipa locally. Uploading requires
# --upload, because an upload permanently burns a build number in App Store
# Connect and cannot be undone.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: testflight-upload.sh [options]

  --upload            actually upload to App Store Connect (default: export only)
  --internal-only     mark the build as internal-TestFlight-only (recommended
                      for anything that is not a real release candidate)
  --archive-only      stop after archiving
  --manage-version    let App Store Connect pick the build number on upload
  --out DIR           working directory (default: build/release)
  -h, --help          show this

Environment:
  ASC_KEY_ID      App Store Connect API key id
  ASC_ISSUER_ID   App Store Connect issuer id
  ASC_KEY_PATH    path to AuthKey_<ASC_KEY_ID>.p8
                  (default ~/.appstoreconnect/private_keys/AuthKey_<id>.p8)
USAGE
}

DO_UPLOAD=no
INTERNAL_ONLY=no
ARCHIVE_ONLY=no
MANAGE_VERSION=false
OUT_DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --upload) DO_UPLOAD=yes ;;
    --internal-only) INTERNAL_ONLY=yes ;;
    --archive-only) ARCHIVE_ONLY=yes ;;
    --manage-version) MANAGE_VERSION=true ;;
    --out) shift; OUT_DIR="${1:?--out needs a directory}" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown option '$1'" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
OUT_DIR=${OUT_DIR:-"$REPO_ROOT/build/release"}
ARCHIVE_PATH="$OUT_DIR/damus.xcarchive"
EXPORT_PATH="$OUT_DIR/export"
EXPORT_OPTIONS="$OUT_DIR/ExportOptions.plist"

ASC_KEY_PATH=${ASC_KEY_PATH:-"$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID:-unset}.p8"}

if [ -z "${ASC_KEY_ID:-}" ] || [ -z "${ASC_ISSUER_ID:-}" ]; then
  echo "error: set ASC_KEY_ID and ASC_ISSUER_ID (see docs/HEADLESS_RELEASE.md)" >&2
  exit 1
fi
if [ ! -f "$ASC_KEY_PATH" ]; then
  echo "error: no App Store Connect private key at $ASC_KEY_PATH" >&2
  exit 1
fi

# The nix dev shell exports a toolchain that xcodebuild cannot use: it points
# SDKROOT and friends at a nix apple-sdk and puts nix's clang wrapper first on
# PATH, which makes the C targets fail on '-index-store-path'. Run xcodebuild
# with those scrubbed rather than changing nix-managed global state with
# xcode-select.
xcb() {
  env -u SDKROOT -u SDKROOT_FOR_BUILD -u NIX_CFLAGS_COMPILE -u NIX_LDFLAGS \
      -u NIX_CC -u NIX_CC_WRAPPER_TARGET_HOST_arm64_apple_darwin \
      -u NIX_HARDENING_ENABLE -u NIX_ENFORCE_NO_NATIVE -u NIX_DONT_SET_RPATH \
      -u NIX_IGNORE_LD_THROUGH_GCC -u NIX_APPLE_SDK_VERSION_FOR_BUILD \
      -u LD -u CC -u CXX -u LD_LIBRARY_PATH -u LIBRARY_PATH -u CPATH \
      DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
      PATH=/Applications/Xcode.app/Contents/Developer/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin \
      xcodebuild "$@"
}

AUTH=(
  -allowProvisioningUpdates
  -authenticationKeyPath "$ASC_KEY_PATH"
  -authenticationKeyID "$ASC_KEY_ID"
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"
)

mkdir -p "$OUT_DIR"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

echo "==> archiving $(git -C "$REPO_ROOT" rev-parse --short HEAD) to $ARCHIVE_PATH"
xcb -project "$REPO_ROOT/damus.xcodeproj" \
    -scheme damus \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    "${AUTH[@]}" \
    archive

if [ "$ARCHIVE_ONLY" = yes ]; then
  echo "==> archived; stopping before export as asked"
  exit 0
fi

if [ "$DO_UPLOAD" = yes ]; then
  DESTINATION=upload
else
  DESTINATION=export
fi
if [ "$INTERNAL_ONLY" = yes ]; then
  INTERNAL_FLAG="<true/>"
else
  INTERNAL_FLAG="<false/>"
fi

cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>$DESTINATION</string>
	<key>teamID</key>
	<string>XK7H4JAB3D</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>uploadSymbols</key>
	<true/>
	<key>manageAppVersionAndBuildNumber</key>
	<$MANAGE_VERSION/>
	<key>testFlightInternalTestingOnly</key>
	$INTERNAL_FLAG
</dict>
</plist>
PLIST

if [ "$DO_UPLOAD" = yes ]; then
  echo "==> exporting AND UPLOADING to App Store Connect"
  echo "    this burns a build number permanently"
else
  echo "==> exporting locally to $EXPORT_PATH (not uploading)"
fi

xcb -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    "${AUTH[@]}"

echo "==> done"
