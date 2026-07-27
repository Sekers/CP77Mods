# Research notes — Improved Minimap Zoom

Accumulated findings for the 1.63 Legacy hotfix line: how the minimap zoom
actually works, what has been tested and ruled out, and the recipes for
re-deriving any of it. Written so nobody has to rediscover this the hard way.

**Target: Cyberpunk 2077 1.63 Hotfix 1 (Legacy).** Frozen forever, so offsets
and layouts never change. RED4ext 1.15.0, redscript 0.5.14, ArchiveXL 1.5.11,
Input Loader 0.1.1, Mod Settings 0.2.0.

Most entries below are marked **tested** (observed in game or in a log) or
**inferred**. Treat inferred items as needing confirmation before you build on
them.

---

## 1. How the minimap zoom works

`gameuiMinimapContainerController` holds **six** zoom values, the "buckets":

    visionRadiusVehicle   visionRadiusCombat     visionRadiusQuestArea
    visionRadiusSecurityArea   visionRadiusInterior   visionRadiusExterior

The engine picks one per repaint from its own state. Two rules matter most:

- The **vehicle** bucket is selected from `UI_ActiveVehicleData.IsPlayerMounted`,
  not from anything the mod owns.
- The **interior** bucket comes from the engine's own interior flag, *not* from
  the security zone. Many interiors are Public or Default zones. Zone-based
  interior guesses cause two-step zoom in Public and Default interiors
  (**tested**).

**Writing the fields alone does not repaint.** The displayed radius only changes
when something makes the engine recompute. That single fact drives the whole
design: every visible change in this mod is a bucket write followed by a
deliberately provoked refresh.

**1.63 does not interpolate the radius** (**tested**, 0.1s sampler): every
transition is a clean sub-100ms snap between exact bucket values, never an
intermediate. If you see an "intermediate" value, it is a different bucket, not
a tween.

`inkWidget.GetScale()` returns garbage through redscript on 1.63, stable
pointer-sized values even on the root widget (**tested**). The live zoom is not
readable from script by any route; fields, systems and widget transforms are all
exhausted. That is why the native plugin exists. Do not retry.

---

## 2. Refresh triggers: what works and what does not

All **tested**. The dead ends cost real time, so they are recorded deliberately.

| Trigger | Result |
|---|---|
| Zone `Safe(3)` ↔ `Default(1)` flip | **The only reliable clean trigger.** Used everywhere. |
| Zone `Default(1)` ↔ `Public(2)` flip | Inert. Does not wake the recompute. |
| Combat `0` ↔ `2` flip | Inert. |
| Faking `InCombat(1)` | Refreshes, but drags the combat HUD along (outline etc). Rejected. |
| `IsPlayerMounted` change | Repaints the minimap **widget**, but see below. |

Two conditions make the zone flip inert entirely:

- **While `InCombat = 1`.** Peek therefore does nothing in combat. Inherited from
  1.7.7, not a regression.
- **While `IsPlayerMounted = true`.** This is why dirty hack #3 is load-bearing
  for far more than the marker shift.

The Safe↔Default flip has a side effect: it briefly runs the minimap through
the other **display mode**, which reads a *different* bucket. Neutralise it by
flattening every selectable bucket to one value for the flip window, then
restoring per-state values *before* the flip back, so the engine's own restore
recompute lands correctly whichever bucket it picks.

**`IsPlayerMounted` moves the marker but does not recompute the zoom**
(**tested**, frame-resolution sampler). On a vehicle exit with hack #3 inactive,
the marker recentres instantly while the displayed radius holds the vehicle
value for ~0.46s until the mod's own refresh completes. Two visible events with
a gap, frequently mistaken for a double zoom transition. Any fix premised on
"vanilla already repainted the zoom at exit" is wrong.

---

## 3. The dirty hacks

Inherited from the original mod, all still necessary.

1. **Flatten all buckets** while driving, so constant `IsPlayerMounted` swapping
   cannot flicker between different values.
2. **Fake-zone refresh at attach**, so a freshly loaded game picks up configured
   values.
3. **Clear `IsPlayerMounted` at mount.** Removes the vanilla vehicle-mode marker
   shift, *and* is what makes zone-flip refreshes work at all in a vehicle.
   Disabling it froze dynamic zoom entirely (**tested**). Vanilla look-ahead
   shift plus dynamic zoom is fundamentally impossible on 1.63; pick one.

Hack #3 fires when dynamic vehicle zoom is on **or** the static-peek opt-in is
set. Anything gated on it must read a **mount-time snapshot**
(`imzVehiclePeekAllowed`), never live config: settings refresh mid-drive, and a
live read once let the gate allow peek while hack #3 had never fired for that
mount, latching a phantom offset that applied on exit (**tested**).

