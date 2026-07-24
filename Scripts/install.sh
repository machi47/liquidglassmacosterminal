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

link_parent="$(dirname "${COMMAND_LINK}")"
if [[ -e "${COMMAND_LINK}" && ! -L "${COMMAND_LINK}" ]]; then
    die "${COMMAND_LINK} already exists and is not a symlink. Set LIQUIDGLASS_PREFIX to another prefix."
fi
if [[ ! -d "${link_parent}" || ! -w "${link_parent}" ]]; then
    command -v sudo >/dev/null 2>&1 || die "${link_parent} is not writable and sudo is unavailable."
fi

staging="$(mktemp -d "${TMPDIR:-/tmp}/liquidglass-install.XXXXXX")"
trap 'rm -rf "${staging}"' EXIT
bundle_stage="${staging}/bundles"
"${SCRIPT_DIR}/build-app-bundles.sh" "${bundle_stage}"

mkdir -p "${APP_SUPPORT}" "${LOG_DIR}" "$(dirname "${LAUNCH_AGENT}")"
launchctl bootout "${GUI_DOMAIN}/${LABEL}" >/dev/null 2>&1 || true
rm -rf "${AGENT_APP}" "${CLI_APP}"
mv "${bundle_stage}/LiquidGlass.app" "${AGENT_APP}"
mv "${bundle_stage}/LiquidGlassCLI.app" "${CLI_APP}"

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

if [[ -d "${link_parent}" && -w "${link_parent}" ]]; then
    ln -sfn "${CLI_APP}/Contents/MacOS/liquidglass" "${COMMAND_LINK}"
else
    sudo mkdir -p "${link_parent}"
    sudo ln -sfn "${CLI_APP}/Contents/MacOS/liquidglass" "${COMMAND_LINK}"
fi

for _ in {1..50}; do
    [[ -f "${APP_SUPPORT}/agent-runtime.json" ]] && break
    sleep 0.1
done

"${CLI_APP}/Contents/MacOS/liquidglass" version
log "Installation complete."
printf '\nOne-time permission setup and enable:\n'
printf '  liquidglass doctor --prompt\n'
printf '  liquidglass on\n\n'
printf 'Normal use afterward:\n'
printf '  liquidglass on\n'
printf '  liquidglass off\n'
