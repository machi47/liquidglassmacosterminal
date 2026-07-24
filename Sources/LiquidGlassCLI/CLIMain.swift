import Foundation
import LiquidGlassCore
#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif

@main
struct LiquidGlassCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let parser = CLIParser()

        do {
            let command = try parser.parse(arguments)
            if command == .help {
                write(helpText)
                return
            }
            if command == .version {
                write("liquidglass \(LiquidGlassVersion.current)\n")
                return
            }

            #if !os(macOS)
            throw LiquidGlassError.unsupportedPlatform
            #else
            let paths = AppPaths()
            let operationLock: InterprocessFileLock? = command.requiresExclusiveOperation
                ? try InterprocessFileLock(url: paths.operationLockFile)
                : nil
            defer { withExtendedLifetime(operationLock) {} }

            let runner = FoundationProcessRunner()
            let controller = LiquidGlassController(
                paths: paths,
                preferences: SystemTerminalPreferences(paths: paths),
                automation: SystemTerminalAutomation(runner: runner, paths: paths),
                agent: SystemAgentSignal(runner: runner)
            )

            switch command {
            case .on:
                let status = try await controller.turnOn()
                write("LiquidGlass enabled. Existing and future Terminal windows use the Metal compositor.\n")
                write(statusSummary(status))
            case .off:
                let status = try await controller.turnOff()
                write("LiquidGlass disabled. Terminal profiles were restored.\n")
                write(statusSummary(status))
            case .toggle:
                let status = try await controller.toggle()
                write(status.enabled ? "LiquidGlass enabled.\n" : "LiquidGlass disabled.\n")
                write(statusSummary(status))
            case .status(let json):
                let status = try await controller.status()
                write(json ? try encodedJSON(status) : statusSummary(status))
            case .doctor(let prompt, let json):
                let checks = await controller.doctor(promptForPermissions: prompt)
                write(json ? try encodedJSON(checks) : doctorSummary(checks))
                if checks.contains(where: { $0.severity == .failure }) { terminate(2) }
            case .permissions:
                let checks = await controller.doctor(promptForPermissions: true)
                    .filter { $0.name == "screen-capture" || $0.name == "automation" }
                write(doctorSummary(checks))
                if checks.contains(where: { $0.severity == .failure }) { terminate(2) }
            case .configShow(let json):
                let configuration = try await controller.loadConfiguration()
                write(json ? try encodedJSON(configuration) : configurationSummary(configuration))
            case .configSet(let mutations):
                let configuration = try await controller.updateConfiguration(mutations)
                write("Configuration updated live.\n")
                write(configurationSummary(configuration))
            case .configReset:
                let configuration = try await controller.resetConfiguration()
                write("Configuration reset to balanced.\n")
                write(configurationSummary(configuration))
            case .purgeState:
                try await controller.purgeState()
                write("LiquidGlass state and configuration removed.\n")
            case .version, .help:
                break
            }
            #endif
        } catch {
            writeError("liquidglass: \(error.localizedDescription)\n")
            if error is LiquidGlassError {
                writeError("Run `liquidglass doctor --prompt` for installation and permission diagnostics.\n")
            }
            terminate(1)
        }
    }

    private static func encodedJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(value), as: UTF8.self) + "\n"
    }

    private static func statusSummary(_ status: LiquidGlassStatus) -> String {
        let transition = status.transition.map { " (\($0.rawValue))" } ?? ""
        var lines = [
            "Enabled: \(status.enabled ? "yes" : "no")\(transition)",
            "Agent: \(status.agentLoaded ? "loaded" : "not loaded")",
            "Terminal: \(status.terminalRunning ? "running" : "not running")",
            "Managed profile: \(status.managedProfileInstalled ? "installed" : "not installed")",
            "Preset: \(status.configuration.preset.rawValue)",
            "Renderer: ScreenCaptureKit + Metal"
        ]
        if let error = status.lastError { lines.append("Last error: \(error)") }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func configurationSummary(_ value: LiquidGlassConfiguration) -> String {
        """
        Preset: \(value.preset.rawValue)
        Tint: \(value.tint.hex)
        Terminal aperture opacity: \(formatted(value.terminalBackgroundOpacity))
        Render scale: \(formatted(value.renderScale))
        Capture / render FPS: \(value.captureFramesPerSecond) / \(value.renderFramesPerSecond)
        Blur sigma: \(formatted(value.blurSigma))
        Refraction: \(formatted(value.refractionStrength)) px
        Dispersion: \(formatted(value.dispersionStrength)) px
        Flow scale / speed: \(formatted(value.flowScale)) / \(formatted(value.flowSpeed))
        Edge / caustics: \(formatted(value.edgeStrength)) / \(formatted(value.causticStrength))
        Saturation: \(formatted(value.saturation))
        Corner radius: \(formatted(value.cornerRadius)) pt
        Grain: \(formatted(value.grainStrength))
        Follow interval: \(value.followIntervalMilliseconds) ms
        Reduce motion: \(value.reduceMotion ? "yes" : "no")
        """ + "\n"
    }

    private static func doctorSummary(_ checks: [DoctorCheck]) -> String {
        checks.map { check in
            let marker: String
            switch check.severity {
            case .pass: marker = "PASS"
            case .warning: marker = "WARN"
            case .failure: marker = "FAIL"
            }
            return "[\(marker)] \(check.name): \(check.message)"
        }.joined(separator: "\n") + "\n"
    }

    private static func formatted(_ value: Double) -> String {
        String(format: "%.3f", value)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    private static func write(_ value: String) {
        FileHandle.standardOutput.write(Data(value.utf8))
    }

    private static func writeError(_ value: String) {
        FileHandle.standardError.write(Data(value.utf8))
    }

    private static func terminate(_ status: Int32) -> Never { exit(status) }

    private static let helpText = """
    LiquidGlass Terminal \(LiquidGlassVersion.current)

    A real-time ScreenCaptureKit + Metal liquid-glass compositor behind normal Terminal.app windows.

    USAGE
      liquidglass on                          Enable now and at login
      liquidglass off                         Disable and restore Terminal
      liquidglass toggle                      Toggle state
      liquidglass status [--json]             Show persistent state
      liquidglass doctor [--prompt] [--json]  Check agent, GPU, capture, and Automation
      liquidglass permissions                 Request/check required permissions
      liquidglass config show [--json]        Show shader configuration
      liquidglass config preset NAME          subtle | balanced | vivid
      liquidglass config set OPTIONS          Tune the shader live
      liquidglass config reset                Restore balanced defaults
      liquidglass version                     Print version

    `-on`, `--on`, `-off`, and `--off` are aliases.

    CONFIG OPTIONS
      --preset subtle|balanced|vivid
      --tint #RRGGBBAA
      --terminal-opacity 0...0.20
      --terminal-blur 0...1
      --render-scale 0.25...1
      --capture-fps 10...60
      --render-fps 15...120
      --blur 0...40
      --refraction 0...60
      --dispersion 0...8
      --flow-scale 0.25...12
      --flow-speed 0...2
      --edge 0...3
      --caustics 0...2
      --saturation 0...2
      --corner-radius 0...80
      --grain 0...0.15
      --follow-ms 8...250
      --reduce-motion true|false

    EXAMPLES
      liquidglass on
      liquidglass config preset vivid
      liquidglass config set --refraction 20 --edge 1.0 --blur 18
      liquidglass off
    """ + "\n"
}

private extension CLICommand {
    var requiresExclusiveOperation: Bool {
        switch self {
        case .on, .off, .toggle, .configSet, .configReset, .purgeState:
            return true
        case .status, .doctor, .configShow, .permissions, .version, .help:
            return false
        }
    }
}
