import ImprovedMinimapMain.ZoomConfig
import ImprovedMinimapUtil.IMZLog

public class RestorePlayerZoneEvent extends Event {
  public let realZone: Int32;
  public let fakedZone: Int32;
  public let restoreBuckets: Bool;
}

public class ClearIMZUnmountFlagEvent extends Event {}

@addField(PlayerPuppet)
public let imzJustUnmounted: Bool;

@addField(PlayerPuppet)
public let imzRefreshPending: Bool;

// Set when a restoreBucketsAfter request arrives while a refresh is already
// pending: the request is coalesced away, but the flatten it was meant to
// undo (OnAction writes the buckets BEFORE requesting the refresh) must
// still be restored when the pending window closes
@addField(PlayerPuppet)
public let imzPendingRestoreBuckets: Bool;

@addField(PlayerPuppet)
public let imzMinimapController: wref<MinimapContainerController>;

// Real (non-faked) state captured when a fake swap starts, so code that runs
// while the swap is in flight never reads a faked blackboard value
@addField(PlayerPuppet)
public let imzLastRealZone: Int32;

@addField(PlayerPuppet)
public let imzLastRealCombat: Int32;

// restoreBucketsAfter: peek path only — write per-zone values back right before
// the real state is restored, so the engine's restore recompute lands on the
// correct value for whichever bucket IT selects (quest areas, security volumes
// and interiors are engine-driven and can't be reliably predicted from script)
@addMethod(PlayerPuppet)
public func ForceMinimapRefreshWithFakeZone(opt restoreBucketsAfter: Bool) -> Void {
  // SOFT GUARD:
  // Skip fake-zone refresh only during the post-unmount window
  if this.imzJustUnmounted {
    IMZLog("Skipped fake zone refresh (post-unmount window)");
    return;
  };

  // DEBOUNCE:
  // If a refresh is already queued, coalesce requests — but carry the
  // bucket-restore obligation over to the pending window, otherwise a peek
  // arriving here leaves the buckets flattened (its flatten already happened
  // in OnAction) with nothing scheduled to restore them
  if this.imzRefreshPending {
    if restoreBucketsAfter {
      this.imzPendingRestoreBuckets = true;
    };
    IMZLog("Fake zone refresh already pending — coalescing");
    return;
  };

  this.imzRefreshPending = true;

  let psmBB: ref<IBlackboard> = this.GetPlayerStateMachineBlackboard();
  let realZone: Int32 = psmBB.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Zones);
  let fakedZone: Int32 = realZone == 3 ? 1 : 3;

  this.imzLastRealZone = realZone;
  this.imzLastRealCombat = psmBB.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Combat);

  IMZLog(s"Force minimap refresh with fake zone \(fakedZone)");

  psmBB.SetInt(GetAllBlackboardDefs().PlayerStateMachine.Zones, fakedZone, false);

  let event: ref<RestorePlayerZoneEvent> = new RestorePlayerZoneEvent();
  event.realZone = realZone;
  event.fakedZone = fakedZone;
  event.restoreBuckets = restoreBucketsAfter;

  // Peek swaps (restoreBucketsAfter) use a short window that must still span
  // at least one rendered frame so the engine sees the faked zone; 0.08s
  // covers down to ~12fps. Because the peek waypoint comes from the live
  // displayed radius, the restore landing is collinear with the motion and
  // the window length has no visible effect. Driving/unmount refreshes keep
  // the original proven timing.
  let restoreDelay: Float = restoreBucketsAfter ? 0.08 : 0.1;

  GameInstance.GetDelaySystem(this.GetGame())
    .DelayEvent(this, event, restoreDelay);
}

@addMethod(PlayerPuppet)
protected cb func OnRestorePlayerZoneEvent(evt: ref<RestorePlayerZoneEvent>) -> Bool {
  // Peek path: put per-zone values back BEFORE the state flips, so the engine's
  // restore recompute reads the correct value for the bucket it actually uses.
  // imzPendingRestoreBuckets covers restore requests that were coalesced away
  // while this refresh was pending.
  if (evt.restoreBuckets || this.imzPendingRestoreBuckets) && IsDefined(this.imzMinimapController) {
    this.imzMinimapController.UpdateZoomValuesOnly_IMZ();
  };
  this.imzPendingRestoreBuckets = false;

  // Only write the stashed zone back if the blackboard still holds our faked
  // value. If a REAL zone change won the race during the fake window (likely
  // at doorways: Public->Safe shop entries etc.), writing the stale zone
  // would clobber it for every system reading PSM Zones.
  let currentZone: Int32 = this.GetPlayerStateMachineBlackboard().GetInt(GetAllBlackboardDefs().PlayerStateMachine.Zones);
  if currentZone == evt.fakedZone {
    this.GetPlayerStateMachineBlackboard()
      .SetInt(GetAllBlackboardDefs().PlayerStateMachine.Zones, evt.realZone, false);
    IMZLog(s"Restore with real zone \(evt.realZone) bucketsRestored=\(evt.restoreBuckets)");
  } else {
    IMZLog(s"Skip zone restore: real zone changed to \(currentZone) during fake window");
  };

  this.imzRefreshPending = false;
  return true;
}

// While a fake swap is in flight the blackboard holds the faked value,
// so return the stashed real one instead
@addMethod(PlayerPuppet)
public func GetRealZone_IMZ() -> Int32 {
  if this.imzRefreshPending {
    return this.imzLastRealZone;
  };
  return this.GetPlayerStateMachineBlackboard().GetInt(GetAllBlackboardDefs().PlayerStateMachine.Zones);
}

@addMethod(PlayerPuppet)
public func GetRealCombat_IMZ() -> Int32 {
  if this.imzRefreshPending {
    return this.imzLastRealCombat;
  };
  return this.GetPlayerStateMachineBlackboard().GetInt(GetAllBlackboardDefs().PlayerStateMachine.Combat);
}

// Peek refresh trigger. Tested findings (CP77 1.63):
// - Combat 0<->2 flips and zone Default(1)<->Public(2) flips do NOT wake the
//   native zoom recompute — dead ends, do not retry.
// - Faking InCombat=1 refreshes but drags the whole combat HUD along (outline).
// - The original Safe<->Default zone flip is the only reliable clean trigger;
//   its indoor display-mode detour is neutralized by flattening the buckets
//   before the flip (see OnAction) and restoring them before the flip-back.
@addMethod(PlayerPuppet)
public func ForceMinimapRefresh_IMZ() -> Void {
  this.ForceMinimapRefreshWithFakeZone(true);
}

@addMethod(PlayerPuppet)
protected cb func OnClearIMZUnmountFlagEvent(evt: ref<ClearIMZUnmountFlagEvent>) -> Bool {
  this.imzJustUnmounted = false;
  return true;
}
