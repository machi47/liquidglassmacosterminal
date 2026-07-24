import Foundation

public enum LiquidGlassError: LocalizedError, Equatable {
    case unsupportedPlatform
    case invalidArguments(String)
    case invalidConfiguration(String)
    case fileSystem(String)
    case processFailed(executable: String, status: Int32, stderr: String)
    case terminalPreferences(String)
    case terminalAutomation(String)
    case agent(String)
    case state(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            return "LiquidGlass Terminal requires macOS."
        case .invalidArguments(let message),
             .invalidConfiguration(let message),
             .fileSystem(let message),
             .terminalPreferences(let message),
             .terminalAutomation(let message),
             .agent(let message),
             .state(let message):
            return message
        case .processFailed(let executable, let status, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "\(executable) exited with status \(status)."
                : "\(executable) exited with status \(status): \(detail)"
        }
    }
}
