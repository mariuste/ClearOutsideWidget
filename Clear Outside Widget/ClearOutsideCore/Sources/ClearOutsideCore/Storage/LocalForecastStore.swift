import Foundation

/// Per-target local cache (no App Group - app and widget extension each cache independently,
/// since a free Apple Developer account cannot enable the App Groups capability).
public struct LocalForecastStore: @unchecked Sendable {
    private static let key = "com.mariuste.ClearOutsideCore.forecastCache"

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func save(_ cache: ForecastCache) throws {
        let data = try encoder.encode(cache)
        defaults.set(data, forKey: Self.key)
    }

    public func load() -> ForecastCache? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? decoder.decode(ForecastCache.self, from: data)
    }
}
