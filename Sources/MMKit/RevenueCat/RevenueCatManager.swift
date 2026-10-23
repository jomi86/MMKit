import Foundation
import RevenueCat
import RevenueCatUI
import SwiftUI
import StoreKit

@MainActor
public final class RevenueCatManager: NSObject, ObservableObject {

  // MARK: - Singleton

  private static var _shared: RevenueCatManager?

  public static var shared: RevenueCatManager {
    guard let instance = _shared else {
      fatalError("RevenueCatManager.configure() must be called before accessing .shared")
    }
    return instance
  }

  // MARK: - Published State

  @Published public var offerings: Offerings?
  @Published public var customerInfo: CustomerInfo?
  @Published public var isSubscribed: Bool = false
  @Published public var isPurchasing: Bool = false
  @Published public var purchaseError: String?

  // MARK: - Private

  private let configuration: any MMKitRevenueCatConfiguration
  private weak var hapticFeedback: (any MMKitHapticFeedbackProviding)?
  private let logger = LoggerFactory().makeLogger(category: "RevenueCatManager")

  private init(
    configuration: any MMKitRevenueCatConfiguration,
    hapticFeedback: (any MMKitHapticFeedbackProviding)?
  ) {
    self.configuration = configuration
    self.hapticFeedback = hapticFeedback
    super.init()
  }

  // MARK: - Configuration

  /// Call once on app launch (before accessing `.shared`).
  /// Configures the RevenueCat SDK and loads initial offerings/subscription state.
  public static func configure(
    configuration: some MMKitRevenueCatConfiguration,
    appUserID: String? = nil,
    hapticFeedback: (any MMKitHapticFeedbackProviding)? = nil
  ) {
    Purchases.logLevel = .info
    Purchases.configure(withAPIKey: configuration.apiKey, appUserID: appUserID)
    let manager = RevenueCatManager(configuration: configuration, hapticFeedback: hapticFeedback)
    _shared = manager
    manager.setupRevenueCat()
  }

  private func setupRevenueCat() {
    Purchases.shared.delegate = self
    Task {
      await loadOfferings()
      await checkSubscriptionStatus()
    }
  }

  // MARK: - Offerings

  public func loadOfferings() async {
    do {
      let offerings = try await Purchases.shared.offerings()
      self.offerings = offerings
    } catch {
      logger.error("Failed to load RevenueCat offerings: \(error)")
    }
  }

  // MARK: - Subscription Status

  public func checkSubscriptionStatus() async {
    do {
      let customerInfo = try await Purchases.shared.customerInfo()
      self.customerInfo = customerInfo
      self.isSubscribed = !customerInfo.entitlements.active.isEmpty

      if let entitlement = customerInfo.entitlements.active.first?.value {
        let isInTrial = entitlement.periodType == .trial
        let productId = entitlement.productIdentifier
        AnalyticsManager.shared.updateSubscriptionProperties(
          isSubscribed: self.isSubscribed,
          isInTrial: isInTrial,
          productId: productId
        )
      } else {
        AnalyticsManager.shared.updateSubscriptionProperties(isSubscribed: false)
      }
    } catch {
      logger.error("Failed to check RevenueCat subscription status: \(error)")
    }
  }

  // MARK: - Purchase