---

## 4. Native offsets

`gameuiMinimapContainerController`, class size `0x488`.

| Offset | What | Source |
|---|---|---|
| `0x338` | **Live (displayed) vision radius** | memory probe |
| `0x360` | `visionRadiusVehicle` (Float) | RTTI |
| `0x364` | `visionRadiusCombat` | RTTI |
| `0x368` | `visionRadiusQuestArea` | RTTI |
| `0x36C` | `visionRadiusSecurityArea` | RTTI |
| `0x370` | `visionRadiusInterior` | RTTI |
| `0x374` | `visionRadiusExterior` | RTTI |
| `0x270–0x27C` | `psmVision` / `psmCombat` / `psmZone` / `tier` (base `gameuiMappinsContainerController`) | RTTI |
| `0x1F0–0x26F`, `0x280–0x35F`, `0x428–0x46F` | unreflected gaps; `0x338` sits in the middle one | layout analysis |

### Evidence that `0x338` is the live value, not the target

From a 1279-sample probe session:

- **Peek discriminator, conclusive.** The peek handler writes the new waypoint
  into all six buckets and *then* probes. At every press the buckets read the
  new target (100) while `0x338` still read what was on screen (60), and the
  mirror image on release. Only the displayed value behaves that way.
- **Drive sweep.** Buckets flattened to the expected speed zoom each update;
  `0x338` trailed those writes in 561 of 1273 drive rows, converging between
  refreshes. Correlation with expected zoom: 1.00.
- It was the only non-bucket float in the instance that tracked zoom at all,
  across a full-instance scan of every 4-byte offset.

Because `0x338` is unreflected it cannot be validated directly. The plugin
instead checks the two reflected landmarks it was derived from, class size
`0x488` and `visionRadiusVehicle` at `0x360`, and disables the live read if
either moves.

---

## 5. Blackboard and PSM reference

- **`PlayerStateMachine.Zones` is the SECURITY zone**, not interior/exterior:
  `1 Default, 2 Public, 3 Safe, 4 Restricted, 5 Dangerous`.
- **`gamePSMCombat`**: `0 Default, 1 InCombat, 2 OutOfCombat, 3 Stealth`. The PSM
  **idles at `OutOfCombat = 2`**, so "not in combat" must be `!= 1`, never
  `== 0`. A `== 0` gate silently broke the fake-combat dispatch (**tested**).
- **Zone writes come from script**, through
  `PlayerPuppet.SetBlackboardIntVariable(id, value)` (`player.script:5122`),
  called by `OnEnterPublicZone` (5207), `OnEnterSafeZone` (5229),
  `OnEnterRestrictedZone` (5245), `OnEnterDangerousZone` (5252). `PlayerPuppet`
  spans lines 633–5414, so all of these are its members. Nothing writes
  `Default(1)`, and `OnEnterUndefinedZone` is empty, so only four of five values
  are observable by wrapping that method.
- **`UI_ActiveVehicleData.IsPlayerMounted` is written natively.** The only script
  writer in vanilla is a debug command handler
  (`vcar_controller.script:193, OnActivateTest`), so it cannot be intercepted
  from script on the normal path.
- **Interior test**: use the global native `IsEntityInInteriorArea(entity)`
  (declared in `core/entity/gameEntity.ws`). It **extends well past doorways**,
  by roughly eight seconds of walking, so it is fine for a zoom guess and
  useless as a hard gate. Intent-guessing designs built on it (flag polling,
  proximity heuristics) were tested and rejected as unusable.

### Vanilla behaviour worth knowing

- `hudCarController.OnPlayerAttach` ends with `Reset()`, which calls
  `OnSpeedValueChanged(0.0)` **synchronously** (`car_hud.script:28-42,144`). Any
  wrap must initialise its own state *before* `wrappedMethod`.
- `hudCarController.OnSpeedValueChanged` takes `AbsF(speedValue)` before its
  curve lookup. Reverse reports negative speed; feeding it raw pins the zoom.
- `hudCarController.OnUnmountingEvent` only unregisters its speed listener when
  `!silentUnmount`, so speed updates can keep arriving on foot after a silent
  unmount (quest scenes).
- `JournalNotificationQueue.OnPlayerDetach` (`journalNotification.script:135-140`)
  never unregisters its mount listener, only the journal callback and the
  transaction listener.
