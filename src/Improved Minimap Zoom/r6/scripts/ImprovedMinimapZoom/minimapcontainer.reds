import ImprovedMinimapMain.ZoomConfig
import ImprovedMinimapUtil.*

// IF YOU READ THIS - THERE ARE A FEW DIRTY HACKS RIGHT HERE :(
// Minimap widget reloading with new zoom values can be triggered only by a few events like combat mode,
// active zone or mount state change so I constantly swap player zone flag while driving =\

// Patch 1.3 added minimap internal container offset for vehicle minimap mode so
// I disabled it with IsPlayerMounted bb value reset inside VehicleComponent OnUnmountingEvent


// -- Events

public class ForceIMZExteriorRefreshEvent extends Event {
  public let generation: Int32;
}

@addMethod(PlayerPuppet)
protected cb func OnForceIMZExteriorRefreshEvent(evt: ref<ForceIMZExteriorRefreshEvent>) -> Bool {
  // Stale: a mount transition happened after this was queued
  if evt.generation != this.imzMountGeneration {
    IMZLog("Ignored stale post-unmount refresh from an earlier mount generation");
    return true;
  };
  // Fires 0.35s after unmount, once imzJustUnmounted is cleared. The exit path
  // flattened all buckets to the exterior value for the immediate visual, and
  // leaving them flat would kill interior/combat/security zoom until the next
  // peek or settings-close — so the per-state values have to go back.
  // Neutralized: writing them BEFORE the zone flip would expose the flip's
  // display-mode detour for ~0.1s, i.e. a zoom blip on every vehicle exit.
  if IsDefined(this.imzMinimapController) {
    // Re-mounting inside the 0.35s window makes this stale: the vehicle path
    // owns the buckets again, and per-state values here would replace the
    // speed-based flatten with visionRadiusVehicle until the next speed update
    if this.imzMinimapController.imzIsActuallyMounted {
      IMZLog("Skipped post-unmount refresh (re-mounted during the window)");
      return true;
    };
    this.imzMinimapController.ApplyConfiguredZoomNeutralized_IMZ();
  } else {
    this.ForceMinimapRefreshWithFakeZone();
  };
  return true;
}


// -- Native zoom fields, magic happens here

// In vehicle
@addField(MinimapContainerController)
native let visionRadiusVehicle: Float;

// In combat
@addField(MinimapContainerController)
native let visionRadiusCombat: Float;

// Quest area
@addField(MinimapContainerController)
native let visionRadiusQuestArea: Float;

// Restricted area
@addField(MinimapContainerController)
native let visionRadiusSecurityArea: Float;

// Interior
@addField(MinimapContainerController)
native let visionRadiusInterior: Float;

// Exterior which does not fit above options
@addField(MinimapContainerController)
native let visionRadiusExterior: Float;


// -- Fields

@addField(MinimapContainerController)
public let imzBlackboard: ref<IBlackboard>;

@addField(MinimapContainerController)
public let imzIsMountedBlackboard: ref<IBlackboard>;

@addField(MinimapContainerController)
public let imzSpeedTrackCallback: ref<CallbackHandle>;

@addField(MinimapContainerController)
public let imzIsMountedCallback: ref<CallbackHandle>;

@addField(MinimapContainerController)
public let imzIsActuallyMountedCallback: ref<CallbackHandle>;

@addField(MinimapContainerController)
public let imzPlayer: wref<PlayerPuppet>;

@addField(MinimapContainerController)
public let imzConfig: ref<ZoomConfig>;

@addField(MinimapContainerController)
public let imzCurrentZoom: Float;

// Target zoom value — all zoom changes now converge toward this instead of snapping
@addField(MinimapContainerController)
public let imzTargetZoom: Float;

@addField(MinimapContainerController)
public let imzPeekActive: Bool;

// Displayed zoom at the moment peek was pressed — floor for the release
// waypoint so a rapid release mid-motion cannot dip below the starting zoom.
// Only consulted within 0.5s of the press (imzPeekPressTime): after that the
// press motion has settled and the value may be stale (the player can walk
// into a different-zoom area while holding peek).
@addField(MinimapContainerController)
public let imzPeekBaseZoom: Float;

