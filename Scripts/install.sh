#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_SUPPORT="${HOME}/Library/Application Support/LiquidGlass"
AGENT_APP="${APP_SUPPORT}/LiquidGlass.app"
CLI_APP="${APP_SUPPORT}/LiquidGlassCLI.app"
LAUNCH_AGENT="${HOME}/Library/LaunchAgents/com.machi47.liquidglass.agent.plist"
LOG_DIR="${APP_SUPPORT}/Logs"
GUI_DOMAIN="gui/$(id -u)"
LABEL="com.machi47.liquidglass.agent"
PREFIX="${LIQUIDGLASS_PREFIX:-/usr/local}"
COMMAND_LINK="${PREFIX}/bin/liquidglass"

log() { printf '[liquidglass] %s\n' "$*"; }
die() { printf '[liquidglass] error: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "This installer requires macOS."
major="$(sw_vers -productVersion | cut -d. -f1)"
[[ "${major}" =~ ^[0-9]+$ ]] || die "Unable to determine macOS version."
(( major >= 15 )) || die "macOS 15 or newer is required."
for command in swift codesign launchctl plutil; do
    command -v "${command}" >/dev/null 2>&1 || die "Missing required command: ${command}"
done

version="$(sed -n 's/.*current = "\([^"]*\)".*/\1/p' "${REPOSITORY_ROOT}/Sources/LiquidGlassCore/Version.swift" | head -n1)"
[[ -n "${version}" ]] || die "Unable to read project version."
build_version="$(date -u +%Y%m%d%H%M%S)"

log "Building release binaries and Metal resources..."
cd "${REPOSITORY_ROOT}"
swift build -c release --product liquidglass
swift build -c release --product LiquidGlassAgent
bin_path="$(swift build -c release --show-bin-path)"
cli_binary="${bin_path}/liquidglass"
agent_binary="${bin_path}/LiquidGlassAgent"
[[ -x "${cli_binary}" && -x "${agent_binary}" ]] || die "Swift build did not produce both executables."

resource_bundle="$(find "${bin_path}" -maxdepth 1 -type d -name '*LiquidGlassAgent*.bundle' -print -quit)"
[[ -n "${resource_bundle}" ]] || die "SwiftPM did not produce the LiquidGlassAgent resource bundle."
[[ -f "${resource_bundle}/LiquidGlass.metal" ]] || die "The Metal shader is missing from the resource bundle."

staging="$(mktemp -d "${TMPDIR:-/tmp}/liquidglass-install.XXXXXX")"
trap 'rm -rf "${staging}"' EXIT
staged_agent="${staging}/LiquidGlass.app"
staged_cli="${staging}/LiquidGlassCLI.app"
mkdir -p \
    "${staged_agent}/Contents/MacOS" \
    "${staged_agent}/Contents/Resources" \
    "${staged_cli}/Contents/MacOS"
install -m 0755 "${agent_binary}" "${staged_agent}/Contents/MacOS/LiquidGlassAgent"
install -m 0755 "${cli_binary}" "${staged_cli}/Contents/MacOS/liquidglass"
cp -R "${resource_bundle}" "${staged_agent}/Contents/Resources/"

cp "${REPOSITORY_ROOT}/Resources/Info.plist.template" "${staged_agent}/Contents/Info.plist"
cp "${REPOSITORY_ROOT}/Resources/CLI-Info.plist.template" "${staged_cli}/Contents/Info.plist"
for plist in "${staged_agent}/Contents/Info.plist" "${staged_cli}/Contents/Info.plist"; do
    plutil -replace CFBundleShortVersionString -string "${version}" "${plist}"
    plutil -replace CFBundleVersion -string "${build_version}" "${plist}"
    plutil -lint "${plist}" >/dev/null
 done

codesign --force --deep --sign - --identifier com.machi47.LiquidGlassAgent "${staged_agent}" >/dev/null
codesign --force --deep --sign - --identifier com.machi47.LiquidGlassCLI "${staged_cli}" >/dev/null
codesign --verify --deep --strict "${staged_agent}"
codesign --verify --deep --strict "${staged_cli}"

mkdir -p "${APP_SUPPORT}" "${LOG_DIR}" "$(dirname "${LAUNCH_AGENT}")"
launchctl bootout "${GUI_DOMAIN}/${LABEL}" >/dev/null 2>&1 || true
rm -rf "${AGENT_APP}" "${CLI_APP}"
mv "${staged_agent}" "${AGENT_APP}"
mv "${staged_cli}" "${CLI_APP}"

launch_plist="${staging}/${LABEL}.plist"
cp "${REPOSITORY_ROOT}/Resources/LaunchAgent.plist.template" "${launch_plist}"
plutil -replace ProgramArguments.0 -string "${AGENT_APP}/Contents/MacOS/LiquidGlassAgent" "${launch_plist}"
plutil -replace StandardOutPath -string "${LOG_DIR}/agent.log" "${launch_plist}"
plutil -replace StandardErrorPath -string "${LOG_DIR}/agent-error.log" "${launch_plist}"
plutil -lint "${launch_plist}" >/dev/null
install -m 0644 "${launch_plist}" "${LAUNCH_AGENT}"
launchctl bootstrap "${GUI_DOMAIN}" "${LAUNCH_AGENT}"
launchctl enable "${GUI_DOMAIN}/${LABEL}" >/dev/null 2>&1 || true
launchctl kickstart -k "${GUI_DOMAIN}/${LABEL}"

link_parent="$(dirname "${COMMAND_LINK}")"
if [[ -e "${COMMAND_LINK}" && ! -L "${COMMAND_LINK}" ]]; then
    die "${COMMAND_LINK} already exists and is not a symlink. Set LIQUIDGLASS_PREFIX to another prefix."
fi
if [[ -d "${link_parent}" && -w "${link_parent}" ]]; then
    ln -sfn "${CLI_APP}/Contents/MacOS/liquidglass" "${COMMAND_LINK}"
else
    command -v sudo >/dev/null 2>&1 || die "${link_parent} is not writable and sudo is unavailable."
    sudo mkdir -p "${link_parent}"
    sudo ln -sfn "${CLI_APP}/Contents/MacOS/liquidglass" "${COMMAND_LINK}"
fi

for _ in {1..50}; do
    [[ -f "${APP_SUPPORT}/agent-runtime.json" ]] && break
    sleep 0.1
done

log "Installed LiquidGlass Terminal ${version}."
printf '\nOne-time permission setup and enable:\n'
printf '  liquidglass doctor --prompt\n'
printf '  liquidglass on\n\n'
printf 'Normal use afterward:\n'
printf '  liquidglass on\n'
printf '  liquidglass off\n'
