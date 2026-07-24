import Foundation
#if canImport(OSLog)
import OSLog
#endif

public enum LogLevel: String, Sendable {
    case debug
    case info
    case warning
    case error
}

public protocol LiquidGlassLogging: Sendable {
    func log(_ level: LogLevel, _ message: @autoclosure () -> String)
}

public struct StandardLogger: LiquidGlassLogging {
    private let subsystem: String
    private let category: String

    public init(subsystem: String = "com.machi47.liquidglass", category: String) {
        self.subsystem = subsystem
        self.category = category
    }

    public func log(_ level: LogLevel, _ message: @autoclosure () -> String) {
        let rendered = message()
        #if canImport(OSLog)
        let logger = Logger(subsystem: subsystem, category: category)
        switch level {
        case .debug:
            logger.debug("\(rendered, privacy: .public)")
        case .info:
            logger.info("\(rendered, privacy: .public)")
        case .warning:
            logger.warning("\(rendered, privacy: .public)")
        case .error:
            logger.error("\(rendered, privacy: .public)")
        }
        #else
        FileHandle.standardError.write(Data("[\(level.rawValue)] \(rendered)\n".utf8))
        #endif
    }
}

public struct NullLogger: LiquidGlassLogging {
    public init() {}
    public func log(_ level: LogLevel, _ message: @autoclosure () -> String) {}
}
