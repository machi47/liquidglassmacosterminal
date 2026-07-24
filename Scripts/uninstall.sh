#!/usr/bin/env bash
set -Eeuo pipefail

APP_SUPPORT="${HOME}/Library/Application Support/LiquidGlass"
LABEL="com.machi47.liquidglass.agent"
GUI_DOMAIN="gui/$(id -u)"
LAUNCH_AGENT="${HOME}/Library/LaunchAgents/${LABEL}.plist"
PREFIX="${LIQUIDGLASS_PREFIX:-/usr/local}"
COMMAND_LINK="${PREFIX}/bin/liquidglass"
CLI="${APP_SUPPORT}/LiquidGlassCLI.app/Contents/MacOS/liquidglass"

if [[ -x "${CLI}" ]]; then
    "${CLI}" off || {
        printf '[liquidglass] error: Terminal restoration failed; installation was retained.\n' >&2
        exit 1
    }
fi
launchctl bootout "${GUI_DOMAIN}/${LABEL}" >/dev/null 2>&1 || true
rm -f "${LAUNCH_AGENT}"
if [[ -L "${COMMAND_LINK}" ]]; then
    if [[ -w "$(dirname "${COMMAND_LINK}")" ]]; then rm -f "${COMMAND_LINK}"; else sudo rm -f "${COMMAND_LINK}"; fi
fi
rm -rf "${APP_SUPPORT}"
printf '[liquidglass] uninstalled.\n'
