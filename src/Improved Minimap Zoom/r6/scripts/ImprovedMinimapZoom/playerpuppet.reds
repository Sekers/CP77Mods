import ImprovedMinimapMain.ZoomConfig
import ImprovedMinimapUtil.IMZLog

public class RestorePlayerZoneEvent extends Event {
  public let realZone: Int32;
  public let fakedZone: Int32;
  public let restoreBuckets: Bool;
}

// Post-unmount events carry the mount generation they were queued under, so a
// later mount can discard the ones left over from an earlier unmount.
// Deliberately NOT applied to RestorePlayerZoneEvent: that event owns the
// cleanup that un-fakes the zone and clears imzRefreshPending, and dropping one
// would leave the blackboard faked and every later refresh coalesced away.
public class ClearIMZUnmountFlagEvent extends Event {
  public let generation: Int32;
}

@addField(PlayerPuppet)
public let imzJustUnmounted: Bool;

@addField(PlayerPuppet)
public let imzRefreshPending: Bool;

// Bumped on every mount transition and at controller attach. Delayed
// post-unmount events stamped with an older value are stale and ignored.
@addField(PlayerPuppet)
public let imzMountGeneration: Int32;

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

// Set when the game genuinely writes PlayerStateMachine.Zones while one of our
// fake swaps is in flight. Comparing the blackboard against the faked value
// cannot distinguish "nothing happened" from "a real change landed on exactly
// the value we faked", so the write itself has to be observed.
@addField(PlayerPuppet)
public let imzSawRealZoneWrite: Bool;

// The mod's own fake goes through IBlackboard.SetInt directly, so this wrap
// never sees it: only genuine zone changes reach here. The four writers are
// PlayerPuppet.OnEnter{Public,Safe,Restricted,Dangerous}Zone. Nothing writes
// Default(1) and OnEnterUndefinedZone is empty, so four of the five zone values
// are observable, which is enough for the doorway cases this protects.
@wrapMethod(PlayerPuppet)
public func SetBlackboardIntVariable(id: BlackboardID_Int, value: Int32) -> Void {
  if this.imzRefreshPending && Equals(id, GetAllBlackboardDefs().PlayerStateMachine.Zones) {
    this.imzSawRealZoneWrite = true;
    // Keep the stash current too: GetRealZone_IMZ returns it for the rest of
    // the window, so leaving it stale would hide the change from every caller
    this.imzLastRealZone = value;
  };
  wrappedMethod(id, value);
}

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
  this.imzSawRealZoneWrite = false;

  let psmBB: ref<IBlackboard> = this.GetPlayerStateMachineBlackboard();
  let realZone: Int32 = psmBB.GetInt(GetAllBlackboardDefs().PlayerStateMachine.Zones);
  let fakedZone: Int32 = realZone == 3 ? 1 : 3;

  this.imzLastRealZone = realZone;

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
  // Never while mounted: these are ON-FOOT values, and the vehicle path owns
  // the buckets. Reachable by pressing peek just before entering a vehicle —
  // the restore would then replace the speed-based flatten with the on-foot
  // config values until the next speed update arrived.
  if (evt.restoreBuckets || this.imzPendingRestoreBuckets)
      && IsDefined(this.imzMinimapController)
      && !this.imzMinimapController.imzIsActuallyMounted {
    this.imzMinimapController.UpdateZoomValuesOnly_IMZ();
  };
  this.imzPendingRestoreBuckets = false;

  // Never write the stashed zone back over a REAL zone change that won the race
  // during the fake window (likely at doorways: Public->Safe shop entries etc.).
  // The observed-write flag is the authority: the value comparison below cannot
  // tell "untouched" from "genuinely changed to exactly the value we faked",
  // and that case used to be clobbered silently.
  let currentZone: Int32 = this.GetPlayerStateMachineBlackboard().GetInt(GetAllBlackboardDefs().PlayerStateMachine.Zones);
  if this.imzSawRealZoneWrite {
    IMZLog(s"Skip zone restore: real zone write observed during fake window (now \(currentZone))");
  } else if currentZone == evt.fakedZone {
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

// Always live: the mod fakes Zones only, never Combat, so there is nothing to
// stash and a snapshot could only ever be stale.
@addMethod(PlayerPuppet)
public func GetRealCombat_IMZ() -> Int32 {
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
  // Stale: a mount happened after this was queued, and that mount already
  // cleared the flag synchronously
  if evt.generation != this.imzMountGeneration {
    IMZLog("Ignored stale unmount-flag clear from an earlier mount generation");
    return true;
  };
  this.imzJustUnmounted = false;
  return true;
}

// Called from every mount transition and from controller attach. Clearing
// imzJustUnmounted here is what makes the generation check safe: once a newer
// generation exists the in-flight ClearIMZUnmountFlagEvent will be discarded,
// so the flag has to be owned by this synchronous path or it would latch true
// and the soft guard would kill every refresh for the rest of the session.
@addMethod(PlayerPuppet)
public func BumpMountGeneration_IMZ() -> Void {
  this.imzMountGeneration += 1;
  this.imzJustUnmounted = false;
}
