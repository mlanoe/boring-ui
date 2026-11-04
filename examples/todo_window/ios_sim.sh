#!/usr/bin/env bash
# Builds the Todo window for the iOS Simulator (`--target wgpu`, rust target aarch64-apple-ios-sim), packages it as an
# .app under main_wgpu/ios and launches it. Usage: ./ios_sim.sh [device]   (a simulator name or UDID; the booted one by default)
# Needs Xcode (simctl, vtool, codesign) and a booted simulator (`xcrun simctl boot <device>`).
#
# Two workarounds, both for the simulator only (see "Mobile adaptation" in the README):
#  - the binary is relabelled to the iOS 17 SDK: winit 0.30 does not adopt UIScene, which an app linked against a newer
#    SDK must, so iOS refuses it otherwise. This is not an option for a device or the App Store;
#  - Info.plist declares an empty UILaunchScreen: without one iOS runs the app in a 320x480 compatibility mode.
# If nothing shows, turn on I/O > Keyboard > "Show On-Screen Keyboard" in the Simulator: the soft keyboard only comes up
# for a focused text field when it is on.
set -euo pipefail

BORING="${BORING:-boring}"
device="${1:-booted}"
cd "$(dirname "${BASH_SOURCE[0]}")"

rustup target add aarch64-apple-ios-sim >/dev/null
rm -rf main_wgpu
out=$("$BORING" build --target wgpu 2>&1) || { echo "$out" >&2; exit 1; }
cd main_wgpu
RUSTFLAGS="-A warnings" cargo build --release --target aarch64-apple-ios-sim -q

app=ios/Todo.app
rm -rf ios
mkdir -p "$app"
cp target/aarch64-apple-ios-sim/release/main "$app/main"
cat > "$app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>main</string>
<key>CFBundleIdentifier</key><string>com.boring.todo</string>
<key>CFBundleName</key><string>Todo</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>CFBundleVersion</key><string>1</string>
<key>MinimumOSVersion</key><string>17.0</string>
<key>UIDeviceFamily</key><array><integer>1</integer></array>
<key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
<key>UIRequiresFullScreen</key><true/>
<key>UILaunchScreen</key><dict/>
</dict></plist>
PLIST

out=$(xcrun vtool -set-build-version iossim 17.0 17.0 -replace -output "$app/main" "$app/main" 2>&1) || { echo "$out" >&2; exit 1; }
codesign -f -s - "$app" 2>/dev/null

xcrun simctl terminate "$device" com.boring.todo 2>/dev/null || true
xcrun simctl install "$device" "$app"
xcrun simctl launch "$device" com.boring.todo