- Class chain: `MinimapContainerController` → `MappinsContainerController` →
  `inkProjectedHUDGameController` → `inkHUDGameController` → `inkGameController`,
  so it does receive UI-system queued events.
- **Loading a save inside a vehicle produces no mount event this controller
  sees** (**tested**), so the vehicle zoom must be applied at attach or the
  minimap sits on the on-foot value for the whole drive.

---

## 6. Input contexts

Verified in `r6\config\inputContexts.xml` (**tested**).

- `UIShared` has exactly **two** includers: `UIExploration` (line 516) and
  `UIMenuShared` (813).
- `UIExploration` is included by `Exploration` (56) **and all eight vehicle
  contexts** (261–419: VehiclePassenger, VehicleOnlyForward, VehicleNoDrive,
  VehicleNoDriveCombat, VehicleDrive, VehicleTankDrive, VehicleDriverCombat,
  VehicleCombat). `Aiming` includes `Exploration`; `Vision` includes `Aiming`.

So appending an action to `UIShared` also makes it fire inside the map,
inventory and pause menus. Appending to `UIExploration` keeps gameplay, aiming
and every vehicle context while dropping the menus. This mod targets
`UIExploration`. `Braindance`, `DeviceControl` and `Dead` reach neither.

Input Loader writes the merged result to `r6\cache\inputContexts.xml` and
`inputUserMappings.xml` at launch, which is a good way to confirm a modded
action actually merged.

**`EInputKey` names** (verified against the RTTI dump and vanilla
`inputUserMappings.xml`): `IK_LeftMouse` / `IK_RightMouse` / `IK_MiddleMouse` /
`IK_Mouse4` / `IK_Mouse5`, `IK_LShift` / `IK_RShift`, `IK_LControl` /
`IK_RControl`, `IK_CapsLock`, `IK_PageUp` / `IK_PageDown`. There is no separate
left/right Alt, only `IK_Alt`. The old Nexus readme list is partly bogus:
`IK_MOUSE1..5`, `IK_LEFTSHIFT`-style caps, `IK_Pad_LeftRightShoulder` and
`IK_PAD_LR_THUMB` do not exist.

---

## 7. Localization

The game ships **18 text languages**. `archive\pc\content\` holds 19 `lang_*`
archives, but one is `lang_en_voice`, so count text only.

**ArchiveXL locale keys use country-doubled forms, not ISO**: `cz-cz`, `jp-jp`
and **`kr-kr`** (not `ko-kr`). Confirmed against other shipped mods in this
repository, which also confirm `pl-pl`, `pt-br`, `th-th`, `tr-tr`. `es-mx` and
`hu-hu` have no in-repo precedent.

An unmapped language resolves every key to `""`, which shows raw `Mod-IMZ-*`
keys in the settings menu **and** trips this mod's own resource check into
reporting a missing archive on a correct install. Map every language, pointing
the untranslated ones at an existing json; no archive rebuild is needed.

Do not put YAML comments in a shipped `.xl`. None of the mods in this repository
do, the parser's comment support is unverified, and that file is load-bearing
for all localization.

---

## 8. Mod Settings 0.2.0

- Renders **plain-string** `displayName` / `category` / `description` values,
  falling back to the raw string when a loc key misses (**tested in game**, 4K
  and 1080p). New settings therefore need no archive or loc edits. The trade-off
  is that such a label stays English in every language.
- Appends "(Confirmation Required)" to every description itself; nothing to do
  with the mod.
- Has **no key-capture widget** and **no button widget**, and the 1.63 bindings
  menu cannot list modded actions. A hotkey rebind UI is not achievable; users
  edit the input XML.
- Ships **zero `.reds`** on 1.63: its script classes are injected by the dll, so
  third-party scripts cannot compile calls against it and must not declare those
  classes themselves. The only safe route is RTTI name lookup from a native
  plugin.
- Label convention for this mod: sentence case. Avoid ending a Bool's label in
  "off" or "on", since it sits beside the ON/OFF state and reads contradictory.

---

## 9. Diagnostics

### Sandbox compile without launching the game

Catches syntax and type errors in seconds. Stage a scratch tree, copy the game's
`r6\cache\final.redscripts.bk` in as `final.redscripts`, copy the mod scripts
under `<scratch>\r6\scripts\`, then:

```
engine\tools\scc.exe -compile "<scratch>\r6\scripts"
```

Exit 0 plus "Compilation complete" means valid. **Never point `scc` at the live
game directory.**

### Runtime logging

`IMZLog` is a no-op until you uncomment its `LogChannel` call. Output lands in
the CET console and in
`bin\x64\plugins\cyber_engine_tweaks\gamelog.log`, which is readable directly.

### Live-radius sampler

The reusable pattern for anything timing-related: a self-requeuing `DelayEvent`
that logs `IMZ_GetMinimapRadius` plus all six buckets, the state flags and the
PSM zone. 50ms resolves ordinary transitions; ~16ms is roughly one sample per
frame. Higher frame rates make such tests *more* sensitive, not less, since more
frames land inside the window.

Log **both** `IsPlayerMounted` and `IsMounted_IMZ`. Omitting them once left a
"no repaint at exit" result unexplained for a whole round.

### Memory probe

`IMZ_DumpMinimapMemory(ctrl, expectedZoom, tag)` is compiled into the shipped
dll but inert: nothing declares or calls it, and it creates files only when
called. First call writes `imz_props.txt` (RTTI class chain, sizes and every
reflected property offset) and starts `imz_mem.csv` (one column per 4-byte
offset). Read-only and bounded by the RTTI class size.

To use it, add temporary redscript (remove afterwards, since the declaration
makes the plugin a hard script dependency):

```reds
public static native func IMZ_DumpMinimapMemory(ctrl: ref<IScriptable>, expectedZoom: Float, tag: String) -> Void

