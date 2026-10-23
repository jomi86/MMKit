import Foundation

public struct WidgetForecastSummary: Equatable, Sendable {
  public let maxUV: Int
  public let maxTimeRange: String

  public init(maxUV: Int, maxTimeRange: String) {
    self.maxUV = maxUV
    self.maxTimeRange = maxTimeRange
  }
}

public enum WidgetForecastSummaryCalculator {
  public static func summary(
    for date: Date,
    forecast: [HourlyForecastPoint],
    fallbackMaxUV: Int,
    fallbackMaxTimeRange: String,
    calendar: Calendar = .autoupdatingCurrent
  ) -> WidgetForecastSummary {
    let dayEntries = forecast.filter { point in
      calendar.isDate(point.date, inSameDayAs: date)
    }

    guard !dayEntries.isEmpty else {
      return WidgetForecastSummary(
        maxUV: fallbackMaxUV,
        maxTimeRange: fallbackMaxTimeRange
      )
    }

    let maxUV = dayEntries.map(\.uvIndex).max() ?? fallbackMaxUV
    let maxHours = dayEntries.filter { $0.uvIndex == maxUV }.sorted { $0.date < $1.date }

    guard let first = maxHours.first?.date, let last = maxHours.last?.date else {
      return WidgetForecastSummary(
        maxUV: maxUV,
        maxTimeRange: fallbackMaxTimeRange
      )
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "HH:mm"

    let start = formatter.string(from: first)
    let end = formatter.string(from: last)
    let range = start == end ? start : "\(start)-\(end)"

    return WidgetForecastSummary(maxUV: maxUV, maxTimeRange: range)
  }
}
