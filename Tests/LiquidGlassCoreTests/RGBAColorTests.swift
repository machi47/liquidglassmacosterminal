import XCTest
@testable import LiquidGlassCore

final class RGBAColorTests: XCTestCase {
    func testParsesEightDigitHex() throws {
        let color = try RGBAColor(hex: "#10203080")
        XCTAssertEqual(color.red, 16.0 / 255.0, accuracy: 0.000_001)
        XCTAssertEqual(color.green, 32.0 / 255.0, accuracy: 0.000_001)
        XCTAssertEqual(color.blue, 48.0 / 255.0, accuracy: 0.000_001)
        XCTAssertEqual(color.alpha, 128.0 / 255.0, accuracy: 0.000_001)
        XCTAssertEqual(color.hex, "#10203080")
    }

    func testParsesShortHex() throws {
        XCTAssertEqual(try RGBAColor(hex: "#abc").hex, "#AABBCCFF")
        XCTAssertEqual(try RGBAColor(hex: "#abcd").hex, "#AABBCCDD")
    }

    func testRejectsMalformedColor() {
        XCTAssertThrowsError(try RGBAColor(hex: "#12"))
        XCTAssertThrowsError(try RGBAColor(hex: "#GGHHII"))
    }
}
