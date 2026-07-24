import XCTest
@testable import LiquidGlassCore

final class ConfigurationTests: XCTestCase {
    func testBalancedDefaultsValidate() throws {
        XCTAssertNoThrow(try LiquidGlassConfiguration.default.validated())
        XCTAssertEqual(LiquidGlassConfiguration.default.preset, .balanced)
    }

    func testPresetMutationReplacesOpticalParameters() throws {
        let updated = try LiquidGlassConfiguration.default.applying([.preset(.vivid)])
        XCTAssertEqual(updated.preset, .vivid)
        XCTAssertGreaterThan(updated.refractionStrength, LiquidGlassConfiguration.default.refractionStrength)
        XCTAssertGreaterThan(updated.causticStrength, LiquidGlassConfiguration.default.causticStrength)
    }

    func testDetailedMutationsAreAppliedAndValidated() throws {
        let updated = try LiquidGlassConfiguration.default.applying([
            .cornerRadius(24),
            .tint(try RGBAColor(hex: "#11223344")),
            .refraction(21),
            .dispersion(2.2),
            .captureFPS(45),
            .renderScale(0.65)
        ])
        XCTAssertEqual(updated.cornerRadius, 24)
        XCTAssertEqual(updated.tint.hex, "#11223344")
        XCTAssertEqual(updated.refractionStrength, 21)
        XCTAssertEqual(updated.dispersionStrength, 2.2)
        XCTAssertEqual(updated.captureFramesPerSecond, 45)
        XCTAssertEqual(updated.renderScale, 0.65)
    }

    func testInvalidRefractionIsRejected() {
        var configuration = LiquidGlassConfiguration.default
        configuration.refractionStrength = 100
        XCTAssertThrowsError(try configuration.validated())
    }
}
