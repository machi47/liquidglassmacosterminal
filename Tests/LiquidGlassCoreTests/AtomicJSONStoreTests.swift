import Foundation
import XCTest
@testable import LiquidGlassCore

final class AtomicJSONStoreTests: XCTestCase {
    func testRoundTripAndReset() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = AtomicJSONStore<LiquidGlassConfiguration>(
            url: directory.appendingPathComponent("config.json"),
            defaultValue: { .default }
        )

        let initial = try await store.load()
        XCTAssertEqual(initial, .default)
        var changed = LiquidGlassConfiguration.default
        changed.cornerRadius = 31
        try await store.save(changed)
        let saved = try await store.load()
        XCTAssertEqual(saved.cornerRadius, 31)
        try await store.reset()
        let reset = try await store.load()
        XCTAssertEqual(reset, .default)
    }
    func testMalformedJSONProducesActionableStateError() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("state.json")
        try Data("{ definitely-not-json".utf8).write(to: file)
        let store = AtomicJSONStore<LiquidGlassState>(url: file, defaultValue: { .disabled })

        do {
            _ = try await store.load()
            XCTFail("Expected malformed JSON to fail.")
        } catch let error as LiquidGlassError {
            guard case .state(let message) = error else {
                return XCTFail("Unexpected LiquidGlassError: \(error)")
            }
            XCTAssertTrue(message.contains("state.json"))
        }
    }

}
