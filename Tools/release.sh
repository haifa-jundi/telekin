#!/bin/zsh
# Builds Telekin.app and packs it as dist/Telekin-<version>.zip for a GitHub release.
# Run from anywhere: zsh Tools/release.sh
set -euo pipefail
cd -- "${0:A:h:h}"
zsh build.sh
signature="$(codesign -dvv Telekin.app 2>&1)"
if [[ "$signature" != *"Authority=Telekin Self-Signed"* ]]; then
    echo "Refusing to package: Telekin.app is not signed with the \"Telekin Self-Signed\" identity." >&2
    echo "Release builds must share one signature, or users lose the Accessibility permission on update." >&2
    exit 1
fi
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Telekin.app/Contents/Info.plist)"
mkdir -p dist
zip="dist/Telekin-$version.zip"
rm -f "$zip"
ditto -c -k --sequesterRsrc --keepParent Telekin.app "$zip"
echo "Packed $zip"
shasum -a 256 "$zip"
