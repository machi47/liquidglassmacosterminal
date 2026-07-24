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
test -s /tmp/LiquidGlass.metallib
rm -f /tmp/LiquidGlass.air /tmp/LiquidGlass.metallib
bundle_stage="$(mktemp -d "${TMPDIR:-/tmp}/liquidglass-bundles.XXXXXX")"
trap 'rm -rf "${bundle_stage}"' EXIT
./Scripts/build-app-bundles.sh "${bundle_stage}/output"
test -x "${bundle_stage}/output/LiquidGlass.app/Contents/MacOS/LiquidGlassAgent"
test -s "${bundle_stage}/output/LiquidGlass.app/Contents/Resources/LiquidGlass.metal"
test -x "${bundle_stage}/output/LiquidGlassCLI.app/Contents/MacOS/liquidglass"
test ! -d .bootstrap
! find . -path './.git' -prune -o -type f -name 'part-*' -print -quit | grep -q .
