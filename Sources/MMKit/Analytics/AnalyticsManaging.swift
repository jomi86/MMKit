import Foundation

@MainActor
public protocol AnalyticsManaging: AnyObject {
  func configure()
  func updateSubscriptionProperties(isSubscribed: Bool, isInTrial: Bool, productId: String?)
  func updatePermissionProperties(locationPermission: String, notificationPermission: String)
  func updateLocationType(isManual: Bool)
  func updateFeaturePreferences(liveActivityEnabled: Bool, notificationsEnabled: Bool)
  func trackScreenView(_ screenName: String, screenClass: String?)
  func trackEvent(_ eventName: String, parameters: [String: Any]?)
  func trackAppOpen()
  func trackError(_ error: Error, context: String)
  func setUserProperty(_ value: String, forKey key: String)
  func setUserID(_ userID: String)
  func setCustomValue(_ value: String, forKey key: String)
  func logCrashlytics(_ message: String)
  func recordNonFatalError(_ error: Error, additionalInfo: [String: Any]?)
  func trackLocationUpdate(permissionGranted: Bool, locationType: String)
}
