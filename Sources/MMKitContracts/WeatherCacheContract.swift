import Foundation

public enum SharedAppGroup {
  public static let identifier = "group.com.tanline.app"
}

public enum WeatherCacheKeys {
  // Legacy weather cache keys used for one-time migration to SwiftData.
  public static let currentUV = "cachedCurrentUV"
  public static let maxUV = "cachedMaxUV"
  public static let maxTimeRange = "cachedMaxTimeRange"
  public static let recommendation = "cachedRecommendation"
  public static let lastUpdate = "weatherLastUpdate"

  public static let userLatitude = "userLatitude"
  public static let userLongitude = "userLongitude"

  public static let hourlyForecast = "cachedHourlyForecast"
  public static let migrationVersion = "weatherCacheMigrationVersion"

  public static let spfIsActive = "spfIsActive"
  public static let spfFactor = "spfFactor"
  public static let spfReapplyTime = "spfReapplyTime"
}

public enum WeatherCachePolicy {
  public static let widgetStaleAfter: TimeInterval = 3 * 60 * 60
  public static let widgetTimelineRefreshInterval: TimeInterval = 15 * 60
  public static let daytimeBackgroundRefreshInterval: TimeInterval = 2 * 60 * 60
  public static let nighttimeBackgroundRefreshInterval: TimeInterval = 4 * 60 * 60
  public static let sunsetCacheLifetime: TimeInterval = 60 * 60

  public static func isWidgetDataStale(lastUpdateTimestamp: TimeInterval, now: Date = Date()) -> Bool {
    (now.timeIntervalSince1970 - lastUpdateTimestamp) > widgetStaleAfter
  }
}
