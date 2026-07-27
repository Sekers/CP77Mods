$ErrorActionPreference = "Stop"

$version    = "1.7.7-HotFix2"
$zipName    = "Improved Minimap Zoom $version.zip"
$releasesDir = Join-Path $PSScriptRoot "releases"
$zipPath    = Join-Path $releasesDir $zipName
$buildDir   = Join-Path $PSScriptRoot "native\build"

# Build Release here rather than trusting whatever happens to be lying around.
# Debug and Release used to share an output directory, so a stale or wrong-config
# dll could be packaged with nothing about the zip looking amiss.
if (-not (Test-Path $buildDir)) {
    throw "Native build directory not found at '$buildDir'. Configure it first:`n  cmake -S native -B native/build -G `"Visual Studio 17 2022`" -A x64"
}
Write-Host "Building native plugin (Release)..."
cmake --build $buildDir --config Release | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Native Release build failed with exit code $LASTEXITCODE." }

# The plugin is a REQUIRED dependency: imznative.reds declares IMZ_GetMinimapRadius,
# so a zip without the dll fails redscript compilation and disables the whole mod.
#
# Taken from the per-configuration Release path with no fallback to the shared
# bin/ directory, which can still hold a stale dll from before output directories
# were split per config. Silently packaging that is exactly what this prevents.
$dllPath = Join-Path $buildDir "bin\Release\ImprovedMinimapZoom_Native.dll"
if (-not (Test-Path $dllPath)) { throw "Release dll not found at '$dllPath' after a successful build." }

# Provenance, not wall-clock age: the question is whether the binary was built
# from the sources currently on disk, which a "built in the last N minutes" test
# cannot answer. It fires on an untouched dll during a plain repackage and stays
# silent when a build genuinely skips a modified file, which is the failure that
# actually happened during development.
$newestNativeSource = Get-ChildItem (Join-Path $PSScriptRoot "native\Plugins") -File |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($newestNativeSource -and (Get-Item $dllPath).LastWriteTime -lt $newestNativeSource.LastWriteTime) {
    throw "Release dll predates '$($newestNativeSource.Name)'. The build did not pick up current sources; clean and rebuild."
}

# Explicit allowlist. Everything shipped is named here, so build artefacts, pdbs,
# probe output, logs and stray working directories cannot be swept in by accident.
$items = @(
    @{ Source = (Join-Path $PSScriptRoot "archive"); Dest = "archive" }
    @{ Source = (Join-Path $PSScriptRoot "r6");      Dest = "r6" }
    @{ Source = $dllPath;  Dest = "red4ext\plugins\ImprovedMinimapZoom\ImprovedMinimapZoom_Native.dll" }
    @{ Source = (Join-Path $PSScriptRoot "README.md"); Dest = "Improved Minimap Zoom README.md" }
    # Mod-local, not the repo root LICENSE: this one names all three copyright
    # holders (Kovrik for the derived scripts, Legacy2077 for the hotfix work and
    # the plugin, Octavian Dima for the header-only SDK compiled into it), which
    # is what MIT requires when distributing modified copies and a binary built
    # from MIT headers.
    @{ Source = (Join-Path $PSScriptRoot "LICENSE.txt"); Dest = "LICENSE.txt" }
)
foreach ($item in $items) {
    if (-not (Test-Path $item.Source)) { throw "Allowlisted item missing: $($item.Source)" }
}

# Copying archive/ and r6/ wholesale is directory-level isolation, not a real
# allowlist: anything that ends up inside those trees ships. Enumerate what is
# actually in them and reject file types the mod does not publish, so a stray
# backup, editor swap file or probe output cannot slip into a release.
$allowedExtensions = @('.reds', '.xml', '.archive', '.xl')
$treeFiles = @(
    Get-ChildItem (Join-Path $PSScriptRoot "archive") -Recurse -File
    Get-ChildItem (Join-Path $PSScriptRoot "r6") -Recurse -File
)
$unexpected = $treeFiles | Where-Object { $allowedExtensions -notcontains $_.Extension.ToLower() }
if ($unexpected) {
    throw "Unexpected files in archive/ or r6/ (allowed: $($allowedExtensions -join ', ')):`n  " +
          (($unexpected | ForEach-Object { $_.FullName }) -join "`n  ")
}

if (-not (Test-Path $releasesDir)) {
    New-Item -ItemType Directory -Path $releasesDir | Out-Null
}

$stage = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid())
New-Item -ItemType Directory -Path $stage | Out-Null
try {
    foreach ($item in $items) {
        $target = Join-Path $stage $item.Dest
        $parent = Split-Path $target -Parent
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -Path $item.Source -Destination $target -Recurse
    }

    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zipPath -Force

    # Reopen and verify rather than assuming Compress-Archive did what was asked
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $entries = @($zip.Entries | Where-Object { $_.Name -ne '' })
        $staged  = @(Get-ChildItem $stage -Recurse -File)
        if ($entries.Count -ne $staged.Count) {
            throw "Archive verification failed: $($entries.Count) entries but $($staged.Count) staged files."
        }
        foreach ($entry in $entries) {
            $stagedFile = Join-Path $stage ($entry.FullName -replace '/', '\')
            if (-not (Test-Path $stagedFile)) { throw "Archive contains unexpected entry: $($entry.FullName)" }
            $ms = New-Object System.IO.MemoryStream
            $s = $entry.Open(); $s.CopyTo($ms); $s.Dispose()
            $inZip = (Get-FileHash -InputStream ([System.IO.MemoryStream]::new($ms.ToArray())) -Algorithm SHA256).Hash
            if ($inZip -ne (Get-FileHash $stagedFile -Algorithm SHA256).Hash) {
                throw "Archive verification failed: content mismatch for $($entry.FullName)"
            }
        }
        Write-Host "Verified $($entries.Count) entries against staged content."
    } finally {
        $zip.Dispose()
    }

    $sha = (Get-FileHash $zipPath -Algorithm SHA256).Hash
    "$sha *$zipName" | Set-Content -Path "$zipPath.sha256" -Encoding ascii

    Write-Host "Release created: $zipPath"
    Write-Host "SHA-256: $sha"
} finally {
    Remove-Item $stage -Recurse -Force
}