  public func purchase(package: Package) async -> Bool {
    isPurchasing = true
    purchaseError = nil
    defer { isPurchasing = false }

    AnalyticsManager.shared.logCrashlytics("Purchase attempt: \(package.identifier)")
    AnalyticsManager.shared.setCustomValue(package.identifier, forKey: "last_purchase_attempt")

    hapticFeedback?.importantButtonTap()

    do {
      let (_, customerInfo, _) = try await Purchases.shared.purchase(package: package)
      self.customerInfo = customerInfo
      self.isSubscribed = !customerInfo.entitlements.active.isEmpty

      hapticFeedback?.actionSuccess()

      logger.debug("Purchase successful: \(package.storeProduct.productIdentifier)")
      AnalyticsManager.shared.trackEvent(
        .subscriptionStarted,
        parameters: [
          AnalyticsManager.Event.Parameter.subscriptionId: package.identifier,
          AnalyticsManager.Event.Parameter.subscriptionPrice: package.storeProduct.price
        ]
      )

      if let entitlement = customerInfo.entitlements.active.first?.value {
        let isInTrial = entitlement.periodType == .trial
        AnalyticsManager.shared.updateSubscriptionProperties(
          isSubscribed: true,
          isInTrial: isInTrial,
          productId: package.storeProduct.productIdentifier
        )
      }

      return true
    } catch {
      hapticFeedback?.actionError()
      logger.error("Purchase failed: \(error)")

      let (errorType, errorCategory) = categorizeError(error)

      AnalyticsManager.shared.trackError(error, context: "purchase_failed")
      AnalyticsManager.shared.recordNonFatalError(error, additionalInfo: [
        "error_type": errorType,
        "error_category": errorCategory,
        "package_id": package.identifier,
        "package_price": String(describing: package.storeProduct.price),
        "product_id": package.storeProduct.productIdentifier,
        "user_message": purchaseError ?? "none"
      ])
      AnalyticsManager.shared.logCrashlytics("Purchase failed: \(errorType) - \(errorCategory)")

      return false
    }
  }

  // MARK: - Restore

  public func restorePurchases() async -> Bool {
    AnalyticsManager.shared.logCrashlytics("Restore purchases attempt")

    do {
      let customerInfo = try await Purchases.shared.restorePurchases()
      self.customerInfo = customerInfo
      self.isSubscribed = !customerInfo.entitlements.active.isEmpty

      let entitlementsCount = customerInfo.entitlements.active.count
      let hasActiveSubscription = !customerInfo.entitlements.active.isEmpty

      logger.debug("Restore successful")
      AnalyticsManager.shared.trackEvent(.subscriptionRestored, parameters: [
        "entitlements_found": entitlementsCount,
        "has_active_subscription": hasActiveSubscription
      ])
      AnalyticsManager.shared.logCrashlytics("Restore successful: \(entitlementsCount) entitlements")

      return true
    } catch {
      logger.error("Restore failed: \(error)")
      AnalyticsManager.shared.trackError(error, context: "restore_failed")
      AnalyticsManager.shared.recordNonFatalError(error, additionalInfo: [
        "operation": "restore_purchases",
        "error_description": error.localizedDescription
      ])
      AnalyticsManager.shared.logCrashlytics("Restore failed: \(error.localizedDescription)")

      return false
    }
  }

  // MARK: - Package Access

  public func getPackage(for productID: String) -> Package? {
    guard let offerings else { return nil }
    for offering in offerings.all.values {
      for package in offering.availablePackages where package.storeProduct.productIdentifier == productID {
        return package
      }
    }
    return nil
  }

  public func getMonthlyPackage() -> Package? {
    getPackage(for: configuration.monthlyProductID)
  }

  public func getYearlyPackage() -> Package? {
    getPackage(for: configuration.yearlyProductID)
  }

  // MARK: - Entitlements

  public func hasEntitlement(_ entitlementID: String) -> Bool {
    customerInfo?.entitlements.active[entitlementID] != nil
  }

  public func hasProEntitlement() -> Bool {
    hasEntitlement(configuration.proEntitlementID) || isSubscribed
  }

  // MARK: - User Management

  public func setUserID(_ userID: String) async {
    do {
      let customerInfo = try await Purchases.shared.logIn(userID)
      self.customerInfo = customerInfo.customerInfo
      self.isSubscribed = !customerInfo.customerInfo.entitlements.active.isEmpty
      logger.debug("User logged in: \(userID)")
    } catch {
      logger.error("Failed to log in user: \(error)")
    }
  }

  public func logOut() async {
    do {
      let customerInfo = try await Purchases.shared.logOut()
      self.customerInfo = customerInfo
      self.isSubscribed = !customerInfo.entitlements.active.isEmpty
      logger.debug("User logged out")
    } catch {
      logger.error("Failed to log out user: \(error)")
    }
  }

  // MARK: - Access Control

  public var hasAccess: Bool { isSubscribed }
  public var shouldShowPaywall: Bool { !isSubscribed }

  // MARK: - Trial

  public var isInTrialPeriod: Bool {
    guard let customerInfo else { return false }
    return customerInfo.entitlements.active.values.contains { $0.periodType == .trial }
  }

