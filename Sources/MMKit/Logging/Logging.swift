import Foundation
import OSLog

public protocol Logging {
  func debug(_ message: OSLogMessage)
  func info(_ message: OSLogMessage)
  func notice(_ message: OSLogMessage)
  func warning(_ message: OSLogMessage)
  func error(_ message: OSLogMessage)
  func critical(_ message: OSLogMessage)
}

extension Logger: Logging {}

public protocol LoggerProviding {
  func makeLogger(category: String) -> Logger
}

public struct LoggerFactory: LoggerProviding {
  public let subsystem: String

  public init(subsystem: String = Bundle.main.bundleIdentifier ?? "TanLine") {
    self.subsystem = subsystem
  }

  public func makeLogger(category: String) -> Logger {
    Logger(subsystem: subsystem, category: category)
  }
}
