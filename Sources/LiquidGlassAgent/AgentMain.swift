import Foundation
import LiquidGlassCore

#if os(macOS)
import AppKit

@main
struct LiquidGlassAgentMain {
    @MainActor
    static func main() {
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