  public var trialInfo: TrialInfo? {
    guard let customerInfo else { return nil }
    for entitlement in customerInfo.entitlements.active.values where entitlement.periodType == .trial {
      let expirationDate = entitlement.expirationDate ?? Date.distantFuture
      let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day ?? 0
      return TrialInfo(
        isActive: true,
        daysRemaining: max(0, daysRemaining),
        isExpired: false,
        startDate: nil
      )
    }
    return nil
  }

  // MARK: - Price Display

  public func getDisplayPrice(for productID: String) -> String {
    getPackage(for: productID)?.storeProduct.localizedPriceString ?? "-"
  }

  public func getMonthlyPrice() -> String { getDisplayPrice(for: configuration.monthlyProductID) }
  public func getYearlyPrice() -> String { getDisplayPrice(for: configuration.yearlyProductID) }

  // MARK: - Purchase by Product ID

  public func purchase(productID: String) async -> Bool {
    isPurchasing = true
    purchaseError = nil
    defer { isPurchasing = false }

    guard let package = getPackage(for: productID) else { return false }
    let success = await purchase(package: package)
    if success { await updateSubscriptionStatus() }
    return success
  }

  public func updateSubscriptionStatus() async {
    await checkSubscriptionStatus()
  }

  // MARK: - Paywall Presentation

  public func presentPaywall(from viewController: UIViewController) async {
    await presentPaywall(from: viewController, offering: offerings?.current)
  }

  public func presentPaywall(from viewController: UIViewController, offering: Offering?) async {
    let top = findTopViewController(from: viewController)
    let paywallViewController = PaywallViewController(offering: offering)
    paywallViewController.delegate = self
    top.present(paywallViewController, animated: true)
  }

  // MARK: - Error Categorization

  private func categorizeError(_ error: Error) -> (type: String, category: String) {
    guard let rcError = error as? RevenueCat.ErrorCode else {
      purchaseError = "Purchase failed. Please try again."
      return ("non_revenuecat", "general")
    }

    switch rcError {
    case .purchaseCancelledError:
      return ("user_cancelled", "user_action")
    case .storeProblemError:
      purchaseError = "Store problem. Please try again later."
      return ("store_problem", "store")
    case .purchaseNotAllowedError:
      purchaseError = "Purchase not allowed on this device."
      return ("not_allowed", "permissions")
    case .purchaseInvalidError:
      purchaseError = "Invalid purchase. Please try again."
      return ("invalid_purchase", "validation")
    case .productNotAvailableForPurchaseError:
      purchaseError = "Product not available for purchase."
      return ("product_unavailable", "store")
    case .productAlreadyPurchasedError:
      purchaseError = "Product already purchased."
      return ("already_purchased", "duplicate")
    case .receiptAlreadyInUseError:
      purchaseError = "Receipt already in use."
      return ("receipt_in_use", "receipt")
    case .invalidReceiptError:
      purchaseError = "Invalid receipt."
      return ("invalid_receipt", "receipt")
    case .missingReceiptFileError:
      purchaseError = "Missing receipt file."
      return ("missing_receipt", "receipt")
    case .networkError:
      purchaseError = "Network error. Please check your connection."
      return ("network", "connectivity")
    case .invalidCredentialsError:
      purchaseError = "Invalid credentials."
      return ("invalid_credentials", "authentication")
    case .unexpectedBackendResponseError:
      purchaseError = "Unexpected backend response."
      return ("backend_error", "server")
    case .receiptInUseByOtherSubscriberError:
      purchaseError = "Receipt in use by another subscriber."
      return ("receipt_other_user", "receipt")
    case .invalidAppUserIdError:
      purchaseError = "Invalid app user ID."
      return ("invalid_user_id", "configuration")
    case .unknownError:
      purchaseError = "Unknown error occurred."
      return ("unknown", "unknown")
    case .paymentPendingError:
      purchaseError = "Payment is pending."
      return ("payment_pending", "payment")
    case .invalidSubscriberAttributesError:
      purchaseError = "Invalid subscriber attributes."
      return ("invalid_attributes", "configuration")
    case .logOutAnonymousUserError:
      purchaseError = "Cannot log out anonymous user."
      return ("logout_anonymous", "authentication")
    case .configurationError:
      purchaseError = "Configuration error."
      return ("configuration", "configuration")
    case .unsupportedError:
      purchaseError = "Unsupported operation."
      return ("unsupported", "compatibility")
    case .productDiscountMissingIdentifierError:
      purchaseError = "Product discount missing identifier."
      return ("discount_error", "validation")
    case .invalidAppleSubscriptionKeyError:
      purchaseError = "Invalid Apple subscription key."
      return ("invalid_key", "configuration")
    case .ineligibleError:
      purchaseError = "Ineligible for purchase."
      return ("ineligible", "permissions")
    case .insufficientPermissionsError:
      purchaseError = "Insufficient permissions."
      return ("insufficient_permissions", "permissions")
    case .customerInfoError:
      purchaseError = "Customer info error."
      return ("customer_info", "data")
    case .systemInfoError:
      purchaseError = "System info error."
      return ("system_info", "system")
    case .beginRefundRequestError:
      purchaseError = "Begin refund request error."
      return ("refund_error", "refund")
    case .apiEndpointBlockedError:
      purchaseError = "API endpoint blocked."
      return ("api_blocked", "connectivity")
    case .invalidPromotionalOfferError:
      purchaseError = "Invalid promotional offer."
      return ("promo_error", "validation")
    default:
      purchaseError = "Purchase failed. Please try again."
      return ("other", "general")
    }
  }