@addField(MinimapContainerController)
public let imzPeekPressTime: Float;

// Track actual mounted state (used to block manual peek while driving)
@addField(MinimapContainerController)
public let imzIsActuallyMounted: Bool;

// Whether peek is usable in the vehicle currently mounted — snapshotted at
// mount because hack #3 (the IsPlayerMounted reset that makes the refresh work
// in vehicles) is decided there. Reading the live config instead would let a
// mid-drive settings change disagree with what hack #3 actually did.
@addField(MinimapContainerController)
public let imzVehiclePeekAllowed: Bool;


// Methods

// Event-driven convergence — vanilla-safe replacement for snap-based zoom (non-vehicle)
@addMethod(MinimapContainerController)
public func UpdateZoom_IMZ() -> Void {
  this.imzCurrentZoom = this.imzTargetZoom;
  this.WriteAllBuckets_IMZ(this.imzCurrentZoom);
}

@addMethod(MinimapContainerController)
protected cb func OnSpeedValueChanged_IMZ(speed: Float) -> Bool {
  // Speed updates are meaningless on foot, and applying one would flatten the
  // on-foot buckets (WriteAllBuckets_IMZ) with nothing scheduled to restore them; the zoom
  // would stay wrong until the next peek, settings change or mount. Reachable
  // after a SILENT unmount: vanilla hudCarController only unregisters its speed
  // listener when !silentUnmount, so it keeps pushing speed while on foot.
  if !this.imzIsActuallyMounted {
    return true;
  };

  if this.imzConfig.isDynamicZoomEnabled {
    // Peek while driving rides the dynamic zoom: speed updates keep flowing
    // with the peek amount added on top
    let peekOffset: Float = this.imzPeekActive ? this.imzConfig.peek : 0.0;
    let newZoom: Float = ZoomCalc.GetForSpeed(speed, this.imzConfig) + peekOffset;
    IMZLog("New zoom available: " + ToString(newZoom));

    // Vehicle dynamic zoom must snap + force refresh (no per-frame tick in vanilla redscript)
    if NotEquals(this.imzCurrentZoom, newZoom) && IsDefined(this.imzPlayer) {
      this.imzCurrentZoom = newZoom;
      this.imzTargetZoom = newZoom;
      this.HackAllZoomValues_IMZ(newZoom);
    };
  };
  return true;
}

@addMethod(MinimapContainerController)
protected cb func OnMountedStateChanged_IMZ(value: Bool) -> Bool {
  IMZLog("! OnMountedStateChanged " + ToString(value));
  return true;
}

