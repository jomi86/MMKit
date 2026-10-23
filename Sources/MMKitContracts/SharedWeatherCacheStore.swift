import Foundation
import OSLog
import SwiftData

public struct HourlyForecastPoint: Codable, Equatable, Sendable {
  public let date: Date
  public let uvIndex: Int

  public init(date: Date, uvIndex: Int) {
    self.date = date
    self.uvIndex = uvIndex
  }
}

public struct WeatherCacheSnapshot: Equatable, Sendable {
  public let currentUV: Int
  public let maxUV: Int
  public let maxTimeRange: String
  public let recommendation: String
  public let lastUpdate: Date
  public let hourlyForecast: [HourlyForecastPoint]

  public init(
    currentUV: Int,
    maxUV: Int,
    maxTimeRange: String,
    recommendation: String,
    lastUpdate: Date,
    hourlyForecast: [HourlyForecastPoint]
  ) {
    self.currentUV = currentUV
    self.maxUV = maxUV
    self.maxTimeRange = maxTimeRange
    self.recommendation = recommendation
    self.lastUpdate = lastUpdate
    self.hourlyForecast = hourlyForecast
  }
}

@Model
public final class WeatherCacheRecord {
  @Attribute(.unique) public var identifier: String
  public var currentUV: Int
  public var maxUV: Int
  public var maxTimeRange: String
  public var recommendation: String
  public var lastUpdate: Date
  @Relationship(deleteRule: .cascade, inverse: \WeatherHourlyRecord.cacheRecord)
  public var hourlyEntries: [WeatherHourlyRecord]

  public init(
    identifier: String,
    currentUV: Int,
    maxUV: Int,
    maxTimeRange: String,
    recommendation: String,
    lastUpdate: Date,
    hourlyEntries: [WeatherHourlyRecord] = []
  ) {
    self.identifier = identifier
    self.currentUV = currentUV
    self.maxUV = maxUV
    self.maxTimeRange = maxTimeRange
    self.recommendation = recommendation
    self.lastUpdate = lastUpdate
    self.hourlyEntries = hourlyEntries
  }
}

@Model
public final class WeatherHourlyRecord {
  public var date: Date
  public var uvIndex: Int
  public var cacheRecord: WeatherCacheRecord?

  public init(
    date: Date,
    uvIndex: Int,
    cacheRecord: WeatherCacheRecord? = nil
  ) {
    self.date = date
    self.uvIndex = uvIndex
    self.cacheRecord = cacheRecord
  }
}

public protocol WeatherCacheStoring: AnyObject, Sendable {
  func save(snapshot: WeatherCacheSnapshot) throws
  func loadLatestSnapshot() throws -> WeatherCacheSnapshot?
  func uvForCurrentHour(now: Date) throws -> Int?
  func lastUpdateDate() throws -> Date?
  func migrateLegacyIfNeeded(sharedDefaults: UserDefaults?) throws
}

public enum WeatherCacheStoreError: LocalizedError {
  case appGroupContainerUnavailable(String)
  case invalidSnapshot(String)
  case corruptedStoreData(String)
  case legacyStoreUnavailable
  case invalidLegacyData(String)
  case unavailable(String)

  public var errorDescription: String? {
    switch self {
    case let .appGroupContainerUnavailable(identifier):
      return "App Group container unavailable for identifier: \(identifier)"
    case let .invalidSnapshot(reason):
      return "Invalid weather cache snapshot: \(reason)"
    case let .corruptedStoreData(reason):
      return "Corrupted weather cache data: \(reason)"
    case .legacyStoreUnavailable:
      return "Shared UserDefaults unavailable for legacy weather migration."
    case let .invalidLegacyData(reason):
      return "Invalid legacy weather cache data: \(reason)"
    case let .unavailable(reason):
      return "Weather cache store unavailable: \(reason)"
    }
  }
}

public final class SharedWeatherCacheStore: WeatherCacheStoring, @unchecked Sendable {
  public static let shared: any WeatherCacheStoring = {
    let logger = Logger(
      subsystem: "xyz.mcf.TanLine",
      category: "SharedWeatherCacheStore"
    )

    do {
      return try SharedWeatherCacheStore()
    } catch {
      logger.critical(
        "Failed to initialize shared weather cache store: \(error.localizedDescription, privacy: .public)"
      )
      return UnavailableWeatherCacheStore(initializationError: error)
    }
  }()

