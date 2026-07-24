#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
bash -n install.sh uninstall.sh Scripts/*.sh
plutil -lint Resources/*.plist.template
swift test
swift build -c release --product liquidglass
swift build -c release --product LiquidGlassAgent
xcrun -sdk macosx metal -c Sources/LiquidGlassAgent/Resources/LiquidGlass.metal -o /tmp/LiquidGlass.air
xcrun -sdk macosx metallib /tmp/LiquidGlass.air -o /tmp/LiquidGlass.metallib
rm -f /tmp/LiquidGlass.air /tmp/LiquidGlass.metallib