@addMethod(MinimapContainerController)
protected cb func OnActualMountedStateChanged_IMZ(value: Bool) -> Bool {
  IMZLog("! OnActualMountedStateChanged " + ToString(value));
  this.imzIsActuallyMounted = value;

  // Vehicle enter detected — apply initial vehicle zoom immediately (even at 0 speed).
  // A toggle-latched peek carries in only where vehicle peek is available:
  // otherwise the peek key is inert in vehicles and an applied offset could
  // never be released until exiting
  if value && IsDefined(this.imzPlayer) {
    // Invalidates any post-unmount events still in flight from the exit that
    // preceded this mount, and clears imzJustUnmounted synchronously so the
    // discarded clear event is not the only thing that would have done it
    this.imzPlayer.BumpMountGeneration_IMZ();

    // Snapshot what hack #3 just decided for this mount (same synchronous
    // block: OnMountingEvent sets IsMounted_IMZ immediately before its check)
    this.imzVehiclePeekAllowed = this.VehiclePeekEnabled_IMZ();

    let speed: Float = this.imzBlackboard.GetFloat(GetAllBlackboardDefs().UI_System.CurrentSpeed_IMZ);
    let peekOffset: Float = this.imzPeekActive && this.imzVehiclePeekAllowed ? this.imzConfig.peek : 0.0;
    let newZoom: Float = ZoomCalc.GetForSpeed(speed, this.imzConfig) + peekOffset;

    this.imzCurrentZoom = newZoom;
    this.imzTargetZoom = newZoom;
    this.HackAllZoomValues_IMZ(newZoom);
    return true;
  };

  // Vehicle exit detected — mark post-unmount window
  if !value && IsDefined(this.imzPlayer) {
    // Bump first: this exit's own delayed events must carry the new generation,
    // and any left over from a previous cycle are invalidated here
    this.imzPlayer.BumpMountGeneration_IMZ();
    this.imzPlayer.imzJustUnmounted = true;

    let clearEvt: ref<ClearIMZUnmountFlagEvent> = new ClearIMZUnmountFlagEvent();
    clearEvt.generation = this.imzPlayer.imzMountGeneration;
    GameInstance.GetDelaySystem(this.imzPlayer.GetGame())
      .DelayEvent(this.imzPlayer, clearEvt, 0.3);

    // Update configured zoom values (this will NOT refresh during the unmount window due to the guard)
    this.SetPreconfiguredZoomValues_IMZ();

    // Restore exterior zoom values immediately (visual fields)
    this.imzCurrentZoom = this.visionRadiusExterior;
    this.imzTargetZoom = this.imzCurrentZoom;
    this.UpdateZoom_IMZ();

    // Critical: refresh AFTER the unmount window clears, otherwise ForceMinimapRefreshWithFakeZone() is skipped
    let refreshEvt: ref<ForceIMZExteriorRefreshEvent> = new ForceIMZExteriorRefreshEvent();
    refreshEvt.generation = this.imzPlayer.imzMountGeneration;
    GameInstance.GetDelaySystem(this.imzPlayer.GetGame())
      .DelayEvent(this.imzPlayer, refreshEvt, 0.35);
  };

  return true;
}

@addMethod(MinimapContainerController)
func InitBBs_IMZ(playerGameObject: ref<GameObject>) -> Void {
  this.imzPlayer = playerGameObject as PlayerPuppet;
  this.imzConfig = new ZoomConfig();
  this.imzBlackboard = GameInstance.GetBlackboardSystem(playerGameObject.GetGame()).Get(GetAllBlackboardDefs().UI_System);
  this.imzSpeedTrackCallback = this.imzBlackboard.RegisterListenerFloat(GetAllBlackboardDefs().UI_System.CurrentSpeed_IMZ, this, n"OnSpeedValueChanged_IMZ");
  this.imzIsMountedBlackboard = GameInstance.GetBlackboardSystem(playerGameObject.GetGame()).Get(GetAllBlackboardDefs().UI_ActiveVehicleData);
  this.imzIsMountedCallback = this.imzIsMountedBlackboard.RegisterListenerBool(GetAllBlackboardDefs().UI_ActiveVehicleData.IsPlayerMounted, this, n"OnMountedStateChanged_IMZ");
  this.imzIsActuallyMountedCallback = this.imzBlackboard.RegisterListenerBool(GetAllBlackboardDefs().UI_System.IsMounted_IMZ, this, n"OnActualMountedStateChanged_IMZ");

  this.imzIsActuallyMounted = this.imzBlackboard.GetBool(GetAllBlackboardDefs().UI_System.IsMounted_IMZ);
  // Config-based seed for the case where the player is already mounted at
  // attach (save loaded in a vehicle) and no mount event replays
  this.imzVehiclePeekAllowed = this.VehiclePeekEnabled_IMZ();

  // Store reference to this controller on the player so events can access it
  this.imzPlayer.imzMinimapController = this;
}

