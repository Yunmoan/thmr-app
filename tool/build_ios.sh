#!/bin/bash
set -euo pipefail

flutter build ios --release --no-codesign --no-pub \
  --build-name="$IOS_VERSION" --build-number="$IOS_BUILD_NUMBER" \
  --dart-define="THMR_CLIENT_VERSION=$CLIENT_VERSION"

app=build/ios/iphoneos/Runner.app
plist="$app/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$plist")" = "$IOS_VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$plist")" = "$IOS_BUILD_NUMBER"
test "$(/usr/libexec/PlistBuddy -c 'Print ITSAppUsesNonExemptEncryption' "$plist")" = false
lipo -verify_arch arm64 "$app/Frameworks/Mpv.framework/Mpv"
