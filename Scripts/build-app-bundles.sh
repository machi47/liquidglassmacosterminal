#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DESTINATION="${1:-}"

log() { printf '[liquidglass-package] %s\n' "$*"; }
die() { printf '[liquidglass-package] error: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "Application bundles can only be built on macOS."
[[ -n "${DESTINATION}" ]] || die "Usage: Scripts/build-app-bundles.sh DESTINATION_DIRECTORY"
for command in swift codesign plutil; do
    command -v "${command}" >/dev/null 2>&1 || die "Missing required command: ${command}"
done

version="$(sed -n 's/.*current = "\([^"]*\)".*/\1/p' "${REPOSITORY_ROOT}/Sources/LiquidGlassCore/Version.swift" | head -n1)"
[[ -n "${version}" ]] || die "Unable to read project version."
build_version="$(date -u +%Y%m%d%H%M%S)"

log "Building release products."
cd "${REPOSITORY_ROOT}"
swift build -c release --product liquidglass
swift build -c release --product LiquidGlassAgent
bin_path="$(swift build -c release --show-bin-path)"
cli_binary="${bin_path}/liquidglass"
agent_binary="${bin_path}/LiquidGlassAgent"
shader_source="${REPOSITORY_ROOT}/Sources/LiquidGlassAgent/Resources/LiquidGlass.metal"
[[ -x "${cli_binary}" && -x "${agent_binary}" ]] || die "Swift build did not produce both executables."
[[ -s "${shader_source}" ]] || die "The LiquidGlass.metal source is missing."

rm -rf "${DESTINATION}"
mkdir -p "${DESTINATION}"
agent_app="${DESTINATION}/LiquidGlass.app"
cli_app="${DESTINATION}/LiquidGlassCLI.app"
mkdir -p \
    "${agent_app}/Contents/MacOS" \
    "${agent_app}/Contents/Resources" \
    "${cli_app}/Contents/MacOS"

install -m 0755 "${agent_binary}" "${agent_app}/Contents/MacOS/LiquidGlassAgent"
install -m 0755 "${cli_binary}" "${cli_app}/Contents/MacOS/liquidglass"
install -m 0644 "${shader_source}" "${agent_app}/Contents/Resources/LiquidGlass.metal"
install -m 0644 "${REPOSITORY_ROOT}/Resources/Info.plist.template" "${agent_app}/Contents/Info.plist"
install -m 0644 "${REPOSITORY_ROOT}/Resources/CLI-Info.plist.template" "${cli_app}/Contents/Info.plist"

for plist in "${agent_app}/Contents/Info.plist" "${cli_app}/Contents/Info.plist"; do
    plutil -replace CFBundleShortVersionString -string "${version}" "${plist}"
    plutil -replace CFBundleVersion -string "${build_version}" "${plist}"
    plutil -lint "${plist}" >/dev/null
done

codesign --force --deep --sign - --identifier com.machi47.LiquidGlassAgent "${agent_app}" >/dev/null
codesign --force --deep --sign - --identifier com.machi47.LiquidGlassCLI "${cli_app}" >/dev/null
codesign --verify --deep --strict "${agent_app}"
codesign --verify --deep --strict "${cli_app}"

"${agent_app}/Contents/MacOS/LiquidGlassAgent" --validate-resources
"${cli_app}/Contents/MacOS/liquidglass" version
log "Built and validated ${agent_app} and ${cli_app}."