// Each listener is torn down on its own terms. The previous all-or-nothing
// guard meant one undefined blackboard leaked every registration, including
// ones that were made successfully.
@addMethod(MinimapContainerController)
public func ClearBBs_IMZ() -> Void {
  // Handles are nulled as they are released so a second teardown is a no-op
  // rather than an unregister against a dead handle
  if IsDefined(this.imzBlackboard) && IsDefined(this.imzSpeedTrackCallback) {
    this.imzBlackboard.UnregisterListenerFloat(GetAllBlackboardDefs().UI_System.CurrentSpeed_IMZ, this.imzSpeedTrackCallback);
    this.imzSpeedTrackCallback = null;
  };
  if IsDefined(this.imzIsMountedBlackboard) && IsDefined(this.imzIsMountedCallback) {
    this.imzIsMountedBlackboard.UnregisterListenerBool(GetAllBlackboardDefs().UI_ActiveVehicleData.IsPlayerMounted, this.imzIsMountedCallback);
    this.imzIsMountedCallback = null;
  };
  if IsDefined(this.imzBlackboard) && IsDefined(this.imzIsActuallyMountedCallback) {
    this.imzBlackboard.UnregisterListenerBool(GetAllBlackboardDefs().UI_System.IsMounted_IMZ, this.imzIsActuallyMountedCallback);
    this.imzIsActuallyMountedCallback = null;
  };

  // Only disown the back reference if it still points here. A newer controller
  // may already have claimed it, and wiping that would strand every event that
  // dispatches through the player.
  if IsDefined(this.imzPlayer) && Equals(this.imzPlayer.imzMinimapController, this) {
    this.imzPlayer.imzMinimapController = null;
  };
}

// Vehicle peek needs hack #3's IsPlayerMounted reset at mount (fired for
// dynamic zoom or the static-peek opt-in) — without it the zone-flip refresh
// is inert in vehicles. Config-based like the mount-time gate, so a settings
// change applies on the next vehicle entry.
@addMethod(MinimapContainerController)
public func VehiclePeekEnabled_IMZ() -> Bool {
  return this.imzConfig.isDynamicZoomEnabled || this.imzConfig.staticVehiclePeek;
}

// Returns the visionRadius value the game will use for the given zone
@addMethod(MinimapContainerController)
public func GetZoomForZone_IMZ(zone: Int32) -> Float {
  // gamePSMZones: 1 = Default, 2 = Public, 3 = Safe, 4 = Restricted, 5 = Dangerous
  let result: Float = this.visionRadiusExterior;
  switch zone {
    case 4:
    case 5:
      result = this.visionRadiusSecurityArea;
      break;
    case 3:
      result = this.visionRadiusInterior;
      break;
    default:
      break;
  };
  return result;
}

// FALLBACK waypoint (peek offset included) for the swap window, used only if
// the native plugin's live-radius read fails. Read from config — never from
// the visionRadius fields, which may already be flattened.
// The interior bucket is selected by the engine's interior flag, NOT the
// security zone: many interiors are Public/Default zones. Near doorways the
// flag extends outside while the minimap still displays the exterior zoom, and
// that mismatch is undetectable from script (no readable minimap state in
// 1.63 RTTI) — so for flag-true spots we flatten to min(interior, exterior) +
// peek for BOTH press and release: exact for real interiors, and monotonic (no
// overshoot dip) for the wrongly flagged doorway strips. The restore recompute
// always lands on the engine's own correct value either way.
@addMethod(MinimapContainerController)
public func GetPeekFlattenValue_IMZ(zone: Int32, combat: Int32) -> Float {
  let peekOffset: Float = this.imzPeekActive ? this.imzConfig.peek : 0.0;
  let result: Float = this.imzConfig.exterior + peekOffset;
  // Driving: the base is the speed-derived zoom, not a zone bucket
  if this.imzIsActuallyMounted {
    let speed: Float = this.imzBlackboard.GetFloat(GetAllBlackboardDefs().UI_System.CurrentSpeed_IMZ);
    return ZoomCalc.GetForSpeed(speed, this.imzConfig) + peekOffset;
  };
  if combat == 1 {
    result = this.imzConfig.combat + peekOffset;
    return result;
  };
  if zone == 4 || zone == 5 {
    result = this.imzConfig.securityArea + peekOffset;
    return result;
  };
  if IsEntityInInteriorArea(this.imzPlayer) {
    result = MinF(this.imzConfig.interior, this.imzConfig.exterior) + this.imzConfig.peek;
  };
  return result;
}

