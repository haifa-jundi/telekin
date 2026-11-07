#!/bin/zsh
# Builds Telekin.app (ad-hoc signed) and runs the offline self-test.
set -euo pipefail
cd -- "${0:A:h}"
app=Telekin.app
compiled="$(mktemp -d)"
trap 'rm -rf "$compiled"' EXIT
xcrun swiftc -swift-version 5 -O Sources/**/*.swift -o "$compiled/Telekin" \
    -framework AppKit -framework CoreMotion -framework AVFAudio -framework ApplicationServices -framework Carbon -framework MediaPlayer -framework SwiftUI -framework Charts -framework QuartzCore
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
codesign --force --sign - --timestamp=none "$app"
"$app/Contents/MacOS/Telekin" --self-test
echo "Built $app"