  private static let cacheIdentifier = "weather-cache-singleton"
  private static let migrationVersionCurrent = 1
  private static let storeFileName = "WeatherCache.sqlite"

  private let modelContainer: ModelContainer
  private let logger = Logger(
    subsystem: "xyz.mcf.TanLine",
    category: "SharedWeatherCacheStore"
  )

  public init(
    isStoredInMemoryOnly: Bool = false,
    appGroupIdentifier: String = SharedAppGroup.identifier
  ) throws {
    self.modelContainer = try SharedWeatherCacheStore.makeModelContainer(
      isStoredInMemoryOnly: isStoredInMemoryOnly,
      appGroupIdentifier: appGroupIdentifier
    )
  }

  public func save(snapshot: WeatherCacheSnapshot) throws {
    try validate(snapshot: snapshot)
    let context = ModelContext(modelContainer)
    let record = try fetchOrCreateRecord(in: context)

    record.currentUV = snapshot.currentUV
    record.maxUV = snapshot.maxUV
    record.maxTimeRange = snapshot.maxTimeRange
    record.recommendation = snapshot.recommendation
    record.lastUpdate = snapshot.lastUpdate

    for entry in record.hourlyEntries {
      context.delete(entry)
    }
    record.hourlyEntries.removeAll(keepingCapacity: true)

    let sortedEntries = snapshot.hourlyForecast.sorted { $0.date < $1.date }
    for point in sortedEntries {
      let hourly = WeatherHourlyRecord(
        date: point.date,
        uvIndex: point.uvIndex,
        cacheRecord: record
      )
      context.insert(hourly)
      record.hourlyEntries.append(hourly)
    }

    if context.hasChanges {
      try context.save()
    }
  }

  public func loadLatestSnapshot() throws -> WeatherCacheSnapshot? {
    let context = ModelContext(modelContainer)
    let record = try fetchRecord(in: context)
    guard let record else {
      return nil
    }

    let hourly = record.hourlyEntries
      .sorted { $0.date < $1.date }
      .map { HourlyForecastPoint(date: $0.date, uvIndex: $0.uvIndex) }

    guard hourly.allSatisfy({ $0.uvIndex >= 0 }) else {
      throw WeatherCacheStoreError.corruptedStoreData(
        "Found negative UV values in stored hourly forecast."
      )
    }

    return WeatherCacheSnapshot(
      currentUV: record.currentUV,
      maxUV: record.maxUV,
      maxTimeRange: record.maxTimeRange,
      recommendation: record.recommendation,
      lastUpdate: record.lastUpdate,
      hourlyForecast: hourly
    )
  }

  public func uvForCurrentHour(now: Date = Date()) throws -> Int? {
    guard let snapshot = try loadLatestSnapshot() else {
      return nil
    }

    for point in snapshot.hourlyForecast {
      let nextHour = point.date.addingTimeInterval(60 * 60)
      if now >= point.date, now < nextHour {
        return point.uvIndex
      }
    }
    return nil
  }

  public func lastUpdateDate() throws -> Date? {
    try loadLatestSnapshot()?.lastUpdate
  }

  public func migrateLegacyIfNeeded(
    sharedDefaults: UserDefaults? = UserDefaults(suiteName: SharedAppGroup.identifier)
  ) throws {
    guard let sharedDefaults else {
      throw WeatherCacheStoreError.legacyStoreUnavailable
    }

    let migratedVersion = sharedDefaults.integer(forKey: WeatherCacheKeys.migrationVersion)
    guard migratedVersion < Self.migrationVersionCurrent else {
      return
    }

    guard let legacySnapshot = try parseLegacySnapshot(from: sharedDefaults) else {
      sharedDefaults.set(
        Self.migrationVersionCurrent,
        forKey: WeatherCacheKeys.migrationVersion
      )
      return
    }

    try save(snapshot: legacySnapshot)
    clearLegacyWeatherKeys(from: sharedDefaults)
    sharedDefaults.set(
      Self.migrationVersionCurrent,
      forKey: WeatherCacheKeys.migrationVersion
    )

    logger.info("Successfully migrated legacy weather cache to SwiftData")
  }