// The ONLY place the native zoom fields are written flat. Flattening is what
// makes the fake-swap window invisible: the Safe<->Default flip briefly runs
// the minimap through the other display mode, which reads a DIFFERENT bucket,
// and equal buckets make that detour have no zoom consequence.
// The vehicle bucket is exempt on foot; see below.
@addMethod(MinimapContainerController)
private func WriteAllBuckets_IMZ(value: Float) -> Void {
  // The engine only selects the vehicle bucket while mounted, so flattening it
  // on foot buys nothing and leaves a remount reading a stale on-foot value:
  // vanilla flips IsPlayerMounted (a rebuild trigger) inside wrappedMethod,
  // before our mount handler can write the vehicle zoom.
  this.visionRadiusVehicle = this.imzIsActuallyMounted ? value : this.imzConfig.minZoom;
  this.visionRadiusCombat = value;
  this.visionRadiusQuestArea = value;
  this.visionRadiusSecurityArea = value;
  this.visionRadiusInterior = value;
  this.visionRadiusExterior = value;
}

// The ONLY place the per-state configured values are written. The vehicle
// bucket never takes the peek offset: peek in a vehicle rides the flatten path
// instead (see OnAction).
@addMethod(MinimapContainerController)
private func WriteConfiguredBuckets_IMZ() -> Void {
  let peek: Float = this.imzPeekActive ? this.imzConfig.peek : 0.0;

  this.visionRadiusVehicle = this.imzConfig.minZoom;
  this.visionRadiusCombat = this.imzConfig.combat + peek;
  this.visionRadiusQuestArea = this.imzConfig.questArea + peek;
  this.visionRadiusSecurityArea = this.imzConfig.securityArea + peek;
  this.visionRadiusInterior = this.imzConfig.interior + peek;
  this.visionRadiusExterior = this.imzConfig.exterior + peek;

  IMZLog(s"Zooms: \(this.imzConfig.minZoom) \(this.imzConfig.combat + peek) \(this.imzConfig.questArea + peek) \(this.imzConfig.securityArea + peek) \(this.imzConfig.interior + peek) \(this.imzConfig.exterior + peek)");
}

// Pure zoom value update without triggering minimap rebuild
@addMethod(MinimapContainerController)
public func UpdateZoomValuesOnly_IMZ() -> Void {
  this.WriteConfiguredBuckets_IMZ();
}

// Overrides

// Set native zoom values for MinimapContainerController, yay ^_^
@addMethod(MinimapContainerController)
public func SetPreconfiguredZoomValues_IMZ() -> Void {
  this.WriteConfiguredBuckets_IMZ();

  // Still required to force minimap rebuild on true zone/state changes
  if IsDefined(this.imzPlayer) {
    this.imzPlayer.ForceMinimapRefreshWithFakeZone();
  };
}

// Apply the configured per-bucket values through a transition that hides the
// Safe<->Default flip's display-mode detour: flatten every selectable bucket to
// the LIVE displayed radius first, then let the restore handler write the per-bucket
// values back just BEFORE the zone flips home, so the engine's own restore
// recompute lands on the right value for whichever bucket IT picks. Writing
// the per-bucket values before the flip instead (SetPreconfiguredZoomValues_IMZ)
// leaves the detour exposed for ~0.1s and shows as a zoom blip.
// Falls back to the plain path when the native live-radius read is unavailable.
@addMethod(MinimapContainerController)
public func ApplyConfiguredZoomNeutralized_IMZ() -> Void {
  let liveZoom: Float = IMZ_GetMinimapRadius(this);
  if liveZoom <= 0.0 || !IsDefined(this.imzPlayer) {
    this.SetPreconfiguredZoomValues_IMZ();
    return;
  };

  this.WriteAllBuckets_IMZ(liveZoom);
  this.imzCurrentZoom = liveZoom;
  this.imzTargetZoom = liveZoom;
  this.imzPlayer.ForceMinimapRefresh_IMZ();
}

