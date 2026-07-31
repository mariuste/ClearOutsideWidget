import Foundation

/// Per-target local cache (no App Group - app and widget extension each cache independently,
/// since a free Apple Developer account cannot enable the App Groups capability).
///
/// Namespaced by `namespace` (in practice, the `ForecastSourceKind`) so switching sources
/// doesn't read back the *other* source's still-fresh cache entry - each source gets its own
/// slot instead of silently overwriting/reusing one shared key.
public struct LocalForecastStore: @unchecked Sendable {
    private static let baseKey = "com.mariuste.ClearOutsideCore.forecastCache"

    private let defaults: UserDefaults
    private let key: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(defaults: UserDefaults = .standard, namespace: String = "default") {
        self.defaults = defaults
        self.key = "\(Self.baseKey).\(namespace)"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func save(_ cache: ForecastCache) throws {
        let data = try encoder.encode(cache)
        defaults.set(data, forKey: key)
    }

    public func load() -> ForecastCache? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(ForecastCache.self, from: data)
    }
}
