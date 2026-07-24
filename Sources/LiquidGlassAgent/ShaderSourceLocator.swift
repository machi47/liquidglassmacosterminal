#if os(macOS)
import Foundation
import LiquidGlassCore

enum ShaderSourceLocator {
    static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> URL {
        var candidates: [URL] = []

        if let override = environment["LIQUIDGLASS_SHADER_PATH"], !override.isEmpty {
            candidates.append(URL(fileURLWithPath: override))
        }

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("LiquidGlass.metal"))
        }

        if let executableURL = Bundle.main.executableURL {
            candidates.append(
                executableURL
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("Resources/LiquidGlass.metal")
            )
            candidates.append(
                executableURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("LiquidGlass.metal")
            )
        }

        let currentDirectory = URL(
            fileURLWithPath: fileManager.currentDirectoryPath,
            isDirectory: true
        )
        candidates.append(
            currentDirectory.appendingPathComponent(
                "Sources/LiquidGlassAgent/Resources/LiquidGlass.metal"
            )
        )
        candidates.append(currentDirectory.appendingPathComponent("LiquidGlass.metal"))

        for candidate in unique(candidates) {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                continue
            }
            return candidate.standardizedFileURL
        }

        let inspected = unique(candidates).map(\.path).joined(separator: "\n  - ")
        throw LiquidGlassError.agent(
            "The LiquidGlass Metal shader could not be located. Checked:\n  - \(inspected)"
        )
    }

    static func validateInstalledResource() throws -> URL {
        let url = try locate()
        let source = try String(contentsOf: url, encoding: .utf8)
        let requiredFunctions = ["liquidGlassVertex", "liquidGlassFragment"]
        let missing = requiredFunctions.filter { !source.contains($0) }
        guard missing.isEmpty else {
            throw LiquidGlassError.agent(
                "The installed Metal shader is incomplete; missing: \(missing.joined(separator: ", "))."
            )
        }
        return url
    }

    private static func unique(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}
#endif
