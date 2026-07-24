import Foundation

public enum GlassPreset: String, Codable, CaseIterable, Sendable {
    case subtle
    case balanced
    case vivid
}

public struct LiquidGlassConfiguration: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var managedProfileName: String

    public var preset: GlassPreset
    public var tint: RGBAColor
    public var terminalBackgroundOpacity: Double
    public var terminalBackgroundBlur: Double

    public var renderScale: Double
    public var captureFramesPerSecond: Int
    public var renderFramesPerSecond: Int
    public var blurSigma: Double
    public var refractionStrength: Double
    public var dispersionStrength: Double
    public var flowScale: Double
    public var flowSpeed: Double
    public var edgeStrength: Double
    public var causticStrength: Double
    public var saturation: Double
    public var cornerRadius: Double
    public var grainStrength: Double
    public var reduceMotion: Bool
    public var followIntervalMilliseconds: Int

    public init(
        schemaVersion: Int = LiquidGlassVersion.schemaVersion,
        managedProfileName: String = LiquidGlassVersion.managedProfileName,
        preset: GlassPreset = .balanced,
        tint: RGBAColor = RGBAColor(red: 0.035, green: 0.055, blue: 0.085, alpha: 0.18),
        terminalBackgroundOpacity: Double = 0.012,
        terminalBackgroundBlur: Double = 0,
        renderScale: Double = 0.5,
        captureFramesPerSecond: Int = 30,
        renderFramesPerSecond: Int = 60,
        blurSigma: Double = 16,
        refractionStrength: Double = 15,
        dispersionStrength: Double = 1.6,
        flowScale: Double = 3.1,
        flowSpeed: Double = 0.16,
        edgeStrength: Double = 0.82,
        causticStrength: Double = 0.42,
        saturation: Double = 1.08,
        cornerRadius: Double = 18,
        grainStrength: Double = 0.018,
        reduceMotion: Bool = false,
        followIntervalMilliseconds: Int = 16
    ) {
        self.schemaVersion = schemaVersion
        self.managedProfileName = managedProfileName
        self.preset = preset
        self.tint = tint
        self.terminalBackgroundOpacity = terminalBackgroundOpacity
        self.terminalBackgroundBlur = terminalBackgroundBlur
        self.renderScale = renderScale
        self.captureFramesPerSecond = captureFramesPerSecond
        self.renderFramesPerSecond = renderFramesPerSecond
        self.blurSigma = blurSigma
        self.refractionStrength = refractionStrength
        self.dispersionStrength = dispersionStrength
        self.flowScale = flowScale
        self.flowSpeed = flowSpeed
        self.edgeStrength = edgeStrength
        self.causticStrength = causticStrength
        self.saturation = saturation
        self.cornerRadius = cornerRadius
        self.grainStrength = grainStrength
        self.reduceMotion = reduceMotion
        self.followIntervalMilliseconds = followIntervalMilliseconds
    }

    public static let `default` = LiquidGlassConfiguration()

    public static func preset(_ preset: GlassPreset) -> LiquidGlassConfiguration {
        switch preset {
        case .subtle:
            return LiquidGlassConfiguration(
                preset: .subtle,
                tint: RGBAColor(red: 0.025, green: 0.035, blue: 0.055, alpha: 0.12),
                blurSigma: 13,
                refractionStrength: 8,
                dispersionStrength: 0.7,
                flowScale: 3.6,
                flowSpeed: 0.10,
                edgeStrength: 0.48,
                causticStrength: 0.18,
                saturation: 1.02,
                grainStrength: 0.010
            )
        case .balanced:
            return .default
        case .vivid:
            return LiquidGlassConfiguration(
                preset: .vivid,
                tint: RGBAColor(red: 0.055, green: 0.075, blue: 0.12, alpha: 0.23),
                renderScale: 0.58,
                blurSigma: 20,
                refractionStrength: 23,
                dispersionStrength: 2.8,
                flowScale: 2.65,
                flowSpeed: 0.22,
                edgeStrength: 1.15,
                causticStrength: 0.72,
                saturation: 1.16,
                grainStrength: 0.025
            )
        }
    }

    @discardableResult
    public func validated() throws -> LiquidGlassConfiguration {
        guard schemaVersion == LiquidGlassVersion.schemaVersion else {
            throw LiquidGlassError.invalidConfiguration(
                "Unsupported configuration schema \(schemaVersion); expected \(LiquidGlassVersion.schemaVersion). Run `liquidglass config reset`."
            )
        }
        guard !managedProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LiquidGlassError.invalidConfiguration("The managed Terminal profile name cannot be empty.")
        }
        _ = try tint.validated(label: "Tint")
        try validate(terminalBackgroundOpacity, in: 0...0.20, name: "Terminal background opacity")
        try validate(terminalBackgroundBlur, in: 0...1, name: "Terminal background blur")
        try validate(renderScale, in: 0.25...1, name: "Render scale")
        guard (10...60).contains(captureFramesPerSecond) else {
            throw LiquidGlassError.invalidConfiguration("Capture FPS must be between 10 and 60.")
        }
        guard (15...120).contains(renderFramesPerSecond) else {
            throw LiquidGlassError.invalidConfiguration("Render FPS must be between 15 and 120.")
        }
        try validate(blurSigma, in: 0...40, name: "Blur sigma")
        try validate(refractionStrength, in: 0...60, name: "Refraction strength")
        try validate(dispersionStrength, in: 0...8, name: "Dispersion strength")
        try validate(flowScale, in: 0.25...12, name: "Flow scale")
        try validate(flowSpeed, in: 0...2, name: "Flow speed")
        try validate(edgeStrength, in: 0...3, name: "Edge strength")
        try validate(causticStrength, in: 0...2, name: "Caustic strength")
        try validate(saturation, in: 0...2, name: "Saturation")
        try validate(cornerRadius, in: 0...80, name: "Corner radius")
        try validate(grainStrength, in: 0...0.15, name: "Grain strength")
        guard (8...250).contains(followIntervalMilliseconds) else {
            throw LiquidGlassError.invalidConfiguration("Window follow interval must be between 8 and 250 milliseconds.")
        }
        return self
    }

    public func applying(_ mutations: [ConfigurationMutation]) throws -> LiquidGlassConfiguration {
        var updated = self
        for mutation in mutations {
            switch mutation {
            case .preset(let value):
                let presetConfiguration = LiquidGlassConfiguration.preset(value)
                updated.preset = value
                updated.tint = presetConfiguration.tint
                updated.renderScale = presetConfiguration.renderScale
                updated.blurSigma = presetConfiguration.blurSigma
                updated.refractionStrength = presetConfiguration.refractionStrength
                updated.dispersionStrength = presetConfiguration.dispersionStrength
                updated.flowScale = presetConfiguration.flowScale
                updated.flowSpeed = presetConfiguration.flowSpeed
                updated.edgeStrength = presetConfiguration.edgeStrength
                updated.causticStrength = presetConfiguration.causticStrength
                updated.saturation = presetConfiguration.saturation
                updated.grainStrength = presetConfiguration.grainStrength
            case .tint(let value): updated.tint = value
            case .terminalOpacity(let value): updated.terminalBackgroundOpacity = value
            case .terminalBlur(let value): updated.terminalBackgroundBlur = value
            case .renderScale(let value): updated.renderScale = value
            case .captureFPS(let value): updated.captureFramesPerSecond = value
            case .renderFPS(let value): updated.renderFramesPerSecond = value
            case .blurSigma(let value): updated.blurSigma = value
            case .refraction(let value): updated.refractionStrength = value
            case .dispersion(let value): updated.dispersionStrength = value
            case .flowScale(let value): updated.flowScale = value
            case .flowSpeed(let value): updated.flowSpeed = value
            case .edge(let value): updated.edgeStrength = value
            case .caustics(let value): updated.causticStrength = value
            case .saturation(let value): updated.saturation = value
            case .cornerRadius(let value): updated.cornerRadius = value
            case .grain(let value): updated.grainStrength = value
            case .followInterval(let value): updated.followIntervalMilliseconds = value
            case .reduceMotion(let value): updated.reduceMotion = value
            }
        }
        return try updated.validated()
    }

    private func validate(_ value: Double, in range: ClosedRange<Double>, name: String) throws {
        guard value.isFinite, range.contains(value) else {
            throw LiquidGlassError.invalidConfiguration(
                "\(name) must be between \(range.lowerBound) and \(range.upperBound)."
            )
        }
    }
}