  // MARK: - Helpers

  private func findTopViewController(from viewController: UIViewController) -> UIViewController {
    if let presented = viewController.presentedViewController {
      return findTopViewController(from: presented)
    }
    if let nav = viewController as? UINavigationController {
      return findTopViewController(from: nav.visibleViewController ?? nav)
    }
    if let tab = viewController as? UITabBarController {
      return findTopViewController(from: tab.selectedViewController ?? tab)
    }
    return viewController
  }
}

// MARK: - PurchasesDelegate

extension RevenueCatManager: @MainActor PurchasesDelegate {
  public func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
    Task { @MainActor in
      self.customerInfo = customerInfo
      self.isSubscribed = !customerInfo.entitlements.active.isEmpty
      logger.debug("Customer info updated")
    }
  }
}

// MARK: - PaywallViewControllerDelegate

extension RevenueCatManager: @MainActor PaywallViewControllerDelegate {
  public func paywallViewController(
    _ controller: PaywallViewController,
    didFinishPurchasingWith customerInfo: CustomerInfo
  ) {
    Task { @MainActor in
      self.customerInfo = customerInfo
      self.isSubscribed = !customerInfo.entitlements.active.isEmpty
      logger.debug("Paywall purchase completed")
      controller.dismiss(animated: true)
    }
  }

  public func paywallViewController(
    _ controller: PaywallViewController,
    didFailPurchasingWith error: NSError
  ) {
    logger.error("Paywall purchase failed: \(error)")
  }

  public func paywallViewController(
    _ controller: PaywallViewController,
    didFinishRestoringWith customerInfo: CustomerInfo
  ) {
    Task { @MainActor in
      self.customerInfo = customerInfo
      self.isSubscribed = !customerInfo.entitlements.active.isEmpty
      logger.debug("Paywall restore completed")
      if self.isSubscribed { controller.dismiss(animated: true) }
    }
  }

  public func paywallViewController(
    _ controller: PaywallViewController,
    didFailRestoringWith error: NSError
  ) {
    logger.error("Paywall restore failed: \(error)")
  }

  public func paywallViewControllerWasDismissed(_ controller: PaywallViewController) {
    logger.debug("Paywall dismissed")
    NotificationCenter.default.post(name: .paywallDismissed, object: nil)
  }
}

// MARK: - Notification

public extension Notification.Name {
  static let paywallDismissed = Notification.Name("MMKit.paywallDismissed")
}

// MARK: - TrialInfo

public struct TrialInfo: Sendable {
  public let isActive: Bool
  public let daysRemaining: Int
  public let isExpired: Bool
  public let startDate: Date?

  public init(isActive: Bool, daysRemaining: Int, isExpired: Bool, startDate: Date?) {
    self.isActive = isActive
    self.daysRemaining = daysRemaining
    self.isExpired = isExpired
    self.startDate = startDate
  }

  public var shouldShowPaywall: Bool { isExpired || !isActive }
}
