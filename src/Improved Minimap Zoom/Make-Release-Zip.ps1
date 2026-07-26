$ErrorActionPreference = "Stop"

$version = "1.7.7-HotFix2"
$zipName = "Improved Minimap Zoom $version.zip"
$releasesDir = Join-Path $PSScriptRoot "releases"
$zipPath = Join-Path $releasesDir $zipName

# The plugin is a REQUIRED dependency: imznative.reds declares IMZ_GetMinimapRadius,
# so a zip without the dll fails redscript compilation and disables the whole mod.
# native\Module is gitignored, so a fresh clone has nothing here until it is built.
$dllPath = Join-Path $PSScriptRoot "native\Module\red4ext\plugins\ImprovedMinimapZoom\ImprovedMinimapZoom_Native.dll"
if (-not (Test-Path $dllPath)) {
    throw "Native plugin not found at '$dllPath'. Build it first:`n  cmake -S native -B native/build -G `"Visual Studio 17 2022`" -A x64`n  cmake --build native/build --config Release"
}

if (-not (Test-Path $releasesDir)) {
    New-Item -ItemType Directory -Path $releasesDir | Out-Null
}

$tempDir = New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid()))

try {
    Copy-Item -Path (Join-Path $PSScriptRoot "archive") -Destination $tempDir -Recurse
    Copy-Item -Path (Join-Path $PSScriptRoot "r6")      -Destination $tempDir -Recurse
    Copy-Item -Path (Join-Path $PSScriptRoot "native\Module\*") -Destination "$tempDir\" -Recurse

    Compress-Archive -Path "$tempDir\*" -DestinationPath $zipPath -Force
    Write-Host "Release created: $zipPath"
} finally {
    Remove-Item $tempDir -Recurse -Force
}
