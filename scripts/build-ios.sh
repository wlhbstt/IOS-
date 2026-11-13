#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
if [ "$(uname -s)" != Darwin ]; then
    echo "iOS compilation requires macOS and Xcode. Use GitHub Actions from Windows." >&2
    exit 1
fi
for tool in xcodebuild xcrun xcodegen swift ditto unzip; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
done

xcodebuild -version
sdk_version="$(xcrun --sdk iphoneos --show-sdk-version)"
if ! awk -v sdk="$sdk_version" 'BEGIN { exit !(sdk + 0 >= 18) }'; then
    echo "An iPhoneOS SDK >= 18.0 is required; selected SDK: $sdk_version" >&2
    exit 1
fi
echo "Selected iPhoneOS SDK: $sdk_version; deployment target: iOS 18.0"

mkdir -p "$repo_dir/build"
output="$repo_dir/build/PhotoCleaner-unsigned.ipa"
rm -f "$output"
run_dir="$(mktemp -d "$repo_dir/build/ios.XXXXXX")"
trap 'if [ -d "$run_dir/Tests.xcresult" ]; then mkdir -p "$repo_dir/build/previews"; xcrun simctl spawn "$simulator_id" log show --last 6m --style compact --predicate '\''subsystem BEGINSWITH "com.apple.photos"'\'' > "$repo_dir/build/previews/photokit.log" 2>&1 || true; xcrun xcresulttool export attachments --path "$run_dir/Tests.xcresult" --output-path "$repo_dir/build/previews" || true; fi; rm -rf "$run_dir"' EXIT

echo "Running PhotoCleanerCore tests"
swift test
echo "Generating Xcode project"
xcodegen generate --spec project.yml
echo "Testing local index migration and feature storage on an iOS simulator"
simulator_id="$(xcrun simctl list devices available -j | node -e '
let input = "";
process.stdin.on("data", chunk => input += chunk);
process.stdin.on("end", () => {
    const devices = Object.entries(JSON.parse(input).devices)
        .filter(([runtime]) => runtime.includes("iOS"))
        .flatMap(([, devices]) => devices);
    const phone = devices.find(device => device.isAvailable && device.name.includes("iPhone"));
    if (!phone) process.exit(1);
    process.stdout.write(phone.udid);
});')"
xcrun simctl boot "$simulator_id" || true
simulator_args=(-project PhotoCleaner.xcodeproj -scheme PhotoCleaner -configuration Debug
    -destination "platform=iOS Simulator,id=$simulator_id" -derivedDataPath "$run_dir/Simulator"
    CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES)
xcodebuild "${simulator_args[@]}" -parallel-testing-enabled NO build-for-testing
xcrun simctl bootstatus "$simulator_id" -b
xcrun simctl install "$simulator_id" "$run_dir/Simulator/Build/Products/Debug-iphonesimulator/PhotoCleaner.app"
xcrun simctl privacy "$simulator_id" grant photos com.localphototools.PhotoCleaner
for photo in photo-1500530855697-b586d89ba3ee photo-1470071459604-3b5ec3a7fe05 photo-1441974231531-c6227db76b6e; do
    curl -fL --connect-timeout 15 --max-time 45 \
        "https://images.unsplash.com/$photo?w=640&q=75" -o "$run_dir/$photo.jpg"
    xcrun simctl addmedia "$simulator_id" "$run_dir/$photo.jpg"
done
curl -fL --connect-timeout 15 --max-time 60 \
    'https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=3200&q=95' -o "$run_dir/compression-fixture.jpg"
xcrun simctl addmedia "$simulator_id" "$run_dir/compression-fixture.jpg"
echo "Verifying simulator fixture resources"
find "$HOME/Library/Developer/CoreSimulator/Devices/$simulator_id/data/Media/DCIM" -type f -exec ls -l {} +
xcodebuild "${simulator_args[@]}" \
    -parallel-testing-enabled NO -destination-timeout 120 \
    -test-timeouts-enabled YES -maximum-test-execution-time-allowance 240 \
    -resultBundlePath "$run_dir/Tests.xcresult" \
    test-without-building
echo "Building Release for a generic iOS device without signing"
xcodebuild -project PhotoCleaner.xcodeproj -scheme PhotoCleaner \
    -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
    -derivedDataPath "$run_dir/DerivedData" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

app="$run_dir/DerivedData/Build/Products/Release-iphoneos/PhotoCleaner.app"
test -d "$app"
test -f "$app/Info.plist"
plutil -lint "$app/Info.plist"
executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Info.plist")"
case "$executable" in
    ''|*/*|.|..) echo "Invalid CFBundleExecutable: $executable" >&2; exit 1 ;;
esac
test -s "$app/$executable"
test -x "$app/$executable"
xcrun lipo "$app/$executable" -verify_arch arm64
platform="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$app/Info.plist")"
test "$platform" = iPhoneOS

mkdir "$run_dir/Payload"
ditto "$app" "$run_dir/Payload/PhotoCleaner.app"
archive="$run_dir/PhotoCleaner-unsigned.ipa"
ditto -c -k --keepParent "$run_dir/Payload" "$archive"
test -s "$archive"
unzip -t "$archive"
unzip -Z1 "$archive" > "$run_dir/archive-entries.txt"
grep -Fxq 'Payload/PhotoCleaner.app/Info.plist' "$run_dir/archive-entries.txt"
grep -Fxq "Payload/PhotoCleaner.app/$executable" "$run_dir/archive-entries.txt"
mv "$archive" "$output"
echo "Unsigned device IPA verified: $output"
echo "Local re-signing is required before installation; this does not prove iPhone operation."
