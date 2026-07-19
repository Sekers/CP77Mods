# Native offset research — Improved Minimap Zoom Native

How the native lookup values used by this plugin were found, with a repeatable
recipe so the research never has to be redone from scratch.

**Game target: Cyberpunk 2077 1.63 Hotfix 1 (Legacy) — frozen forever, offsets never change.**
RED4ext 1.15.0. SDK: https://github.com/Sekers/RED4ext.SDK commit `046877f9`
(tag `SDK-Release-CyberPunk2077-1.63-HF1`), fetched automatically at CMake
configure time into the git-ignored `build\` folder (see Plugins/CMakeLists.txt;
set `RED4EXT_SDK_DIR` to use a local checkout instead).

## Offset table — `gameuiMinimapContainerController` (class size 0x488)

| Offset | What | Source |
|--------|------|--------|
| `0x338` | **Live (displayed, interpolated) vision radius** — the value on screen right now | discovered via memory probe (below) |
| `0x360` | `visionRadiusVehicle` (Float) | RTTI (reflected) |
| `0x364` | `visionRadiusCombat` (Float) | RTTI |
| `0x368` | `visionRadiusQuestArea` (Float) | RTTI |
| `0x36C` | `visionRadiusSecurityArea` (Float) | RTTI |
| `0x370` | `visionRadiusInterior` (Float) | RTTI |
| `0x374` | `visionRadiusExterior` (Float) | RTTI |
| `0x270–0x27C` | `psmVision` / `psmCombat` / `psmZone` / `tier` (base class `gameuiMappinsContainerController`) | RTTI |
| `0x1F0–0x26F`, `0x280–0x35F`, `0x428–0x46F` | Unreflected gaps holding native-only state (0x338 lives in the middle one) | layout analysis |

Full reflected layout of the whole class chain: run the probe once — it writes
`imz_props.txt` next to the dll (a previous capture's content is the layout
listing generated on 2026-07-14; regenerate anytime).

## Evidence that 0x338 is the LIVE radius (not the target)

From the probe session (2026-07-14, 1279 samples):

- **Peek discriminator (conclusive):** the mod's peek handler writes the new
  waypoint into all six buckets and *then* calls the probe. At every peek
  press, buckets read the new target (e.g. 100) while `0x338` still read the
  value on screen at that instant (60) — and the mirror image on release
  (buckets 60, `0x338` 100). Only the *displayed* value behaves like that.
- **Drive sweep:** with dynamic zoom on, buckets are flattened to the expected
  speed zoom each update; `0x338` trailed the bucket writes mid-interpolation
  (e.g. bucket 84.5 while `0x338` = 83.9) in 561 of 1273 drive rows,
  converging between refreshes. Correlation with the expected zoom: 1.00.
- It was the ONLY non-bucket float in the instance that tracked the zoom at
  all (full-instance scan, every 4-byte offset, range/correlation filtered).

## Repeatable probe recipe (find more offsets later)

The research native is still compiled into the shipped dll:

```
IMZ_DumpMinimapMemory(ctrl: ref<IScriptable>, expectedZoom: Float, tag: String) -> Void
```

First call per session writes `imz_props.txt` (RTTI class chain: sizes + every
reflected property offset) and starts `imz_mem.csv` (header = one column per
4-byte offset). Every call appends one CSV row: `tick_ms, tag, expectedZoom`,
then the instance memory reinterpreted as floats (`NA` for non-finite). Both
files land next to the dll. Read-only, bounded by the RTTI class size — cannot
corrupt anything.

To wire it up, add TEMP redscript to the mod (remove afterwards — the
declaration makes the plugin a hard script dependency):

```reds
// TEMP: declaration (own file, e.g. imznative_temp.reds)
public static native func IMZ_DumpMinimapMemory(ctrl: ref<IScriptable>, expectedZoom: Float, tag: String) -> Void

// TEMP: in MinimapContainerController.OnSpeedValueChanged_IMZ, after newZoom is computed:
IMZ_DumpMinimapMemory(this, newZoom, "drive");

// TEMP: in the OnAction peek block, after the waypoint is set:
IMZ_DumpMinimapMemory(this, this.imzTargetZoom, "peek");
```

Session protocol: dynamic zoom ON → drive ~30s with strong speed variation
(slow crawl → top speed → brake) → a few peek presses/releases on foot → quit.

Analysis criteria: per CSV column compute range / distinct count / correlation
against `expectedZoom` over the `drive` rows. Real values live in ~20–200.
Columns exactly equal to expected = the six buckets (known offsets — sanity
landmarks). A column that *tracks with lag* = interpolated live state. Use the
`peek` rows to separate live from target: at the peek instant the buckets
already hold the new target while the live value still holds the old one.

## Gotchas (each cost real debugging time)

- **`@addField` script fields are NOT in instance memory.** Their RTTI
  property offsets are relative to a separate script-data holder (`CClass::holderSize`),
  not the native instance. Reading e.g. `imzCurrentZoom` "at 0x1E0" from the
  instance returns garbage. Only *native* properties' offsets are
  instance-relative.
- **SDK version gate:** RED4ext 1.15.0 refuses plugins built against SDK
  ≥ 0.5.0 (`uses RED4ext.SDK v0.5.0 which is not supported`). Build against
  the vendored commit `046877f9` — do NOT update that clone. Newer SDK
  checkouts also describe post-1.63 struct layouts.
- **Runtime gate:** the SDK's `RED4EXT_RUNTIME_LATEST` may resolve to a
  post-1.63 game version and make RED4ext skip the plugin as incompatible.
  This plugin uses `RED4EXT_RUNTIME_INDEPENDENT` (same choice as
  RED4.RTTIDumper).
- **`std::bit_cast` compile error:** the 1.63-era SDK uses `std::bit_cast`
  without including `<bit>`; include `<bit>` before any RED4ext header
  (see Main.cpp / MinimapDump.cpp).
- **RTTI property arrays:** `CClass::props` holds the class's own reflected
  props; `CClass::unk118` additionally contains native-only reflected entries.
  Neither contains truly unreflected fields (like 0x338) — those are only
  findable by memory probing.

## Build

```
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release
```

Output: `build\bin\ImprovedMinimapZoom_Native.dll` (also copied to
`Module\red4ext\plugins\ImprovedMinimapZoom\`). Deploy to the game's
`red4ext\plugins\ImprovedMinimapZoom\`.