// DIRTY HACK #1:
// Flatten all zoom values to prevent dynamic zoom flickering because of constant IsPlayerMounted swaps
@addMethod(MinimapContainerController)
public func HackAllZoomValues_IMZ(value: Float) -> Void {
  this.WriteAllBuckets_IMZ(value);
  if IsDefined(this.imzPlayer) {
    this.imzPlayer.ForceMinimapRefreshWithFakeZone();
  };
}

// DIRTY HACK #2:
// Trigger minimap refresh after the game loaded with faked zone
@wrapMethod(MinimapContainerController)
protected cb func OnPlayerAttach(playerGameObject: ref<GameObject>) -> Bool {
  wrappedMethod(playerGameObject);

  // Everything below assumes a PlayerPuppet: InitBBs_IMZ stashes the back
  // reference on it and the refresh paths dispatch through it
  if !IsDefined(playerGameObject as PlayerPuppet) {
    return true;
  };

  this.InitBBs_IMZ(playerGameObject);
  this.imzPeekActive = false;
  // Fresh attach: invalidate anything still queued and clear the post-unmount
  // flag, so a stale one can never suppress refreshes for the whole session
  this.imzPlayer.BumpMountGeneration_IMZ();
  this.SetPreconfiguredZoomValues_IMZ();

  // Seed from the actual displayed zoom (exact); fall back to the zone-based
  // guess if the native read is unavailable this early in initialization
  let liveZoom: Float = IMZ_GetMinimapRadius(this);
  this.imzCurrentZoom = liveZoom > 0.0 ? liveZoom : this.GetZoomForZone_IMZ(this.imzPlayer.GetRealZone_IMZ());
  this.imzTargetZoom = this.imzCurrentZoom;

  // Loading a save inside a vehicle gives this controller no mount event to
  // react to, so without this the vehicle zoom is never applied and the
  // minimap sits on the on-foot exterior value for the whole drive.
  // Flattening every bucket makes it correct whichever one the engine selects,
  // and the refresh coalesces with the one hack #2 just issued above.
  if this.imzIsActuallyMounted {
    let speed: Float = this.imzBlackboard.GetFloat(GetAllBlackboardDefs().UI_System.CurrentSpeed_IMZ);
    this.imzCurrentZoom = ZoomCalc.GetForSpeed(speed, this.imzConfig);
    this.imzTargetZoom = this.imzCurrentZoom;
    this.HackAllZoomValues_IMZ(this.imzCurrentZoom);
  };

  playerGameObject.RegisterInputListener(this, IMZAction());
  return true;
}

@wrapMethod(MinimapContainerController)
protected cb func OnPlayerDetach(playerGameObject: ref<GameObject>) -> Bool {
  wrappedMethod(playerGameObject);
  // Matches the RegisterInputListener in OnPlayerAttach, which previously had
  // no counterpart
  if IsDefined(playerGameObject) {
    playerGameObject.UnregisterInputListener(this);
  };
  this.ClearBBs_IMZ();
  return true;
}

