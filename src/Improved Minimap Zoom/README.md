# Improved Minimap Zoom — 1.7.7 Community Hotfixes (Game 1.63 Legacy)

Community-maintained hotfixes for [Improved Minimap Zoom](https://www.nexusmods.com/cyberpunk2077/mods/2959) by djkovrik, version **1.7.7** — the last release compatible with Cyberpunk 2077 **1.63 Legacy** (with Hotfix 1). Upstream development moved on to game 2.x; these branches keep the Legacy version working and polished.

## Releases

| Release | Branch | What it is |
| --- | --- | --- |
| `Improved-Minimap-Zoom-1.7.7-HF1` | `fix-minimap-1.7.7-HF1` | Pure-redscript fixes: vehicle-exit crash, peek hotkey two-step zoom. No new requirements. The hotfix release is a complete package; uninstall other versions of IMZ before installing. |
| `Improved-Minimap-Zoom-1.7.7-HF2` | `fix-minimap-1.7.7-HF2-Native` | Everything in HotFix1, plus a small bundled RED4ext plugin that reads the minimap's live zoom from memory, making the peek hotkey exact everywhere. Also adds peek while driving, finer settings sliders, instant apply of settings changes, and a set of smaller fixes (all listed below). The hotfix release is a complete package; uninstall other versions of IMZ before installing. |

## What was added or fixed in HF2

- **Peek exactness**: peek now measures from the zoom *actually on screen*, so it lands exactly right everywhere, including near building entrances and in quest areas, where it used to overshoot or come back to the wrong level. Rapid double-taps no longer dip past where you started.
- **Peek while driving**: the peek hotkey now also works in vehicles, zooming out on top of the vehicle zoom and returning on release. It is always available when dynamic vehicle zoom is enabled. When dynamic zoom is off the mod keeps the vanilla vehicle-mode minimap downward shift by default, which is incompatible with peek. You can enable the new **Vehicle peek when no dynamic zoom** setting to trade the shift for peek support.
- **Finer settings sliders**: all zoom and speed sliders move in steps of 1 (was 5), and the peek increment can go as low as 5 (was 20).
- **Instant settings**: zoom settings apply the moment the Mod Settings menu closes.
- **Zoom blip when leaving a vehicle** (present since the original 1.7.7): every time you got out, the minimap flickered through a wrong zoom level before settling (more noticeable the further apart your Interior and Exterior settings are). The transition is now clean.
- **Getting straight back into a vehicle showed the wrong zoom** (present since the original 1.7.7): hopping back in within about a third of a second of stepping out left the minimap on the on-foot zoom instead of switching to the vehicle one. With dynamic vehicle zoom turned off it stayed wrong for the rest of the drive.
- **Peek hotkey no longer fires inside menus**: the hotkey was reachable from the map, inventory and pause menus. It is now bound to gameplay and vehicles only.
- **Reversing zooms out like driving forward**: backing up always sat at the closest zoom, however fast you were going. Reverse speed now widens the minimap exactly the way forward speed does.
- **Settings menu shows up in every language**: the mod shipped translations for 11 of the game's 18 text languages, and players on any of the other seven (Polish, Brazilian Portuguese, Korean, Hungarian, Thai, Turkish, Latin American Spanish) saw raw text keys in the settings menu *and* a false "resource files not detected!" error on the main menu even with the mod installed correctly. Those seven now fall back to English (Latin American Spanish falls back to Spanish), covering all 18.
- **Interior zoom dead after driving** (regression introduced in HotFix1): once you had driven anywhere, the Interior, Combat and Security Area zooms stopped applying; everything stayed at the Exterior level until you next used the peek hotkey or changed a setting.
- **Wrong security zone after a zoom change**: to make the minimap redraw, the mod briefly swaps which security zone the game thinks you are in, then puts it back. If you genuinely crossed into a different zone at that exact moment (walking into a shop as the zoom changed, say), it put the old zone back and the game carried on treating you as though you had never left it, affecting the zone shown on the minimap and anything else that depends on it. A real zone change is now left alone.
- **Peek could leave the zoom stuck on one level** (latent since HotFix1): pressing the peek hotkey immediately after getting out of a vehicle or closing the settings menu left every situation sharing a single zoom level, so the minimap stopped reacting to interiors, combat and security areas. In toggle mode it stayed that way indefinitely.
- **Loading a save while sitting in a vehicle** (present since the original 1.7.7): produced a script error as the save came up.
- **Peek could stay stuck on after a vehicle ride** (hold mode, present since the original 1.7.7): if you were holding the peek key as you got into a vehicle that does not support peek and let go while driving, the release was ignored and the zoom stayed peeked after you got out. The release is now always registered.
- **Zoom stuck at a vehicle level while on foot**: when a quest scene took you out of a vehicle without a normal exit, the minimap could keep using a vehicle zoom on foot, with interiors, combat and security areas all ignored.
- **Closing the pause menu no longer disturbs the minimap**: opening and closing the pause menu caused a brief zoom flicker even when you had changed nothing.

## Known limitations (engine constraints)

- The peek hotkey has no effect during active combat; the game holds the minimap zoom itself while you are in combat (also true of the original 1.7.7).
- In a vehicle, the vanilla game shifts the minimap so your marker sits lower and you see more of the road ahead. That shift is incompatible with both dynamic vehicle zoom and peek-while-driving. Dynamic vehicle zoom always turns it off. With dynamic zoom off, the **Vehicle peek when no dynamic zoom** setting decides which one you get.
- Entering an interior can show a brief minimap blip (most visible on the yellow route line): the engine switches from the Exterior to the Interior zoom value as a single instant snap right at the doorway, simultaneously with the interior map mode, and the route line re-fits during that repaint. This is inherent to how 1.63 recomputes minimap zoom (no interpolation), has existed since the original 1.7.7, and gets more visible the further apart the Interior and Exterior settings are (keeping them closer together reduces it).

## Folder layout

```text
archive/   game resources (.archive + ArchiveXL manifest)
r6/        redscript sources + Input Loader hotkey mapping
native/    RED4ext plugin source (CMake, C++20, MSVC x64); see native/RESEARCH.md
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

- **djkovrik**: The original Improved Minimap Zoom mod ([v1.7.7](https://github.com/Sekers/CP77Mods/releases/tag/Improved-Minimap-Zoom-1.7.7); the last Cyberpunk 2077 Legacy compatible version).
- **Legacy2077**: Community hotfixes based off of mod version v1.7.7.