  private func fetchRecord(in context: ModelContext) throws -> WeatherCacheRecord? {
    let cacheIdentifier = Self.cacheIdentifier
    let descriptor = FetchDescriptor<WeatherCacheRecord>(
      predicate: #Predicate { $0.identifier == cacheIdentifier }
    )
    return try context.fetch(descriptor).first
  }

  private func fetchOrCreateRecord(in context: ModelContext) throws -> WeatherCacheRecord {
    if let existing = try fetchRecord(in: context) {
      return existing
    }

    let record = WeatherCacheRecord(
      identifier: Self.cacheIdentifier,
      currentUV: 0,
      maxUV: 0,
      maxTimeRange: "--",
      recommendation: "",
      lastUpdate: Date.distantPast
    )
    context.insert(record)
    return record
  }

  private func validate(snapshot: WeatherCacheSnapshot) throws {
    guard snapshot.currentUV >= 0 else {
      throw WeatherCacheStoreError.invalidSnapshot("currentUV must be non-negative.")
    }

    guard snapshot.maxUV >= 0 else {
      throw WeatherCacheStoreError.invalidSnapshot("maxUV must be non-negative.")
    }

    guard !snapshot.maxTimeRange.isEmpty else {
      throw WeatherCacheStoreError.invalidSnapshot("maxTimeRange must not be empty.")
    }

    guard snapshot.lastUpdate.timeIntervalSince1970 > 0 else {
      throw WeatherCacheStoreError.invalidSnapshot("lastUpdate timestamp is invalid.")
    }

    guard !snapshot.hourlyForecast.isEmpty else {
      throw WeatherCacheStoreError.invalidSnapshot(
        "hourlyForecast must contain at least one entry."
      )
    }

    guard snapshot.hourlyForecast.allSatisfy({ $0.uvIndex >= 0 }) else {
      throw WeatherCacheStoreError.invalidSnapshot(
        "hourlyForecast contains negative UV values."
      )
    }
  }

  private func parseLegacySnapshot(from sharedDefaults: UserDefaults) throws -> WeatherCacheSnapshot? {
    let weatherKeys: [String] = [
      WeatherCacheKeys.currentUV,
      WeatherCacheKeys.maxUV,
      WeatherCacheKeys.maxTimeRange,
      WeatherCacheKeys.recommendation,
      WeatherCacheKeys.lastUpdate,
      WeatherCacheKeys.hourlyForecast,
    ]

    let hasAnyLegacyWeatherValue = weatherKeys.contains {
      sharedDefaults.object(forKey: $0) != nil
    }

    guard hasAnyLegacyWeatherValue else {
      return nil
    }

    guard
      let currentUV = sharedDefaults.object(forKey: WeatherCacheKeys.currentUV) as? NSNumber,
      let maxUV = sharedDefaults.object(forKey: WeatherCacheKeys.maxUV) as? NSNumber,
      let maxTimeRange = sharedDefaults.string(forKey: WeatherCacheKeys.maxTimeRange),
      let recommendation = sharedDefaults.string(forKey: WeatherCacheKeys.recommendation),
      let lastUpdate = sharedDefaults.object(forKey: WeatherCacheKeys.lastUpdate) as? NSNumber,
      let hourlyForecastJSON = sharedDefaults.string(forKey: WeatherCacheKeys.hourlyForecast)
    else {
      throw WeatherCacheStoreError.invalidLegacyData(
        "Legacy weather payload is partial or missing required keys."
      )
    }

    let hourly = try decodeLegacyHourlyForecast(from: hourlyForecastJSON)
    let snapshot = WeatherCacheSnapshot(
      currentUV: currentUV.intValue,
      maxUV: maxUV.intValue,
      maxTimeRange: maxTimeRange,
      recommendation: recommendation,
      lastUpdate: Date(timeIntervalSince1970: lastUpdate.doubleValue),
      hourlyForecast: hourly
    )

    try validate(snapshot: snapshot)
    return snapshot
  }

