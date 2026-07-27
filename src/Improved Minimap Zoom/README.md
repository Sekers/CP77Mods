# Improved Minimap Zoom — 1.7.7 Community Hotfixes (Game 1.63 Legacy)

Community-maintained hotfixes for [Improved Minimap Zoom](https://www.nexusmods.com/cyberpunk2077/mods/2959) by djkovrik, version **1.7.7** — the last release compatible with Cyberpunk 2077 **1.63 Legacy** (with Hotfix 1). Upstream development moved on to game 2.x; these branches keep the Legacy version working and polished.

## Releases

| Release | Branch | What it is |
| --- | --- | --- |
| `Improved-Minimap-Zoom-1.7.7-HF1` | `fix-minimap-1.7.7-HF1` | Fixes only, with no new requirements: the crash when getting out of a vehicle, and the peek hotkey's two-step zoom. The hotfix release is a complete package; uninstall other versions of IMZ before installing. |
| `Improved-Minimap-Zoom-1.7.7-HF2` | `fix-minimap-1.7.7-HF2-Native` | Everything in HotFix1, plus a small plugin bundled with the mod that lets it see the zoom currently on screen, which makes the peek hotkey land exactly right everywhere. Also adds peek while driving, finer settings sliders, settings that apply straight away, and a set of smaller fixes (all listed below). The plugin is installed for you by the zip and needs RED4ext, which the mod's other dependencies already required. The hotfix release is a complete package; uninstall other versions of IMZ before installing. |

## New in HF2

- **Peek while driving**: the peek hotkey now also works in vehicles, zooming out on top of the vehicle zoom and returning on release. It is always available when dynamic vehicle zoom is enabled. When dynamic zoom is off the mod keeps the vanilla vehicle-mode minimap downward shift by default, which is incompatible with peek. You can enable the new **Vehicle peek when no dynamic zoom** setting to trade the shift for peek support.
- **Finer settings sliders**: all zoom and speed sliders move in steps of 1 (was 5), and the peek increment can go as low as 5 (was 20).
- **Instant settings**: zoom settings apply the moment the Mod Settings menu closes.
- **Reversing zooms out like driving forward**: backing up used to sit at the closest zoom however fast you were going. Reverse speed now widens the minimap exactly the way forward speed does.

## Fixed in HF2

- **Peek landed on the wrong zoom** (present since the original 1.7.7): peek guessed at the zoom it was starting from, so it overshot or came back to the wrong level near building entrances and in quest areas, and a rapid double-tap could dip past where you started. It now measures from the zoom *actually on screen* and lands exactly right everywhere. This is what the bundled plugin is for. HotFix1 had already fixed the related two-step zoom; this finishes the job.
- **Zoom blip when leaving a vehicle** (present since the original 1.7.7): every time you got out, the minimap flickered through a wrong zoom level before settling (more noticeable the further apart your Interior and Exterior settings are). The transition is now a single clean step.
  - Note: With both dynamic vehicle zoom and vehicle peek turned off you also keep the vanilla game's own vehicle marker shift, and that marker slides back to centre the instant you step out while the zoom follows a fraction of a second later (the short delay prevents the pre-HF1 crash), so the two can look like separate changes.
- **Getting straight back into a vehicle showed the wrong zoom** (present since the original 1.7.7): hopping back in within about a third of a second of stepping out left the minimap on the on-foot zoom instead of switching to the vehicle one. With dynamic vehicle zoom turned off it stayed wrong for the rest of the drive.
- **Peek hotkey no longer fires inside menus** (present since the original 1.7.7): the hotkey was reachable from the map, inventory and pause menus. It is now bound to gameplay and vehicles only.
- **Settings menu shows up in every language** (present since the original 1.7.7): the mod shipped translations for 11 of the game's 18 text languages, and players on any of the other seven (Polish, Brazilian Portuguese, Korean, Hungarian, Thai, Turkish, Latin American Spanish) saw raw text keys in the settings menu *and* a false "resource files not detected!" error on the main menu even with the mod installed correctly. Those seven now fall back to English (Latin American Spanish falls back to Spanish), covering all 18.
- **Interior zoom dead after driving** (regression introduced in HotFix1): once you had driven anywhere, the Interior, Combat and Security Area zooms stopped applying; everything stayed at the Exterior level until you next used the peek hotkey or changed a setting.
- **Wrong security zone after a zoom change** (present since the original 1.7.7): to make the minimap redraw, the mod briefly tells the game you are in a different security zone, then puts the real one back about a tenth of a second later. If you genuinely crossed into a new zone inside that window (e.g., walking into a shop just as the zoom changed), the mod wrote the old zone back over the real one, and the game kept treating you as though you were still outside until the next time you crossed a boundary. That could show the wrong zone name on the minimap, or leave the game not making you put your weapon away where it normally would. A real zone change is now left alone.
- **Peek could leave the zoom stuck on one level** (latent since HotFix1): pressing the peek hotkey immediately after getting out of a vehicle or closing the settings menu left every situation sharing a single zoom level, so the minimap stopped reacting to interiors, combat and security areas. In toggle mode it stayed that way indefinitely.
- **Loading a save while sitting in a vehicle** (present since the original 1.7.7): produced a script error as the save came up, and the minimap then used the on-foot Exterior zoom for the whole drive instead of the vehicle zoom.
- **Peek could stay stuck on after a vehicle ride** (hold mode, present since the original 1.7.7): if you were holding the peek key as you got into a vehicle that does not support peek and let go while driving, the release was ignored and the zoom stayed peeked after you got out. The release is now always registered.
- **Zoom stuck at a vehicle level while on foot** (present since the original 1.7.7): when a quest scene took you out of a vehicle without a normal exit, the minimap could keep using a vehicle zoom on foot, with interiors, combat and security areas all ignored.

## Known limitations (engine constraints)

- The peek hotkey has no effect during active combat; the game holds the minimap zoom itself while you are in combat (also true of the original 1.7.7).
- In a vehicle, the vanilla game shifts the minimap so your marker sits lower and you see more of the road ahead. That shift is incompatible with both dynamic vehicle zoom and peek-while-driving. Dynamic vehicle zoom always turns it off. With dynamic zoom off, the **Vehicle peek when no dynamic zoom** setting decides which one you get.
- Entering an interior can show a brief minimap blip, most visible on the yellow route line: the zoom jumps to the Interior value in one step right at the doorway, at the same moment the map switches to its interior mode, and the route line redraws as that happens. The game changes minimap zoom in instant steps rather than easing between values, so this cannot be smoothed out. It has existed since the original 1.7.7, and gets more visible the further apart your Interior and Exterior settings are (keeping them closer together reduces it).

## Folder layout

```text
archive/      game resources (.archive + ArchiveXL manifest)
r6/           redscript sources + Input Loader hotkey mapping
native/       RED4ext plugin source (CMake, C++20, MSVC x64)
releases/     built release zips
RESEARCH.md   research notes for the mod
```

Open `Improved Minimap Zoom.code-workspace` in VS Code to get both the repo and the native plugin configured (C++ IntelliSense activates for `native/` once the project has been configured at least once).

## Building the native plugin

```text
cmake -S native -B native/build -G "Visual Studio 17 2022" -A x64
cmake --build native/build --config Release
```

The RED4ext.SDK is fetched automatically at configure time, pinned to the 1.63-HF1 commit of [Sekers/RED4ext.SDK](https://github.com/Sekers/RED4ext.SDK) (`046877f9`). Output: `native/build/bin/ImprovedMinimapZoom_Native.dll` (also published to `native/Module/red4ext/plugins/ImprovedMinimapZoom/`). The dll ships only inside release zips; it is never committed to the repository.

[`RESEARCH.md`](RESEARCH.md) collects the research notes for the whole mod: how minimap zoom works on 1.63, which refresh triggers do and do not work, the native offset table and how it was found, blackboard and input-context reference, and the diagnostic recipes.

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
