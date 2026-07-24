import Foundation
#if os(macOS)
import Darwin
#elseif os(Linux)
import Glibc
#endif

/// An advisory process-wide mutex backed by `lockf(3)`.
///
/// Each CLI invocation is a separate process, so Swift actors alone cannot
/// serialize concurrent `on`, `off`, and configuration transactions. The lock
/// is released automatically by the kernel when the owning process exits or
/// crashes.
public final class InterprocessFileLock: @unchecked Sendable {
    private var descriptor: Int32 = -1

    public init(
        url: URL,
        timeout: TimeInterval = 15,
        pollInterval: TimeInterval = 0.05,
        fileManager: FileManager = .default
    ) throws {
        guard timeout.isFinite, timeout >= 0 else {
            throw LiquidGlassError.state("The operation-lock timeout must be nonnegative and finite.")
        }
        guard pollInterval.isFinite, pollInterval > 0 else {
            throw LiquidGlassError.state("The operation-lock poll interval must be positive and finite.")
        }

        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !fileManager.fileExists(atPath: url.path) {
                guard fileManager.createFile(
                    atPath: url.path,
                    contents: Data(),
                    attributes: [.posixPermissions: 0o600]
                ) else {
                    throw LiquidGlassError.fileSystem("Unable to create the LiquidGlass operation lock.")
                }
            }
        } catch let error as LiquidGlassError {
            throw error
        } catch {
            throw LiquidGlassError.fileSystem(
                "Unable to prepare the LiquidGlass operation lock: \(error.localizedDescription)"
            )
        }

        #if os(macOS) || os(Linux)
        let opened = platformOpen(url.path)
        guard opened >= 0 else {
            throw LiquidGlassError.fileSystem(
                "Unable to open the LiquidGlass operation lock: \(platformErrorDescription())."
            )
        }
        descriptor = opened

        let deadline = Date().addingTimeInterval(timeout)
        while platformTryLock(opened) != 0 {
            let code = errno
            guard code == EACCES || code == EAGAIN else {
                platformClose(opened)
                descriptor = -1
                throw LiquidGlassError.state(
                    "Unable to acquire the LiquidGlass operation lock: \(platformErrorDescription(code))."
                )
            }
            guard Date() < deadline else {
                platformClose(opened)
                descriptor = -1
                throw LiquidGlassError.state(
                    "Another LiquidGlass command is still running. Wait for it to finish, then retry."
                )
            }
            let microseconds = useconds_t(min(pollInterval, 1) * 1_000_000)
            platformSleep(microseconds)
        }
        #else
        throw LiquidGlassError.unsupportedPlatform
        #endif
    }

    deinit {
        #if os(macOS) || os(Linux)
        guard descriptor >= 0 else { return }
        _ = platformUnlock(descriptor)
        platformClose(descriptor)
        descriptor = -1
        #endif
    }
}

#if os(macOS)
private func platformOpen(_ path: String) -> Int32 { Darwin.open(path, O_RDWR) }
private func platformTryLock(_ descriptor: Int32) -> Int32 {
    Darwin.lockf(descriptor, F_TLOCK, 0)
}
private func platformUnlock(_ descriptor: Int32) -> Int32 {
    Darwin.lockf(descriptor, F_ULOCK, 0)
}
private func platformClose(_ descriptor: Int32) { _ = Darwin.close(descriptor) }
private func platformSleep(_ microseconds: useconds_t) { _ = Darwin.usleep(microseconds) }
private func platformErrorDescription(_ code: Int32 = errno) -> String {
    String(cString: Darwin.strerror(code))
}
#elseif os(Linux)
private func platformOpen(_ path: String) -> Int32 { Glibc.open(path, O_RDWR) }
private func platformTryLock(_ descriptor: Int32) -> Int32 {
    Glibc.lockf(descriptor, F_TLOCK, 0)
}
private func platformUnlock(_ descriptor: Int32) -> Int32 {
    Glibc.lockf(descriptor, F_ULOCK, 0)
}
private func platformClose(_ descriptor: Int32) { _ = Glibc.close(descriptor) }
private func platformSleep(_ microseconds: useconds_t) { _ = Glibc.usleep(microseconds) }
private func platformErrorDescription(_ code: Int32 = errno) -> String {
    String(cString: Glibc.strerror(code))
}
#endif
