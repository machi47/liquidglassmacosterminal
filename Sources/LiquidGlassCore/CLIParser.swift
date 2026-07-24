import Foundation

public enum CLICommand: Equatable, Sendable {
    case on
    case off
    case toggle
    case status(json: Bool)
    case doctor(prompt: Bool, json: Bool)
    case permissions
    case configShow(json: Bool)
    case configSet([ConfigurationMutation])
    case configReset
    case version
    case help
    case purgeState
}

public enum ConfigurationMutation: Equatable, Sendable {
    case preset(GlassPreset)
    case tint(RGBAColor)
    case terminalOpacity(Double)
    case terminalBlur(Double)
    case renderScale(Double)
    case captureFPS(Int)
    case renderFPS(Int)
    case blurSigma(Double)
    case refraction(Double)
    case dispersion(Double)
    case flowScale(Double)
    case flowSpeed(Double)
    case edge(Double)
    case caustics(Double)
    case saturation(Double)
    case cornerRadius(Double)
    case grain(Double)
    case followInterval(Int)
    case reduceMotion(Bool)
}

public struct CLIParser: Sendable {
    public init() {}

    public func parse(_ arguments: [String]) throws -> CLICommand {
        guard let first = arguments.first else { return .help }
        let command = normalize(first)
        let rest = Array(arguments.dropFirst())

        switch command {
        case "on":
            try requireEmpty(rest, command: "on")
            return .on
        case "off":
            try requireEmpty(rest, command: "off")
            return .off
        case "toggle":
            try requireEmpty(rest, command: "toggle")
            return .toggle
        case "status":
            return .status(json: try onlyJSON(rest, command: "status"))
        case "doctor":
            var prompt = false
            var json = false
            for argument in rest {
                switch argument {
                case "--prompt": prompt = true
                case "--json": json = true
                default: throw LiquidGlassError.invalidArguments("Unknown doctor option: \(argument)")
                }
            }
            return .doctor(prompt: prompt, json: json)
        case "permissions":
            try requireEmpty(rest, command: "permissions")
            return .permissions
        case "version", "--version", "-v":
            try requireEmpty(rest, command: "version")
            return .version
        case "help", "--help", "-h":
            return .help
        case "purge-state":
            try requireEmpty(rest, command: "purge-state")
            return .purgeState
        case "config":
            return try parseConfig(rest)
        default:
            throw LiquidGlassError.invalidArguments("Unknown command: \(first)")
        }
    }

    private func parseConfig(_ arguments: [String]) throws -> CLICommand {
        guard let action = arguments.first else { return .configShow(json: false) }
        let rest = Array(arguments.dropFirst())
        switch action {
        case "show": return .configShow(json: try onlyJSON(rest, command: "config show"))
        case "reset":
            try requireEmpty(rest, command: "config reset")
            return .configReset
        case "preset":
            guard rest.count == 1, let preset = GlassPreset(rawValue: rest[0].lowercased()) else {
                throw LiquidGlassError.invalidArguments("Usage: liquidglass config preset subtle|balanced|vivid")
            }
            return .configSet([.preset(preset)])
        case "set":
            return .configSet(try parseMutations(rest))
        default:
            throw LiquidGlassError.invalidArguments("Unknown config action: \(action)")
        }
    }

    private func parseMutations(_ arguments: [String]) throws -> [ConfigurationMutation] {
        guard !arguments.isEmpty else {
            throw LiquidGlassError.invalidArguments("config set requires at least one option.")
        }
        var mutations: [ConfigurationMutation] = []
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard index + 1 < arguments.count else {
                throw LiquidGlassError.invalidArguments("Missing value after \(option).")
            }
            let raw = arguments[index + 1]
            switch option {
            case "--preset":
                guard let value = GlassPreset(rawValue: raw.lowercased()) else {
                    throw LiquidGlassError.invalidArguments("--preset must be subtle, balanced, or vivid.")
                }
                mutations.append(.preset(value))
            case "--tint": mutations.append(.tint(try RGBAColor(hex: raw)))
            case "--terminal-opacity": mutations.append(.terminalOpacity(try parseDouble(raw, option)))
            case "--terminal-blur": mutations.append(.terminalBlur(try parseDouble(raw, option)))
            case "--render-scale": mutations.append(.renderScale(try parseDouble(raw, option)))
            case "--capture-fps": mutations.append(.captureFPS(try parseInt(raw, option)))
            case "--render-fps": mutations.append(.renderFPS(try parseInt(raw, option)))
            case "--blur": mutations.append(.blurSigma(try parseDouble(raw, option)))
            case "--refraction": mutations.append(.refraction(try parseDouble(raw, option)))
            case "--dispersion": mutations.append(.dispersion(try parseDouble(raw, option)))
            case "--flow-scale": mutations.append(.flowScale(try parseDouble(raw, option)))
            case "--flow-speed": mutations.append(.flowSpeed(try parseDouble(raw, option)))
            case "--edge": mutations.append(.edge(try parseDouble(raw, option)))
            case "--caustics": mutations.append(.caustics(try parseDouble(raw, option)))
            case "--saturation": mutations.append(.saturation(try parseDouble(raw, option)))
            case "--corner-radius": mutations.append(.cornerRadius(try parseDouble(raw, option)))
            case "--grain": mutations.append(.grain(try parseDouble(raw, option)))
            case "--follow-ms": mutations.append(.followInterval(try parseInt(raw, option)))
            case "--reduce-motion": mutations.append(.reduceMotion(try parseBool(raw, option)))
            default: throw LiquidGlassError.invalidArguments("Unknown config option: \(option)")
            }
            index += 2
        }
        return mutations
    }

    private func normalize(_ command: String) -> String {
        switch command {
        case "-on", "--on": return "on"
        case "-off", "--off": return "off"
        default: return command.lowercased()
        }
    }

    private func requireEmpty(_ arguments: [String], command: String) throws {
        guard arguments.isEmpty else {
            throw LiquidGlassError.invalidArguments("\(command) does not accept arguments.")
        }
    }

    private func onlyJSON(_ arguments: [String], command: String) throws -> Bool {
        switch arguments {
        case []: return false
        case ["--json"]: return true
        default: throw LiquidGlassError.invalidArguments("\(command) accepts only --json.")
        }
    }

    private func parseDouble(_ value: String, _ option: String) throws -> Double {
        guard let result = Double(value), result.isFinite else {
            throw LiquidGlassError.invalidArguments("\(option) requires a finite number.")
        }
        return result
    }

    private func parseInt(_ value: String, _ option: String) throws -> Int {
        guard let result = Int(value) else {
            throw LiquidGlassError.invalidArguments("\(option) requires an integer.")
        }
        return result
    }

    private func parseBool(_ value: String, _ option: String) throws -> Bool {
        switch value.lowercased() {
        case "true", "yes", "1", "on": return true
        case "false", "no", "0", "off": return false
        default: throw LiquidGlassError.invalidArguments("\(option) requires true or false.")
        }
    }
}
