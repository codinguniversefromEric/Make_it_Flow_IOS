import Foundation
import os

enum LogLevel: String {
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case crash = "CRASH"
    
    var prefix: String {
        switch self {
        case .info: return "🟢 [INFO]"
        case .warning: return "🟠 [WARNING]"
        case .error: return "🔴 [ERROR]"
        case .crash: return "💥 [CRASH]"
        }
    }
}

class AppLogger: @unchecked Sendable {
    static let shared = AppLogger()
    private let osLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.libriai.ePdfUB", category: "AppLog")
    
    private init() {}
    
    nonisolated func info(_ message: String) { log(level: .info, message: message) }
    nonisolated func warning(_ message: String) { log(level: .warning, message: message) }
    nonisolated func error(_ message: String) { log(level: .error, message: message) }
    nonisolated func crash(_ message: String) { log(level: .crash, message: message) }
    
    nonisolated private func log(level: LogLevel, message: String) {
        let formatted = "\(level.prefix) \(message)"
        
        #if DEBUG || targetEnvironment(macCatalyst)
        print(formatted)
        #endif
        
        switch level {
        case .info: osLogger.info("\(message, privacy: .public)")
        case .warning: osLogger.warning("\(message, privacy: .public)")
        case .error: osLogger.error("\(message, privacy: .public)")
        case .crash: osLogger.fault("\(message, privacy: .public)")
        }
    }
}
