import XCTest
@testable import LiquidGlassCore

final class CLIParserTests: XCTestCase {
    private let parser = CLIParser()

    func testRequestedOnOffAliases() throws {
        XCTAssertEqual(try parser.parse(["-on"]), .on)
        XCTAssertEqual(try parser.parse(["--on"]), .on)
        XCTAssertEqual(try parser.parse(["-off"]), .off)
        XCTAssertEqual(try parser.parse(["--off"]), .off)
    }

    func testPresetCommand() throws {
        XCTAssertEqual(
            try parser.parse(["config", "preset", "vivid"]),
            .configSet([.preset(.vivid)])
        )
    }

    func testMetalConfigurationOptions() throws {
        let command = try parser.parse([
            "config", "set",
            "--refraction", "19",
            "--dispersion", "2.4",
            "--blur", "17",
            "--tint", "#00000022",
            "--render-fps", "60"
        ])
        XCTAssertEqual(command, .configSet([
            .refraction(19),
            .dispersion(2.4),
            .blurSigma(17),
            .tint(try RGBAColor(hex: "#00000022")),
            .renderFPS(60)
        ]))
    }

    func testUnknownOptionFails() {
        XCTAssertThrowsError(try parser.parse(["config", "set", "--fake", "1"]))
    }
}
