import ImprovedMinimapMain.ZoomConfig
import ImprovedMinimapUtil.*

// IF YOU READ THIS - THERE ARE A FEW DIRTY HACKS RIGHT HERE :(
// Minimap widget reloading with new zoom values can be triggered only by a few events like combat mode,
// active zone or mount state change so I constantly swap player zone flag while driving =\

// Patch 1.3 added minimap internal container offset for vehicle minimap mode so
// I disabled it with IsPlayerMounted bb value reset inside VehicleComponent OnUnmountingEvent


// -- Events

public class ForceIMZExteriorRefreshEvent extends Event {}

@addMethod(PlayerPuppet)
protected cb func OnForceIMZExteriorRefreshEvent(evt: ref<ForceIMZExteriorRefreshEvent>) -> Bool {
  // This calls ForceMinimapRefreshWithFakeZone(), which will only work once imzJustUnmounted is cleared.
  this.ForceMinimapRefreshWithFakeZone();
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

// Track actual mounted state (used to block manual peek while driving)
@addField(MinimapContainerController)
public let imzIsActuallyMounted: Bool;


// Methods

// Event-driven convergence — vanilla-safe replacement for snap-based zoom (non-vehicle)
@addMethod(MinimapContainerController)
public func UpdateZoom_IMZ() -> Void {
  this.imzCurrentZoom = this.imzTargetZoom;
  this.ApplyZoom_IMZ(this.imzCurrentZoom);
}

@addMethod(MinimapContainerController)
protected cb func OnSpeedValueChanged_IMZ(speed: Float) -> Bool {
  if this.imzConfig.isDynamicZoomEnabled && !this.imzPeekActive {
    let newZoom: Float = ZoomCalc.GetForSpeed(speed, this.imzConfig);
    IMZLog("New zoom available: " + ToString(newZoom));

    // Vehicle dynamic zoom must snap + force refresh (no per-frame tick in vanilla redscript)
    if this.imzIsActuallyMounted {
      if NotEquals(this.imzCurrentZoom, newZoom) && IsDefined(this.imzPlayer) {
        this.imzCurrentZoom = newZoom;
        this.imzTargetZoom = newZoom;
        this.HackAllZoomValues_IMZ(newZoom);
      };
      return true;
    };

    // On-foot: update target and apply without rebuild
    if NotEquals(this.imzTargetZoom, newZoom) && IsDefined(this.imzPlayer) {
      this.imzTargetZoom = newZoom;
      this.UpdateZoom_IMZ();
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

  // Vehicle enter detected — apply initial vehicle zoom immediately (even at 0 speed)
  if value && IsDefined(this.imzPlayer) {
    let speed: Float = this.imzBlackboard.GetFloat(GetAllBlackboardDefs().UI_System.CurrentSpeed_IMZ);
    let newZoom: Float = ZoomCalc.GetForSpeed(speed, this.imzConfig);

    this.imzCurrentZoom = newZoom;
    this.imzTargetZoom = newZoom;
    this.HackAllZoomValues_IMZ(newZoom);
    return true;
  };

  // Vehicle exit detected — mark post-unmount window
  if !value && IsDefined(this.imzPlayer) {
    this.imzPlayer.imzJustUnmounted = true;

    GameInstance.GetDelaySystem(this.imzPlayer.GetGame())
      .DelayEvent(this.imzPlayer, new ClearIMZUnmountFlagEvent(), 0.3);

    // Update configured zoom values (this will NOT refresh during the unmount window due to the guard)
    this.SetPreconfiguredZoomValues_IMZ();

    // Restore exterior zoom values immediately (visual fields)
    this.imzCurrentZoom = this.visionRadiusExterior;
    this.imzTargetZoom = this.imzCurrentZoom;
    this.UpdateZoom_IMZ();

    // Critical: refresh AFTER the unmount window clears, otherwise ForceMinimapRefreshWithFakeZone() is skipped
    GameInstance.GetDelaySystem(this.imzPlayer.GetGame())
      .DelayEvent(this.imzPlayer, new ForceIMZExteriorRefreshEvent(), 0.35);
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

  // Store reference to this controller on the player so events can access it
  this.imzPlayer.imzMinimapController = this;
}

@addMethod(MinimapContainerController)
public func ClearBBs_IMZ() -> Void {
  this.imzBlackboard.UnregisterListenerFloat(GetAllBlackboardDefs().UI_System.CurrentSpeed_IMZ, this.imzSpeedTrackCallback);
  this.imzIsMountedBlackboard.UnregisterListenerBool(GetAllBlackboardDefs().UI_ActiveVehicleData.IsPlayerMounted, this.imzIsMountedCallback);
  this.imzBlackboard.UnregisterListenerBool(GetAllBlackboardDefs().UI_System.IsMounted_IMZ, this.imzIsActuallyMountedCallback);
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

// Flatten value (peek offset included) for the swap window, read from config —
// never from the visionRadius fields, which may already be flattened.
// The interior bucket is selected by the engine's interior flag, NOT the
// security zone: many interiors are Public/Default zones. Near doorways the
// flag extends outside while the minimap still displays the exterior zoom, and
// that mismatch is undetectable from script (no readable minimap state in
// 1.63) — so for flag-true spots we flatten to min(interior, exterior) + peek
// for BOTH press and release: exact for real interiors, and monotonic (no
// overshoot dip) for the wrongly flagged doorway strips. The restore recompute
// always lands on the engine's own correct value either way.
@addMethod(MinimapContainerController)
public func GetPeekFlattenValue_IMZ(zone: Int32, combat: Int32) -> Float {
  let peekOffset: Float = this.imzPeekActive ? this.imzConfig.peek : 0.0;
  let result: Float = this.imzConfig.exterior + peekOffset;
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

// Flatten every bucket to one value for the fake-swap window: the Safe<->Default
// flip briefly runs the minimap through the other display mode, which reads a
// DIFFERENT bucket — equal buckets make that detour invisible
@addMethod(MinimapContainerController)
private func SetAllZoomsToCurrentValue_IMZ(zoomValue: Float) -> Void {
  this.visionRadiusVehicle = zoomValue;
  this.visionRadiusCombat = zoomValue;
  this.visionRadiusQuestArea = zoomValue;
  this.visionRadiusSecurityArea = zoomValue;
  this.visionRadiusInterior = zoomValue;
  this.visionRadiusExterior = zoomValue;
}

// Pure zoom value update without triggering minimap rebuild
@addMethod(MinimapContainerController)
public func UpdateZoomValuesOnly_IMZ() -> Void {
  let peek: Float = this.imzPeekActive ? this.imzConfig.peek : 0.0;

  this.visionRadiusVehicle = this.imzConfig.minZoom;
  this.visionRadiusCombat = this.imzConfig.combat + peek;
  this.visionRadiusQuestArea = this.imzConfig.questArea + peek;
  this.visionRadiusSecurityArea = this.imzConfig.securityArea + peek;
  this.visionRadiusInterior = this.imzConfig.interior + peek;
  this.visionRadiusExterior = this.imzConfig.exterior + peek;
}

// Overrides

// Set native zoom values for MinimapContainerController, yay ^_^
@addMethod(MinimapContainerController)
public func SetPreconfiguredZoomValues_IMZ() -> Void {
  let peek: Float = this.imzPeekActive ? this.imzConfig.peek : 0.0;

  this.visionRadiusVehicle = this.imzConfig.minZoom;
  this.visionRadiusCombat = this.imzConfig.combat + peek;
  this.visionRadiusQuestArea = this.imzConfig.questArea + peek;
  this.visionRadiusSecurityArea = this.imzConfig.securityArea + peek;
  this.visionRadiusInterior = this.imzConfig.interior + peek;
  this.visionRadiusExterior = this.imzConfig.exterior + peek;

  IMZLog(s"Zooms: \(this.imzConfig.minZoom) \(this.imzConfig.combat + peek) \(this.imzConfig.questArea + peek) \(this.imzConfig.securityArea) \(this.imzConfig.interior) \(this.imzConfig.exterior)");

  // Still required to force minimap rebuild on true zone/state changes
  this.imzPlayer.ForceMinimapRefreshWithFakeZone();
}

// Pure visual zoom application — no rebuild
@addMethod(MinimapContainerController)
public func ApplyZoom_IMZ(value: Float) -> Void {
  this.visionRadiusVehicle = value;
  this.visionRadiusCombat = value;
  this.visionRadiusQuestArea = value;
  this.visionRadiusSecurityArea = value;
  this.visionRadiusInterior = value;
  this.visionRadiusExterior = value;
}

// DIRTY HACK #1:
// Flatten all zoom values to prevent dynamic zoom flickering because of constant IsPlayerMounted swaps
@addMethod(MinimapContainerController)
public func HackAllZoomValues_IMZ(value: Float) -> Void {
  this.visionRadiusVehicle = value;
  this.visionRadiusCombat = value;
  this.visionRadiusQuestArea = value;
  this.visionRadiusSecurityArea = value;
  this.visionRadiusInterior = value;
  this.visionRadiusExterior = value;
  this.imzPlayer.ForceMinimapRefreshWithFakeZone();
}

// DIRTY HACK #2:
// Trigger minimap refresh after the game loaded with faked zone
@wrapMethod(MinimapContainerController)
protected cb func OnPlayerAttach(playerGameObject: ref<GameObject>) -> Bool {
  wrappedMethod(playerGameObject);
  this.InitBBs_IMZ(playerGameObject);
  this.imzPeekActive = false;
  this.SetPreconfiguredZoomValues_IMZ();

  // Seed from the actual zone (the player may load a save indoors)
  this.imzCurrentZoom = this.GetZoomForZone_IMZ(this.imzPlayer.GetRealZone_IMZ());
  this.imzTargetZoom = this.imzCurrentZoom;

  playerGameObject.RegisterInputListener(this, IMZAction());
  return true;
}

@wrapMethod(MinimapContainerController)
protected cb func OnPlayerDetach(playerGameObject: ref<GameObject>) -> Bool {
  wrappedMethod(playerGameObject);
  this.ClearBBs_IMZ();
  return true;
}

@addMethod(MinimapContainerController)
protected cb func OnAction(action: ListenerAction, consumer: ListenerActionConsumer) -> Bool {
  let actionName: CName = ListenerAction.GetName(action);
  if Equals(actionName, IMZAction()) {

    // Manual peek should not work while driving
    if this.imzIsActuallyMounted {
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
      // Flatten ALL buckets to one waypoint value for the swap window so the
      // mode detour during the Safe<->Default flip has no zoom consequence.
      // A wrong waypoint (quest areas, doorway strips) only bends the first
      // 0.05s of motion: the restore handler writes per-bucket values back
      // before the zone flips home, so the engine always lands correctly.
      this.imzTargetZoom = this.GetPeekFlattenValue_IMZ(this.imzPlayer.GetRealZone_IMZ(), this.imzPlayer.GetRealCombat_IMZ());
      this.SetAllZoomsToCurrentValue_IMZ(this.imzTargetZoom);
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
  this.imzConfig = new ZoomConfig();
}