@addMethod(MinimapContainerController)
protected cb func OnAction(action: ListenerAction, consumer: ListenerActionConsumer) -> Bool {
  let actionName: CName = ListenerAction.GetName(action);
  if Equals(actionName, IMZAction()) {

    // Peek while driving needs hack #3's IsPlayerMounted reset (dynamic zoom
    // or the static-peek opt-in): without it the engine ignores the zone-flip
    // refresh in vehicles — the press would change nothing on screen.
    // Uses the mount-time snapshot, not the live config: a settings change
    // made mid-drive cannot retroactively fire hack #3 for this vehicle
    if this.imzIsActuallyMounted && !this.imzVehiclePeekAllowed {
      // A hold started ON FOOT must still be able to end in here, or the flag
      // latches with no key held and the unmount restore writes a phantom
      // +peek into every bucket. No visual work: the buckets are
      // vehicle-flattened anyway and SetPreconfiguredZoomValues_IMZ at unmount
      // reads the cleared flag.
      if !this.imzConfig.replaceHoldWithToggle && Equals(ListenerAction.GetType(action), gameinputActionType.BUTTON_RELEASED) {
        this.imzPeekActive = false;
      };
      return false;
    };

    let prevPeek: Bool = this.imzPeekActive;

    if Equals(ListenerAction.GetType(action), gameinputActionType.BUTTON_PRESSED) {
      this.imzPeekActive = this.imzConfig.replaceHoldWithToggle ? !this.imzPeekActive : true;
    };

    if Equals(ListenerAction.GetType(action), gameinputActionType.BUTTON_RELEASED) {
      if !this.imzConfig.replaceHoldWithToggle {
        this.imzPeekActive = false;
      };
    };

    if NotEquals(prevPeek, this.imzPeekActive) {
      // Flatten every selectable bucket to one waypoint value for the swap
      // window so the mode detour during the Safe<->Default flip has no zoom
      // consequence.
      // The waypoint comes from the LIVE displayed radius (read from native
      // memory by the Improved Minimap Zoom Native plugin), so the motion is
      // exact everywhere — doorway strips and quest areas included. If the
      // read fails (<= 0), fall back to the config-based guess; either way
      // the restore handler writes per-bucket values back before the zone
      // flips home, so the engine always lands correctly.
      let liveZoom: Float = IMZ_GetMinimapRadius(this);
      if liveZoom > 0.0 {
        if this.imzPeekActive {
          this.imzPeekBaseZoom = liveZoom;
          this.imzPeekPressTime = EngineTime.ToFloat(GameInstance.GetSimTime(this.imzPlayer.GetGame()));
          this.imzTargetZoom = liveZoom + this.imzConfig.peek;
        } else {
          let sincePress: Float = EngineTime.ToFloat(GameInstance.GetSimTime(this.imzPlayer.GetGame())) - this.imzPeekPressTime;
          if sincePress < 0.5 {
            // Rapid tap: the press motion may still be in flight — don't let
            // the release waypoint dip below the starting zoom
            this.imzTargetZoom = MaxF(liveZoom - this.imzConfig.peek, this.imzPeekBaseZoom);
          } else {
            // Settled hold: live - peek is exact for wherever the player is
            // now (they may have walked into a different-zoom area meanwhile,
            // making the press-time floor stale)
            this.imzTargetZoom = liveZoom - this.imzConfig.peek;
          };
        };
      } else {
        this.imzTargetZoom = this.GetPeekFlattenValue_IMZ(this.imzPlayer.GetRealZone_IMZ(), this.imzPlayer.GetRealCombat_IMZ());
      };

      // Driving: apply via the dynamic-zoom pattern — flatten to the waypoint
      // and refresh WITHOUT the per-bucket restore. The on-foot restore would
      // land the engine on a zone/interior config bucket, overriding the
      // speed-based value until the next speed update arrived.
      if this.imzIsActuallyMounted {
        this.imzCurrentZoom = this.imzTargetZoom;
        IMZLog(s"PEEK (vehicle) active=\(this.imzPeekActive) target=\(this.imzTargetZoom)");
        this.HackAllZoomValues_IMZ(this.imzTargetZoom);
        return true;
      };

      this.WriteAllBuckets_IMZ(this.imzTargetZoom);
      this.imzCurrentZoom = this.imzTargetZoom;

      IMZLog(s"PEEK active=\(this.imzPeekActive) zone=\(this.imzPlayer.GetRealZone_IMZ()) combat=\(this.imzPlayer.GetRealCombat_IMZ()) interior=\(IsEntityInInteriorArea(this.imzPlayer)) target=\(this.imzTargetZoom)");

      // Original Safe<->Default zone flip — the only trigger that reliably
      // wakes the native zoom recompute without dragging the combat HUD along
      this.imzPlayer.ForceMinimapRefresh_IMZ();
    };

    return true;
  };

  return false;
}

