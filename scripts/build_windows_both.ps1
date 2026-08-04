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

Write-Host "Building field app (lib/main.dart)..."
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "Field app build failed" }
Remove-Item -Recurse -Force "dist/field-app-windows" -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "dist" | Out-Null
Copy-Item -Recurse "build/windows/x64/runner/Release" "dist/field-app-windows"
Write-Host "-> dist/field-app-windows/resqruck.exe"

Write-Host "Building Command Console (lib/main_admin.dart)..."
flutter build windows --release -t lib/main_admin.dart
if ($LASTEXITCODE -ne 0) { throw "Command Console build failed" }
Remove-Item -Recurse -Force "dist/command-console-windows" -ErrorAction SilentlyContinue
Copy-Item -Recurse "build/windows/x64/runner/Release" "dist/command-console-windows"
Write-Host "-> dist/command-console-windows/resqruck.exe"

Write-Host "Done. Both apps are named resqruck.exe -- keep them in their separate dist/ folders."
