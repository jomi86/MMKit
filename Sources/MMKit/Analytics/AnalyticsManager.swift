import Foundation
import FirebaseAnalytics
import FirebaseCrashlytics

@MainActor
public final class AnalyticsManager {
  public static let shared = AnalyticsManager()

  private init() {}
}

// MARK: - AnalyticsManaging

extension AnalyticsManager: AnalyticsManaging {
  // MARK: - Configuration

  public func configure() {
#if DEBUG
    Analytics.setAnalyticsCollectionEnabled(false)
#else
    Analytics.setAnalyticsCollectionEnabled(true)
#endif

    setAppProperties()
  }

  // MARK: - User Properties

  public func setUserProperty(_ value: String, forKey key: String) {
    Analytics.setUserProperty(value, forName: key)
  }

  public func updateSubscriptionProperties(isSubscribed: Bool, isInTrial: Bool = false, productId: String? = nil) {
    let status = isSubscribed ? (isInTrial ? "trial" : "active") : "none"
    Analytics.setUserProperty(status, forName: UserProperty.subscriptionStatus)

    if let productId {
      Analytics.setUserProperty(productId, forName: UserProperty.subscriptionProductId)
    }
  }

  public func updatePermissionProperties(locationPermission: String, notificationPermission: String) {
    Analytics.setUserProperty(locationPermission, forName: UserProperty.locationPermission)
    Analytics.setUserProperty(notificationPermission, forName: UserProperty.notificationPermission)
  }

  public func updateLocationType(isManual: Bool) {
    Analytics.setUserProperty(isManual ? "manual" : "automatic", forName: UserProperty.locationType)
  }

  public func updateFeaturePreferences(liveActivityEnabled: Bool, notificationsEnabled: Bool) {
    Analytics.setUserProperty(String(liveActivityEnabled), forName: UserProperty.liveActivityEnabled)
    Analytics.setUserProperty(String(notificationsEnabled), forName: UserProperty.notificationsEnabled)
  }

  // MARK: - Screen Tracking

  public func trackScreenView(_ screenName: String, screenClass: String? = nil) {
    let parameters: [String: Any] = [
      AnalyticsParameterScreenName: screenName,
      AnalyticsParameterScreenClass: screenClass ?? screenName
    ]

    Analytics.logEvent(AnalyticsEventScreenView, parameters: parameters)
  }

  // MARK: - Events

  public func trackEvent(_ eventName: String, parameters: [String: Any]? = nil) {
    Analytics.logEvent(eventName, parameters: parameters)
  }

  public func trackEvent(_ event: Event, parameters: [String: Any]? = nil) {
    trackEvent(event.rawValue, parameters: parameters)
  }

  // MARK: - Common Events

  public func trackAppOpen() {
    Analytics.logEvent(AnalyticsEventAppOpen, parameters: nil)
    setAppProperties()
  }

  public func trackError(_ error: Error, context: String) {
    let parameters: [String: Any] = [
      "error_description": error.localizedDescription,
      "context": context
    ]
    trackEvent("error_occurred", parameters: parameters)

    Crashlytics.crashlytics().record(error: error)
    Crashlytics.crashlytics().log("Error in context: \(context) - \(error.localizedDescription)")
  }

  // MARK: - Crashlytics

  public func setUserID(_ userID: String) {
    Crashlytics.crashlytics().setUserID(userID)
  }

  public func setCustomValue(_ value: String, forKey key: String) {
    Crashlytics.crashlytics().setCustomValue(value, forKey: key)
  }

  public func logCrashlytics(_ message: String) {
    Crashlytics.crashlytics().log(message)
  }

  public func recordNonFatalError(_ error: Error, additionalInfo: [String: Any]? = nil) {
    if let additionalInfo {
      for (key, value) in additionalInfo {
        Crashlytics.crashlytics().setCustomValue(value, forKey: key)
      }
    }

    Crashlytics.crashlytics().record(error: error)
  }

  // MARK: - Location Tracking

