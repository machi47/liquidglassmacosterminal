import Foundation
import XCTest
@testable import LiquidGlassCore

final class ProcessRunnerTests: XCTestCase {
    func testDrainsLargeStandardOutputAndErrorConcurrently() async throws {
        let runner = FoundationProcessRunner()
        let result = try await runner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c",
                "dd if=/dev/zero bs=1024 count=256 2>/dev/null; "
                    + "dd if=/dev/zero bs=1024 count=256 1>&2 2>/dev/null"
            ]
        )

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.standardOutput.utf8.count, 256 * 1024)
        XCTAssertEqual(result.standardError.utf8.count, 256 * 1024)
    }

    func testNonzeroExitPreservesStatusAndStandardError() async throws {
        let runner = FoundationProcessRunner()

        do {
            _ = try await runner.run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf 'intentional failure' >&2; exit 7"]
            )
            XCTFail("Expected a process failure.")
        } catch let error as LiquidGlassError {
            guard case .processFailed(_, let status, let standardError) = error else {
                return XCTFail("Unexpected LiquidGlassError: \(error)")
            }
            XCTAssertEqual(status, 7)
            XCTAssertEqual(standardError, "intentional failure")
        }
    }
}
