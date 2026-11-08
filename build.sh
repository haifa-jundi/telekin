#!/bin/zsh
# Builds Telekin.app, signs it, and runs the offline self-test.
# Signing: uses the "Telekin Self-Signed" keychain identity (or $TELEKIN_SIGN_IDENTITY) when present,
# so macOS keeps the Accessibility permission across builds. Otherwise signs ad-hoc (for this Mac only).
set -euo pipefail
cd -- "${0:A:h}"
app=Telekin.app
compiled="$(mktemp -d)"
trap 'rm -rf "$compiled"' EXIT
xcrun swiftc -swift-version 5 -O Sources/**/*.swift -o "$compiled/Telekin" \
    -framework AppKit -framework CoreMotion -framework AVFAudio -framework ApplicationServices -framework Carbon -framework MediaPlayer -framework SwiftUI -framework Charts -framework QuartzCore -framework ServiceManagement
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
mv -f "$compiled/Telekin" "$app/Contents/MacOS/Telekin"
# Icon: regenerate with `swift Tools/make_icon.swift` if Assets/AppIcon.icns is missing.
[[ -f Assets/AppIcon.icns ]] || swift Tools/make_icon.swift
cp Assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Telekin</string>
<key>CFBundleIdentifier</key><string>io.github.haifa-jundi.telekin</string>
<key>CFBundleName</key><string>Telekin</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSHumanReadableCopyright</key><string>MIT License. Not affiliated with Apple.</string>
<key>NSMotionUsageDescription</key><string>Telekin reads your AirPods head motion to move the cursor.</string>
</dict></plist>
PLIST
identity="${TELEKIN_SIGN_IDENTITY:-Telekin Self-Signed}"
if security find-certificate -c "$identity" >/dev/null 2>&1; then
    # A fixed designated requirement (bundle id + certificate) is what keeps TCC grants across builds.
    leaf="$(security find-certificate -c "$identity" -Z | awk '/SHA-1 hash:/ {print $3}')"
    codesign --force --sign "$identity" --timestamp=none --options runtime \
        -r="designated => identifier \"io.github.haifa-jundi.telekin\" and certificate leaf = H\"$leaf\"" "$app"
    echo "Signed with \"$identity\""
else
    codesign --force --sign - --timestamp=none "$app"
    echo "Signed ad-hoc (no \"$identity\" identity in the keychain)"
fi
"$app/Contents/MacOS/Telekin" --self-test
echo "Built $app"