  public func trackLocationUpdate(permissionGranted: Bool, locationType: String) {
    trackEvent("location_updated", parameters: [
      "permission_granted": permissionGranted,
      "location_type": locationType
    ])
  }
}

private extension AnalyticsManager {
  enum DefaultsKey {
    static let firstLaunchDate = "firstLaunchDate"
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
  }

  func setAppProperties() {
    if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
      Analytics.setUserProperty(appVersion, forName: UserProperty.appVersion)
    }

    if let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
      Analytics.setUserProperty(buildNumber, forName: UserProperty.buildNumber)
    }

    if let firstLaunch = UserDefaults.standard.object(forKey: DefaultsKey.firstLaunchDate) as? Date {
      let daysSinceInstall = Calendar.current.dateComponents([.day], from: firstLaunch, to: Date()).day ?? 0
      Analytics.setUserProperty(String(daysSinceInstall), forName: UserProperty.daysSinceInstall)
    } else {
      UserDefaults.standard.set(Date(), forKey: DefaultsKey.firstLaunchDate)
      Analytics.setUserProperty("0", forName: UserProperty.daysSinceInstall)
    }

    let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: DefaultsKey.hasCompletedOnboarding)
    Analytics.setUserProperty(String(hasCompletedOnboarding), forName: UserProperty.onboardingCompleted)
  }
}

// MARK: - Generic Event Names

extension AnalyticsManager {
  public enum Event: String {
    case appOpened = "app_opened"
    case appBackgrounded = "app_backgrounded"
    case screenView = "screen_view"
    case locationUpdated = "location_updated"
    case activityAdded = "activity_added"
    case activityDeleted = "activity_deleted"
    case activityCompleted = "activity_completed"
    case onboardingCompleted = "onboarding_completed"
    case settingsUpdated = "settings_updated"
    case errorOccurred = "error_occurred"
    case paywallOpened = "paywall_opened"
    case paywallDismissed = "paywall_dismissed"
    case paywallPurchaseCompleted = "paywall_purchase_completed"
    case paywallPurchaseFailed = "paywall_purchase_failed"
    case subscriptionStarted = "subscription_started"
    case subscriptionRestored = "subscription_restored"
    case customerCenterOpened = "customer_center_opened"
    case customerCenterDismissed = "customer_center_dismissed"
    case customerCenterRefundRequested = "customer_center_refund_requested"
    case customerCenterRestoreCompleted = "customer_center_restore_completed"
    case landingPageViewed = "landing_page_viewed"
    case landingPageGetStartedTapped = "landing_page_get_started_tapped"
    case locationPermissionRequested = "location_permission_requested"
    case locationPermissionGranted = "location_permission_granted"
    case locationPermissionDenied = "location_permission_denied"
    case manualLocationSelected = "manual_location_selected"
    case widgetViewed = "widget_viewed"
    case profileViewed = "profile_viewed"
    case profileUpdated = "profile_updated"

    public enum Parameter {
      public static let feature = "feature"
      public static let error = "error"
      public static let context = "context"
      public static let subscriptionId = "subscription_id"
      public static let subscriptionPrice = "subscription_price"
      public static let isDismissible = "is_dismissible"
      public static let launchCount = "launch_count"
      public static let permissionStatus = "permission_status"
      public static let locationType = "location_type"
      public static let productId = "product_id"
      public static let refundStatus = "refund_status"
      public static let success = "success"
      public static let errorDescription = "error_description"
    }
  }

  enum UserProperty {
    static let subscriptionStatus = "subscription_status"
    static let subscriptionProductId = "subscription_product_id"
    static let locationPermission = "location_permission"
    static let notificationPermission = "notification_permission"
    static let locationType = "location_type"
    static let liveActivityEnabled = "live_activity_enabled"
    static let notificationsEnabled = "notifications_enabled"
    static let appVersion = "app_version"
    static let buildNumber = "build_number"
    static let daysSinceInstall = "days_since_install"
    static let onboardingCompleted = "onboarding_completed"
  }
}
