@addField(JournalNotificationQueue)
public let m_UIBlackboard_IMZ: wref<IBlackboard>;

@replaceMethod(JournalNotificationQueue)
protected cb func OnPlayerAttach(playerPuppet: ref<GameObject>) -> Bool {
  let shardCallback: ref<ShardCollectedInventoryCallback>;
  this.m_journalMgr = GameInstance.GetJournalManager(playerPuppet.GetGame());
  this.m_journalMgr.RegisterScriptCallback(this, n"OnJournalUpdate", gameJournalListenerType.State);
  this.m_journalMgr.RegisterScriptCallback(this, n"OnJournalEntryVisited", gameJournalListenerType.Visited);
  // this.m_activeVehicleBlackboard = this.GetBlackboardSystem().Get(GetAllBlackboardDefs().UI_ActiveVehicleData);
  // this.m_mountBBConnectionId = this.m_activeVehicleBlackboard.RegisterListenerBool(GetAllBlackboardDefs().UI_ActiveVehicleData.IsPlayerMounted, this, n"OnPlayerMounted");
  // this.m_isPlayerMounted = this.m_activeVehicleBlackboard.GetBool(GetAllBlackboardDefs().UI_ActiveVehicleData.IsPlayerMounted);
  this.m_UIBlackboard_IMZ = this.GetBlackboardSystem().Get(GetAllBlackboardDefs().UI_System);
  this.m_mountBBConnectionId = this.m_UIBlackboard_IMZ.RegisterListenerBool(GetAllBlackboardDefs().UI_System.IsMounted_IMZ, this, n"OnPlayerMounted");
  this.m_isPlayerMounted = this.m_UIBlackboard_IMZ.GetBool(GetAllBlackboardDefs().UI_System.IsMounted_IMZ);
  // -
  this.m_playerPuppet = playerPuppet;
  this.m_uiSystem = GameInstance.GetUISystem(playerPuppet.GetGame());
  shardCallback = new ShardCollectedInventoryCallback();
  shardCallback.m_notificationQueue = this;
  shardCallback.m_journalManager = this.m_journalMgr;
  this.m_transactionSystem = GameInstance.GetTransactionSystem(playerPuppet.GetGame());
  this.m_shardTransactionListener = this.m_transactionSystem.RegisterInventoryListener(playerPuppet, shardCallback);
}

// Vanilla's OnPlayerDetach releases the journal callback and the transaction
// listener but never the mount listener, so the registration above outlived
// every detach. Matching non-delayed unregister, on the UI_System blackboard
// this mod redirected it to.
@wrapMethod(JournalNotificationQueue)
protected cb func OnPlayerDetach(playerPuppet: ref<GameObject>) -> Bool {
  if IsDefined(this.m_UIBlackboard_IMZ) && IsDefined(this.m_mountBBConnectionId) {
    this.m_UIBlackboard_IMZ.UnregisterListenerBool(GetAllBlackboardDefs().UI_System.IsMounted_IMZ, this.m_mountBBConnectionId);
  };
  wrappedMethod(playerPuppet);
}
