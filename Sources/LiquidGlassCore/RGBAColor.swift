import Foundation

public struct RGBAColor: Codable, Equatable, Sendable, CustomStringConvertible {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(hex: String) throws {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }

        switch value.count {
        case 3, 4:
            value = value.map { "\($0)\($0)" }.joined()
        case 6, 8:
            break
        default:
            throw LiquidGlassError.invalidConfiguration(
                "Color '\(hex)' must be #RGB, #RGBA, #RRGGBB, or #RRGGBBAA."
            )
        }

        guard let raw = UInt64(value, radix: 16) else {
            throw LiquidGlassError.invalidConfiguration("Color '\(hex)' is not valid hexadecimal.")
        }

        let hasAlpha = value.count == 8
        let redShift = hasAlpha ? 24 : 16
        let greenShift = hasAlpha ? 16 : 8
        let blueShift = hasAlpha ? 8 : 0

        self.red = Double((raw >> UInt64(redShift)) & 0xFF) / 255
        self.green = Double((raw >> UInt64(greenShift)) & 0xFF) / 255
        self.blue = Double((raw >> UInt64(blueShift)) & 0xFF) / 255
        self.alpha = hasAlpha ? Double(raw & 0xFF) / 255 : 1
    }

    public func validated(label: String = "Color") throws -> RGBAColor {
        let components = [red, green, blue, alpha]
        guard components.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw LiquidGlassError.invalidConfiguration("\(label) components must be between 0 and 1.")
        }
        return self
    }

    public var hex: String {
        func channel(_ value: Double) -> Int {
            Int((min(max(value, 0), 1) * 255).rounded())
        }
        return String(
            format: "#%02X%02X%02X%02X",
            channel(red), channel(green), channel(blue), channel(alpha)
        )
    }

    public var description: String { hex }
}