@addMethod(MinimapContainerController)
protected cb func OnRefreshZoomConfigsEvent(evt: ref<RefreshZoomConfigsEvent>) -> Void {
  let previous: ref<ZoomConfig> = this.imzConfig;
  // Always adopt the new config: the behavior flags (dynamic zoom, toggle mode,
  // static vehicle peek) matter even when no zoom VALUE moved
  this.imzConfig = new ZoomConfig();

  if !IsDefined(this.imzPlayer) {
    return;
  };

  // Switching between hold and toggle while a peek is active would strand the
  // flag: a hold-mode peek has no release left to arrive once the key is no
  // longer held, and a toggle-mode one has no press. Drop it and let the
  // per-bucket write below land without the offset.
  // Deliberately not conditioned on the dynamic-zoom or static-peek settings:
  // availability belongs to imzVehiclePeekAllowed, snapshotted at mount, and
  // reading those live is what caused the phantom-peek bug.
  let peekCleared: Bool = false;
  if this.imzPeekActive && NotEquals(previous.replaceHoldWithToggle, this.imzConfig.replaceHoldWithToggle) {
    IMZLog("Peek cleared: hold/toggle mode changed while active");
    this.imzPeekActive = false;
    peekCleared = true;
  };

  // This event fires on EVERY pause-menu close, not just when a setting
  // changed. A refresh costs a zone flip, and the flip runs the minimap
  // through the other display mode for ~0.1s — so do nothing at all unless a
  // value we actually write has moved.
  // peekCleared forces it through regardless: ZoomValuesChanged_IMZ compares
  // only zoom VALUES, so flipping hold/toggle alone would return here and leave
  // the peek offset on screen with imzPeekActive already false, i.e. released
  // in state but not visually.
  if !peekCleared && !this.ZoomValuesChanged_IMZ(previous, this.imzConfig) {
    return;
  };

  // Driving: with dynamic zoom ON the buckets are rewritten on every speed
  // update, so an ordinary value change lands on its own. Two cases still have
  // to be written here.
  // With dynamic zoom OFF no speed updates flow at all, so a change would
  // otherwise wait until the next unmount.
  // A cleared peek must be released immediately even with dynamic zoom ON,
  // because CurrentSpeed_IMZ only signals on change: parked, no speed update
  // ever arrives, and the offset would stay on screen until the player drove
  // off despite imzPeekActive already being false.
  // The repaint only lands when hack #3 fired for this mount (dynamic zoom or
  // the static-peek opt-in); without it the buckets are at least correct for
  // the next rebuild the engine does on its own.
  if this.imzIsActuallyMounted {
    if !this.imzConfig.isDynamicZoomEnabled || peekCleared {
      let vehiclePeek: Float = this.imzPeekActive && this.imzVehiclePeekAllowed ? this.imzConfig.peek : 0.0;
      let speed: Float = this.imzBlackboard.GetFloat(GetAllBlackboardDefs().UI_System.CurrentSpeed_IMZ);
      // GetForSpeed returns minZoom outright when dynamic zoom is off, so this
      // covers both cases without branching on the setting twice
      this.imzCurrentZoom = ZoomCalc.GetForSpeed(speed, this.imzConfig) + vehiclePeek;
      this.imzTargetZoom = this.imzCurrentZoom;
      this.HackAllZoomValues_IMZ(this.imzCurrentZoom);
    };
    return;
  };

  // Apply the changed settings immediately so the displayed zoom never sits on
  // stale values — without this the first peek afterwards reads a stale radius
  // and visibly re-aims mid-motion once. Neutralized so the flip window costs
  // nothing visually.
  this.ApplyConfiguredZoomNeutralized_IMZ();
}

// True when a setting this controller actually writes into the visionRadius*
// buckets has changed — the behavior flags are deliberately excluded, they
// need no minimap refresh
@addMethod(MinimapContainerController)
private func ZoomValuesChanged_IMZ(a: ref<ZoomConfig>, b: ref<ZoomConfig>) -> Bool {
  if !IsDefined(a) || !IsDefined(b) { return true; };
  if NotEquals(a.minZoom, b.minZoom) { return true; };
  if NotEquals(a.combat, b.combat) { return true; };
  if NotEquals(a.questArea, b.questArea) { return true; };
  if NotEquals(a.securityArea, b.securityArea) { return true; };
  if NotEquals(a.interior, b.interior) { return true; };
  if NotEquals(a.exterior, b.exterior) { return true; };
  if NotEquals(a.peek, b.peek) { return true; };
  return false;
}
