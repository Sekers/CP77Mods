# Improved Minimap Zoom — 1.7.7 Community Hotfixes (Game 1.63 Legacy)

Community-maintained hotfixes for [Improved Minimap Zoom](https://www.nexusmods.com/cyberpunk2077/mods/2959) by djkovrik, version **1.7.7** — the last release compatible with Cyberpunk 2077 **1.63 Legacy** (with Hotfix 1). Upstream development moved on to game 2.x; these branches keep the Legacy version working and polished.

## Releases

| Release | Branch | What it is |
| --- | --- | --- |
| `ImprovedMinimapZoom-1.7.7-HotFix1` | `fix-minimap-1.7.7` | Pure-redscript fixes: vehicle-exit crash, peek hotkey two-step zoom. No new requirements. The hotfix release is a complete package; uninstall other versions of IMZ before installing. |
| `ImprovedMinimapZoom-1.7.7-HotFix2` | `fix-minimap-1.7.7-native` | Everything in HotFix1, plus a small bundled RED4ext plugin that reads the minimap's live zoom from memory — making the peek hotkey exact everywhere — and instant apply of settings changes. Adds a RED4ext 1.15.0 requirement (which was already needed for the required dependency mods). The hotfix release is a complete package; uninstall other versions of IMZ before installing. |

## What was fixed

- **Vehicle-exit crash** (HotFix1): with dynamic zoom disabled and a large gap between vehicle and on-foot zoom values, exiting a vehicle could crash the game during the minimap's vehicle→on-foot transition. Fixed with a guarded post-unmount window and debounced, coalesced minimap refreshes.
- **Peek hotkey two-step zoom** (HotFix1): the zoom hotkey showed an intermediate motion before settling. Fixed by flattening all vision-radius values to a single waypoint during the refresh window and restoring per-state values before the refresh completes.
- **Peek exactness** (HotFix2): the waypoint now comes from the minimap's *actual displayed* radius (read natively), removing the last visible artifacts near building entrances and in quest areas, plus a release clamp for rapid double-taps.
- **Instant settings** (HotFix2): zoom settings apply the moment the Mod Settings menu closes.

## Known limitations (engine constraints)

- The peek hotkey has no effect during active combat (the minimap refresh trigger is inert while combat controls the zoom — also true of the original 1.7.7).
- The peek hotkey is disabled while driving (never functional in the original either).
- With dynamic vehicle zoom enabled, the vanilla vehicle-mode minimap shift (marker pushed down) is suppressed — the two features are fundamentally incompatible in this engine version (see the author's original notes; verified by testing).

## Folder layout

```text
archive/   game resources (.archive + ArchiveXL manifest)
r6/        redscript sources + Input Loader hotkey mapping
native/    RED4ext plugin source (CMake, C++20, MSVC x64) — see native/RESEARCH.md
releases/  built release zips + notes (not tracked as releases; see GitHub releases)
```

Open `Improved Minimap Zoom.code-workspace` in VS Code to get both the repo and the native plugin configured (C++ IntelliSense activates for `native/` once the project has been configured at least once).

## Building the native plugin

```text
cmake -S native -B native/build -G "Visual Studio 17 2022" -A x64
cmake --build native/build --config Release
```

The RED4ext.SDK is fetched automatically at configure time, pinned to the 1.63-HF1 commit of [Sekers/RED4ext.SDK](https://github.com/Sekers/RED4ext.SDK) (`046877f9`). Output: `native/build/bin/ImprovedMinimapZoom_Native.dll` (also published to `native/Module/red4ext/plugins/ImprovedMinimapZoom/`). The dll ships only inside release zips — it is never committed to the repository.

The offset research (how the live-radius address was found, and how to find more) is documented in [`native/RESEARCH.md`](native/RESEARCH.md).

## Packaging a release zip

After building the native plugin, run from this folder (requires [PowerShell](https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell)):

```text
pwsh.exe -ExecutionPolicy Bypass -File "Make-Release-Zip.ps1"
```

Output: `releases\Improved Minimap Zoom 1.7.7-HotFix2-Native.zip`

## Requirements (HotFix2)

- Cyberpunk 2077 **1.63 Legacy** with **1.63 Hotfix 1** (not 2.x)
- RED4ext 1.15.0, redscript, ArchiveXL, Input Loader, Mod Settings (1.63-compatible versions)

## Credits

- **djkovrik** — The original Improved Minimap Zoom mod ([v1.7.7](https://github.com/Sekers/CP77Mods/releases/tag/Improved-Minimap-Zoom-1.7.7); the last Cyberpunk 2077 Legacy compatible version).
- **Legacy2077** — Community hotfixes based off of mod version v1.7.7.
