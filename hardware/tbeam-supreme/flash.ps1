# Configure an already-Meshtastic-flashed T-Beam Supreme for AerieMed (Windows).
# Firmware flashing itself is done via https://flasher.meshtastic.org or esptool
# (see README.md) -- this script only applies the AerieMed device configuration.
#
# Usage:  $env:PSK="base64:...."; .\flash.ps1 [-Port COM5]
param([string]$Port)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Get-Command meshtastic -ErrorAction SilentlyContinue)) {
  Write-Error "meshtastic CLI not found. Install: pip install --upgrade 'meshtastic[cli]'"
}
if (-not $env:PSK) {
  Write-Error 'Set $env:PSK to the team channel key, e.g. $env:PSK = "base64:<openssl rand -base64 32>"'
}

$tmp = New-TemporaryFile
try {
  (Get-Content "$here\config.yaml") -replace 'base64:REPLACE_WITH_TEAM_KEY', $env:PSK | Set-Content $tmp
  $portArgs = @(); if ($Port) { $portArgs = @("--port", $Port) }
  Write-Host "Applying AerieMed config to the T-Beam..."
  meshtastic @portArgs --configure $tmp
  Write-Host "Done. Verify with: meshtastic $($portArgs -join ' ') --info"
} finally {
  Remove-Item $tmp -ErrorAction SilentlyContinue
}
