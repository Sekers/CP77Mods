$version = "1.7.7-HotFix2"
$zipName = "Improved Minimap Zoom $version.zip"
$releasesDir = Join-Path $PSScriptRoot "releases"
$zipPath = Join-Path $releasesDir $zipName

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
