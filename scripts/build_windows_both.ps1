# Builds both the field app (default entry point) and the Command Console
# (lib/main_admin.dart) for Windows, and copies each into dist/ since both
# currently compile to the same build/windows/x64/runner/Release path and
# would otherwise overwrite each other.
#
# Usage (from the aeriemed/ project root):
#   powershell -ExecutionPolicy Bypass -File scripts/build_windows_both.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# Copies the CONTENTS of the freshly built Release folder into $dest,
# never the folder itself -- Copy-Item -Recurse "Release" "$dest" nests a
# Release\ subfolder inside $dest instead of overwriting in place whenever
# $dest already exists (e.g. Remove-Item below silently failed because the
# old .exe was still running and locked), leaving a broken top-level exe
# with no data\ folder next to it that fails to launch at all. Failing
# loudly here beats silently shipping that.
function Copy-BuildOutput([string]$dest) {
  Remove-Item -Recurse -Force $dest -ErrorAction SilentlyContinue
  if (Test-Path $dest) {
    throw "Could not remove $dest -- is resqruck.exe still running from a previous test? Close it and try again."
  }
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Item -Path "build/windows/x64/runner/Release/*" -Destination $dest -Recurse -Force
}

Write-Host "Building field app (lib/main.dart)..."
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "Field app build failed" }
New-Item -ItemType Directory -Force -Path "dist" | Out-Null
Copy-BuildOutput "dist/field-app-windows"
Write-Host "-> dist/field-app-windows/resqruck.exe"

Write-Host "Building Command Console (lib/main_admin.dart)..."
flutter build windows --release -t lib/main_admin.dart
if ($LASTEXITCODE -ne 0) { throw "Command Console build failed" }
Copy-BuildOutput "dist/command-console-windows"
Write-Host "-> dist/command-console-windows/resqruck.exe"

Write-Host "Done. Both apps are named resqruck.exe -- keep them in their separate dist/ folders."