// in OnSpeedValueChanged_IMZ, after newZoom:
IMZ_DumpMinimapMemory(this, newZoom, "drive");
// in the OnAction peek block, after the waypoint is set:
IMZ_DumpMinimapMemory(this, this.imzTargetZoom, "peek");
```

Protocol: dynamic zoom on, drive ~30s with strong speed variation, then a few
peek presses on foot, then quit. Analysis: per column compute range, distinct
count and correlation against `expectedZoom` over the drive rows. Real values
live in ~20–200. Columns exactly equal to expected are the six buckets, useful
as landmarks. A column that tracks *with lag* is live state. The peek rows
separate live from target.

---

## 10. Gotchas

Each of these cost real debugging time.

- **`Log::` output does not reach `red4ext.log`.** It goes to
  `OutputDebugString`, visible only with a debugger or DebugView. A native
  failure can therefore be completely silent, and absence of an error line in
  `red4ext.log` proves nothing about it.
- **`CClass::props` is not the whole story.** It holds the class's own reflected
  properties; `CClass::unk118` additionally holds **native-only** reflected
  entries, which is where the `visionRadius*` fields live. A `props`-only search
  finds nothing and looks like a layout mismatch. Neither collection contains
  truly unreflected fields such as `0x338`.
- **`@addField` script fields are not in instance memory.** Their RTTI offsets
  are relative to a separate script-data holder (`CClass::holderSize`), so
  reading them from the native instance returns garbage. Only native properties'
  offsets are instance-relative.
- **SDK version gate.** RED4ext 1.15.0 refuses plugins built against SDK ≥ 0.5.0.
  Build against the pinned commit `046877f9`
  (`github.com/Sekers/RED4ext.SDK`, tag `SDK-Release-CyberPunk2077-1.63-HF1`).
  Do not update it; newer checkouts also describe post-1.63 struct layouts.
- **Runtime declaration.** `RED4EXT_RUNTIME_LATEST` resolves to a post-1.63
  patch in that checkout and makes RED4ext skip the plugin. The explicit
  `RED4EXT_RUNTIME_1_63_HOTFIX_1` loads correctly (**tested**) and is the right
  choice for a plugin reading a version-specific offset.
- **`std::bit_cast` compile error.** The 1.63-era SDK uses it without including
  `<bit>`; include `<bit>` before any RED4ext header.
- **No hot reload.** Every `.reds` change needs a full game restart. Reports of
  "the fix didn't work" are often stale-script artefacts.
- **No 1.63 decompile exists publicly.** The codeberg `adamsmasher/cyberpunk`
  repository jumps from `v1.62` straight to `v2.0`. Use the game's own
  `tools\redmod\scripts\`, which is the actual 1.63 HF1 source, plus the RTTI
  dump for native classes.

---

## 11. Build and package

```
cmake -S native -B native/build -G "Visual Studio 17 2022" -A x64
cmake --build native/build --config Release
```

Output: `native\build\bin\Release\ImprovedMinimapZoom_Native.dll`, deployed to
the game's `red4ext\plugins\ImprovedMinimapZoom\`. Output directories are split
per configuration so a Debug build cannot overwrite the Release binary that
packaging picks up.

`Make-Release-Zip.ps1` builds Release itself, packages from an explicit
allowlist, refuses a dll older than the newest file in `native\Plugins`,
reopens the archive to hash-verify every entry, and writes a SHA-256 sidecar.
