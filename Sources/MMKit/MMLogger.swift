import OSLog

public class MMLogger {
    @MainActor public static let shared = MMLogger()
    
    private let logger: Logger
    
    private init() {
        logger = Logger.init()
    }
    
    public func log(_ message: String, level: LogType = .info) {
        switch level {
        case .debug:
            logger.log(level: .debug, "\(message)")
        case .info:
            logger.log(level: .info, "\(message)")
        case .warning:
            logger.log(level: .fault, "\(message)")
        case .error:
            logger.log(level: .error, "\(message)")
        }
    }
}

public enum LogType {
    case debug
    case info
    case warning
    case error
}
