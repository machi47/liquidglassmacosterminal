import Foundation

public struct ProcessResult: Sendable, Equatable {
    public let status: Int32
    public let standardOutput: String
    public let standardError: String

    public init(status: Int32, standardOutput: String, standardError: String) {
        self.status = status
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public protocol ProcessRunning: Sendable {
    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]?,
        input: Data?
    ) async throws -> ProcessResult
}

public extension ProcessRunning {
    func run(
        executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        input: Data? = nil
    ) async throws -> ProcessResult {
        try await run(executable: executable, arguments: arguments, environment: environment, input: input)
    }
}

public struct FoundationProcessRunner: ProcessRunning {
    public init() {}

    public func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]?,
        input: Data?
    ) async throws -> ProcessResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            if let environment {
                process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, replacement in
                    replacement
                }
            }

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            var inputPipe: Pipe?
            if input != nil {
                let pipe = Pipe()
                process.standardInput = pipe
                inputPipe = pipe
            }

            do {
                try process.run()
            } catch {
                throw LiquidGlassError.processFailed(
                    executable: executable.path,
                    status: -1,
                    stderr: error.localizedDescription
                )
            }

            // Drain both pipes concurrently. Reading them sequentially after
            // process termination can deadlock when either pipe fills first.
            async let outputData = Task.detached(priority: .utility) {
                outputPipe.fileHandleForReading.readDataToEndOfFile()
            }.value
            async let errorData = Task.detached(priority: .utility) {
                errorPipe.fileHandleForReading.readDataToEndOfFile()
            }.value

            if let input, let inputPipe {
                inputPipe.fileHandleForWriting.write(input)
                try? inputPipe.fileHandleForWriting.close()
            }

            process.waitUntilExit()
            let (capturedOutput, capturedError) = await (outputData, errorData)

            let result = ProcessResult(
                status: process.terminationStatus,
                standardOutput: String(decoding: capturedOutput, as: UTF8.self),
                standardError: String(decoding: capturedError, as: UTF8.self)
            )

            guard result.status == 0 else {
                throw LiquidGlassError.processFailed(
                    executable: executable.path,
                    status: result.status,
                    stderr: result.standardError
                )
            }
            return result
        }.value
    }
}
