import Foundation

/// Provides app-specific RevenueCat configuration for use with `RevenueCatManager`.
public protocol MMKitRevenueCatConfiguration: Sendable {
  var apiKey: String { get }
  var monthlyProductID: String { get }
  var yearlyProductID: String { get }
  /// Entitlement ID that grants full access. Defaults to `"pro"`.
  var proEntitlementID: String { get }
}

public extension MMKitRevenueCatConfiguration {
  var proEntitlementID: String { "pro" }
}

/// Allows `RevenueCatManager` to trigger haptic feedback without depending on app-level implementations.
@MainActor
public protocol MMKitHapticFeedbackProviding: AnyObject {
  func importantButtonTap()
  func actionSuccess()
  func actionError()
}
