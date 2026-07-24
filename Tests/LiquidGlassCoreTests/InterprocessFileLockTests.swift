import Foundation
import XCTest
@testable import LiquidGlassCore

final class InterprocessFileLockTests: XCTestCase {
    func testCompetingProcessTimesOutAndLockBecomesAvailableAfterRelease() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockURL = directory.appendingPathComponent("operation.lock")

        guard let python = executableOnPath(named: "python3") else {
            throw XCTSkip("python3 is unavailable; cross-process POSIX lock probe skipped.")
        }

        let readyPipe = Pipe()
        let errorPipe = Pipe()
        let holder = Process()
        holder.executableURL = python
        holder.arguments = [
            "-u",
            "-c",
            """
            import fcntl
            import pathlib
            import sys
            import time

            path = pathlib.Path(sys.argv[1])
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open("a+") as handle:
                fcntl.lockf(handle.fileno(), fcntl.LOCK_EX)
                print("ready", flush=True)
                time.sleep(10)
            """,
            lockURL.path
        ]
        holder.standardOutput = readyPipe
        holder.standardError = errorPipe

        try holder.run()
        defer {
            if holder.isRunning {
                holder.terminate()
            }
            holder.waitUntilExit()
        }

        let ready = readyPipe.fileHandleForReading.availableData
        let readyText = String(decoding: ready, as: UTF8.self)
        guard readyText.contains("ready") else {
            let stderr = String(
                decoding: errorPipe.fileHandleForReading.availableData,
                as: UTF8.self
            )
            XCTFail("The lock-holder process did not start: \(stderr)")
            return
        }

        XCTAssertThrowsError(
            try InterprocessFileLock(
                url: lockURL,
                timeout: 0.15,
                pollInterval: 0.01
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("still running"))
        }

        holder.terminate()
        holder.waitUntilExit()

        let acquired = try InterprocessFileLock(
            url: lockURL,
            timeout: 1,
            pollInterval: 0.01
        )
        withExtendedLifetime(acquired) {}
    }

    private func executableOnPath(named name: String) -> URL? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory), isDirectory: true)
                .appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
