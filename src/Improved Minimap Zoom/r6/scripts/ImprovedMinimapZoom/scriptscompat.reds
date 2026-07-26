import ImprovedMinimapMain.ZoomConfig

@addField(JournalNotificationQueue)
public let m_UIBlackboard_Compat: wref<IBlackboard>;

public class RefreshZoomConfigsEvent extends Event {}

@wrapMethod(PauseMenuBackgroundGameController)
protected cb func OnUninitialize() -> Bool {
  // The controlled object can already be gone when this fires as part of a
  // session teardown (quit to main menu), and there is nothing to refresh then
  let player: ref<GameObject> = this.GetPlayerControlledObject();
  if IsDefined(player) {
    GameInstance.GetUISystem(player.GetGame()).QueueEvent(new RefreshZoomConfigsEvent());
  };
  wrappedMethod();
}
