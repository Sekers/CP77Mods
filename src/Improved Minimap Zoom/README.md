# Improved Minimap Zoom — 1.7.7 Community Hotfixes (Game 1.63 Legacy)

Community-maintained hotfixes for [Improved Minimap Zoom](https://www.nexusmods.com/cyberpunk2077/mods/2959) by djkovrik, version **1.7.7** — the last release compatible with Cyberpunk 2077 **1.63 Legacy** (with Hotfix 1). Upstream development moved on to game 2.x; these branches keep the Legacy version working and polished.

## Releases

| Release | Branch | What it is |
| --- | --- | --- |
| `Improved-Minimap-Zoom-1.7.7-HF1` | `fix-minimap-1.7.7-HF1` | Pure-redscript fixes: vehicle-exit crash, peek hotkey two-step zoom. No new requirements. The hotfix release is a complete package; uninstall other versions of IMZ before installing. |
| `Improved-Minimap-Zoom-1.7.7-HF2` | `fix-minimap-1.7.7-HF2-Native` | Everything in HotFix1, plus a small bundled RED4ext plugin that reads the minimap's live zoom from memory, making the peek hotkey exact everywhere. Also adds peek while driving, finer settings sliders, instant apply of settings changes, and 3 minor fixes (all listed below). The hotfix release is a complete package; uninstall other versions of IMZ before installing. |

## What was added or fixed in HF2

- **Peek exactness**: the waypoint now comes from the minimap's *actual displayed* radius (read natively), removing the last visible artifacts near building entrances and in quest areas, plus a release clamp for rapid double-taps.
- **Peek while driving**: the peek hotkey now also works in vehicles, zooming out on top of the vehicle zoom and returning on release. It is always available when dynamic vehicle zoom is enabled. When dynamic zoom is off the mod keeps the vanilla vehicle-mode minimap downward shift by default, which is incompatible with peek. You can enable the new **Vehicle peek when no dynamic zoom** setting to trade the shift for peek support.
- **Finer settings sliders**: all zoom and speed sliders move in steps of 1 (was 5), and the peek increment can go as low as 5 (was 20).
- **Instant settings**: zoom settings apply the moment the Mod Settings menu closes.
- **Interior zoom dead after driving** (regression introduced in HotFix1): exiting a vehicle left all per-state zoom values flattened to the Exterior value, so interior/combat/security-area zoom stopped applying until the next peek or settings change. The delayed post-unmount refresh now restores the per-state values first.
- **Zone-restore race**: the mod refreshes the minimap by briefly faking the player's security zone and restoring it ~0.1s later. If a *real* zone change happened inside that window (e.g. stepping into a shop the instant a refresh fired), the restore overwrote it with a stale value and that was visible to every game system that reads the player zone. The restore is now skipped when the zone changed underneath it.
- **Peek during a pending refresh left zoom flattened** (latent since HotFix1's refresh debounce): pressing the peek hotkey while another minimap refresh was in flight (e.g. right after exiting a vehicle or closing the settings menu) dropped the peek's bucket-restore step, leaving all per-state zoom values flattened. Toggle-mode peek would stay there indefinitely. Coalesced requests now carry the restore obligation over to the pending refresh.

## Known limitations (engine constraints)

- The peek hotkey has no effect during active combat (the minimap refresh trigger is inert while combat controls the zoom; also true of the original 1.7.7).
- In a vehicle, the vanilla game shifts the minimap so your marker sits lower and you see more of the road ahead. That shift is incompatible with both dynamic vehicle zoom and peek-while-driving. Dynamic vehicle zoom always turns it off. With dynamic zoom off, the **Vehicle peek when no dynamic zoom** setting decides which one you get.
- Entering an interior can show a brief minimap blip (most visible on the yellow route line): the engine switches from the Exterior to the Interior zoom value as a single instant snap right at the doorway, simultaneously with the interior map mode, and the route line re-fits during that repaint. This is inherent to how 1.63 recomputes minimap zoom (no interpolation), has existed since the original 1.7.7, and gets more visible the further apart the Interior and Exterior settings are (keeping them closer together reduces it).

## Folder layout

```text
archive/   game resources (.archive + ArchiveXL manifest)
r6/        redscript sources + Input Loader hotkey mapping
native/    RED4ext plugin source (CMake, C++20, MSVC x64) — see native/RESEARCH.md
releases/  built release zips
```

Open `Improved Minimap Zoom.code-workspace` in VS Code to get both the repo and the native plugin configured (C++ IntelliSense activates for `native/` once the project has been configured at least once).

## Building the native plugin

```text
cmake -S native -B native/build -G "Visual Studio 17 2022" -A x64
cmake --build native/build --config Release
```

The RED4ext.SDK is fetched automatically at configure time, pinned to the 1.63-HF1 commit of [Sekers/RED4ext.SDK](https://github.com/Sekers/RED4ext.SDK) (`046877f9`). Output: `native/build/bin/ImprovedMinimapZoom_Native.dll` (also published to `native/Module/red4ext/plugins/ImprovedMinimapZoom/`). The dll ships only inside release zips; it is never committed to the repository.

The offset research (how the live-radius address was found, and how to find more) is documented in [`native/RESEARCH.md`](native/RESEARCH.md).

## Packaging a release zip

After building the native plugin, run from this folder (requires [PowerShell](https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell)):

```text
pwsh.exe -ExecutionPolicy Bypass -File "Make-Release-Zip.ps1"
```

Output: `releases\Improved Minimap Zoom 1.7.7-HotFix2.zip`

## Requirements (HotFix2)

- Cyberpunk 2077 **1.63 Legacy** with **1.63 Hotfix 1** (not 2.x)
- RED4ext 1.15.0, redscript, ArchiveXL, Input Loader, Mod Settings (1.63-compatible versions)

## Credits

- **djkovrik** — The original Improved Minimap Zoom mod ([v1.7.7](https://github.com/Sekers/CP77Mods/releases/tag/Improved-Minimap-Zoom-1.7.7); the last Cyberpunk 2077 Legacy compatible version).
- **Legacy2077** — Community hotfixes based off of mod version v1.7.7.
