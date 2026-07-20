# Improved Minimap Zoom — 1.7.7 Community Hotfixes (Game 1.63 Legacy)

Community-maintained hotfixes for [Improved Minimap Zoom](https://www.nexusmods.com/cyberpunk2077/mods/2959) by djkovrik, version **1.7.7** — the last release compatible with Cyberpunk 2077 **1.63 Legacy** (with Hotfix 1). Upstream development moved on to game 2.x; these branches keep the Legacy version working and polished.

## Releases

| Release | Branch | What it is |
| --- | --- | --- |
| `ImprovedMinimapZoom-1.7.7-HotFix1` | `fix-minimap-1.7.7` | Pure-redscript fixes: vehicle-exit crash, peek hotkey two-step zoom. No new requirements. The hotfix release is a complete package; uninstall other versions of IMZ before installing. |

## What was fixed

- **Vehicle-exit crash**: with dynamic zoom disabled and a large gap between vehicle and on-foot zoom values, exiting a vehicle could crash the game during the minimap's vehicle→on-foot transition. Fixed with a guarded post-unmount window and debounced, coalesced minimap refreshes.
- **Peek hotkey two-step zoom**: the zoom hotkey showed an intermediate motion before settling. Fixed by flattening all vision-radius values to a single waypoint during the refresh window and restoring per-state values before the refresh completes.

## Known limitations (engine constraints)

- The peek hotkey has no effect during active combat (the minimap refresh trigger is inert while combat controls the zoom — also true of the original 1.7.7).
- The peek hotkey is disabled while driving (never functional in the original either).
- Peeking near building entrances and some other locations may show a brief 2-step zoom animation (instead of a single step) due to the mod needing to guess at the player's location. Hotfix 1 improved this so it's less jarring but it still exists.
- With dynamic vehicle zoom enabled, the vanilla vehicle-mode minimap shift (marker pushed down) is suppressed. The two features are fundamentally incompatible in this engine version (see the author's original notes; verified by testing).

## Folder layout

```text
archive/   game resources (.archive + ArchiveXL manifest)
r6/        redscript sources + Input Loader hotkey mapping
```

## Requirements

- Cyberpunk 2077 **1.63 Legacy** with **1.63 Hotfix 1** (not 2.x)
- RED4ext, redscript, ArchiveXL, Input Loader, Mod Settings (1.63-compatible versions)

## Credits

- **djkovrik** — The original Improved Minimap Zoom mod ([v1.7.7](https://github.com/Sekers/CP77Mods/releases/tag/Improved-Minimap-Zoom-1.7.7); the last Cyberpunk 2077 Legacy compatible version).
- **Legacy2077** — Community hotfixes based off of mod version v1.7.7.
