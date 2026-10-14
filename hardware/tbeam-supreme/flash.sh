#!/usr/bin/env bash
# Configure an already-Meshtastic-flashed T-Beam Supreme for AerieMed.
# Firmware flashing itself is done via https://flasher.meshtastic.org or esptool
# (see README.md) — this script only applies the AerieMed device configuration.
#
# Usage: PSK="base64:...." ./flash.sh [--port /dev/ttyACM0]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT_ARG=()
[ "${1:-}" = "--port" ] && PORT_ARG=(--port "$2")

if ! command -v meshtastic >/dev/null 2>&1; then
  echo "meshtastic CLI not found. Install: pip install --upgrade 'meshtastic[cli]'" >&2
  exit 1
fi
if [ -z "${PSK:-}" ]; then
  echo "Set PSK env var to the team channel key, e.g. PSK=\"base64:$(openssl rand -base64 32)\"" >&2
  exit 1
fi

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
sed "s#base64:REPLACE_WITH_TEAM_KEY#${PSK}#" "$HERE/config.yaml" > "$TMP"

echo "Applying AerieMed config to the T-Beam..."
meshtastic "${PORT_ARG[@]}" --configure "$TMP"
echo "Done. Verify with: meshtastic ${PORT_ARG[*]} --info"