  private func decodeLegacyHourlyForecast(from jsonString: String) throws -> [HourlyForecastPoint] {
    guard let data = jsonString.data(using: .utf8) else {
      throw WeatherCacheStoreError.invalidLegacyData(
        "Legacy hourly forecast is not valid UTF-8."
      )
    }

    let rawJSON: Any
    do {
      rawJSON = try JSONSerialization.jsonObject(with: data)
    } catch {
      throw WeatherCacheStoreError.invalidLegacyData(
        "Legacy hourly forecast JSON parsing failed: \(error.localizedDescription)"
      )
    }

    guard let array = rawJSON as? [[String: Any]] else {
      throw WeatherCacheStoreError.invalidLegacyData(
        "Legacy hourly forecast JSON has invalid structure."
      )
    }

    let points = try array.map { entry throws -> HourlyForecastPoint in
      guard let timestamp = entry["date"] as? Double else {
        throw WeatherCacheStoreError.invalidLegacyData(
          "Legacy hourly forecast entry is missing date."
        )
      }

      guard let uvValue = entry["uv"] as? Int else {
        throw WeatherCacheStoreError.invalidLegacyData(
          "Legacy hourly forecast entry is missing uv."
        )
      }

      return HourlyForecastPoint(
        date: Date(timeIntervalSince1970: timestamp),
        uvIndex: uvValue
      )
    }

    return points.sorted { $0.date < $1.date }
  }

  private func clearLegacyWeatherKeys(from sharedDefaults: UserDefaults) {
    sharedDefaults.removeObject(forKey: WeatherCacheKeys.currentUV)
    sharedDefaults.removeObject(forKey: WeatherCacheKeys.maxUV)
    sharedDefaults.removeObject(forKey: WeatherCacheKeys.maxTimeRange)
    sharedDefaults.removeObject(forKey: WeatherCacheKeys.recommendation)
    sharedDefaults.removeObject(forKey: WeatherCacheKeys.lastUpdate)
    sharedDefaults.removeObject(forKey: WeatherCacheKeys.hourlyForecast)
  }

  private static func makeModelContainer(
    isStoredInMemoryOnly: Bool,
    appGroupIdentifier: String
  ) throws -> ModelContainer {
    let schema = Schema([WeatherCacheRecord.self, WeatherHourlyRecord.self])

    if isStoredInMemoryOnly {
      let configuration = ModelConfiguration(
        "SharedWeatherCacheInMemory",
        schema: schema,
        isStoredInMemoryOnly: true,
        allowsSave: true,
        groupContainer: .none,
        cloudKitDatabase: .none
      )
      return try ModelContainer(for: schema, configurations: [configuration])
    }

    guard let containerURL = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupIdentifier
    ) else {
      throw WeatherCacheStoreError.appGroupContainerUnavailable(appGroupIdentifier)
    }

    let storeURL = containerURL.appendingPathComponent(Self.storeFileName)
    let configuration = ModelConfiguration(
      "SharedWeatherCache",
      schema: schema,
      url: storeURL,
      allowsSave: true,
      cloudKitDatabase: .none
    )

    return try ModelContainer(for: schema, configurations: [configuration])
  }
}

private final class UnavailableWeatherCacheStore: WeatherCacheStoring, @unchecked Sendable {
  private let initializationError: Error
  private let logger = Logger(
    subsystem: "xyz.mcf.TanLine",
    category: "SharedWeatherCacheStore"
  )

  init(initializationError: Error) {
    self.initializationError = initializationError
  }

  func save(snapshot: WeatherCacheSnapshot) throws {
    throw unavailableError()
  }

  func loadLatestSnapshot() throws -> WeatherCacheSnapshot? {
    throw unavailableError()
  }

  func uvForCurrentHour(now: Date) throws -> Int? {
    throw unavailableError()
  }

  func lastUpdateDate() throws -> Date? {
    throw unavailableError()
  }

  func migrateLegacyIfNeeded(sharedDefaults: UserDefaults?) throws {
    throw unavailableError()
  }

  private func unavailableError() -> WeatherCacheStoreError {
    let reason = initializationError.localizedDescription
    logger.error(
      "Shared weather cache store unavailable: \(reason, privacy: .public)"
    )
    return .unavailable(reason)
  }
}
