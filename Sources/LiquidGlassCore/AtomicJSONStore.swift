import Foundation

public actor AtomicJSONStore<Value: Codable & Sendable> {
    private let url: URL
    private let defaultValue: @Sendable () -> Value
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager

    public init(
        url: URL,
        defaultValue: @escaping @Sendable () -> Value,
        fileManager: FileManager = .default
    ) {
        self.url = url
        self.defaultValue = defaultValue
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func load() throws -> Value {
        guard fileManager.fileExists(atPath: url.path) else {
            return defaultValue()
        }

        do {
            return try decoder.decode(Value.self, from: Data(contentsOf: url))
        } catch {
            throw LiquidGlassError.state("Unable to read \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    public func save(_ value: Value) throws {
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            throw LiquidGlassError.state("Unable to write \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    public func reset() throws {
        if fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                throw LiquidGlassError.state("Unable to remove \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
}
