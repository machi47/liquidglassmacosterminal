import Foundation
import LiquidGlassCore

#if os(macOS)
import AppKit
import Darwin

@main
struct LiquidGlassAgentMain {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--validate-resources") {
            do {
                let shaderURL = try ShaderSourceLocator.validateInstalledResource()
                FileHandle.standardOutput.write(
                    Data("LiquidGlass resources valid: \(shaderURL.path)\n".utf8)
                )
                exit(EXIT_SUCCESS)
            } catch {
                FileHandle.standardError.write(
                    Data("LiquidGlass resource validation failed: \(error.localizedDescription)\n".utf8)
                )
                exit(EXIT_FAILURE)
            }
        }

        let application = NSApplication.shared
        let delegate = AgentApplicationDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

#else

@main
struct LiquidGlassAgentMain {
    static func main() {
        FileHandle.standardError.write(Data("LiquidGlassAgent requires macOS.\n".utf8))
    }
}

#endif
