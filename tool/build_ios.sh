#!/bin/bash
set -euo pipefail

version_args=(
  "--build-name=$IOS_VERSION"
  "--build-number=$IOS_BUILD_NUMBER"
  "--dart-define=THMR_CLIENT_VERSION=$CLIENT_VERSION"
)

if [[ ${1:-} == --testflight ]]; then
  flutter build ipa --release --no-pub "${version_args[@]}" \
    --export-options-plist="$RUNNER_TEMP/ios-export-options.plist"
  app=build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app
  codesign --verify --deep --strict "$app"
  test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Info.plist")" = "$IOS_BUNDLE_ID"
else
  flutter build ios --release --no-codesign --no-pub "${version_args[@]}"
  app=build/ios/iphoneos/Runner.app
fi

plist="$app/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$plist")" = "$IOS_VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$plist")" = "$IOS_BUILD_NUMBER"
test "$(/usr/libexec/PlistBuddy -c 'Print ITSAppUsesNonExemptEncryption' "$plist")" = false
lipo "$app/Frameworks/Mpv.framework/Mpv" -verify_arch arm64
