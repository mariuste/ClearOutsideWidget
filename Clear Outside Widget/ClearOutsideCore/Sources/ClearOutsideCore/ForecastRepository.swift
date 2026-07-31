import Foundation

/// Used identically by the app and the widget extension - each fetches/caches independently.
/// Defaults to the new Open-Meteo + 7Timer + SunMoonCalculator stack; the app can pass a
/// `ClearOutsideForecastSource` instead if the user picks the fallback source.
public actor ForecastRepository {
    private let source: ForecastSource
    private let store: LocalForecastStore
    private let latitude: Double
    private let longitude: Double

    public init(
        source: ForecastSource = SevenTimerForecastSource(),
        store: LocalForecastStore = LocalForecastStore(),
        latitude: Double = 48.00,
        longitude: Double = 7.85
    ) {
        self.source = source
        self.store = store
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Always performs a fresh fetch, and persists the result on success.
    @discardableResult
    public func refresh() async throws -> ForecastCache {
        let cache = try await source.fetch(latitude: latitude, longitude: longitude)
        try? store.save(cache)
        return cache
    }

    /// Cache-first read: returns cached data if fresh enough, otherwise refreshes,
    /// falling back to stale/last-known-good cache (or `.error`) if the refresh fails.
    public func cachedOrRefresh(maxAge: TimeInterval) async -> ForecastLoadState {
        if let cached = store.load(), Date().timeIntervalSince(cached.fetchedAt) < maxAge {
            return .loaded(cached)
        }

        do {
            let fresh = try await refresh()
            return .loaded(fresh)
        } catch {
            if let stale = store.load() {
                return .staleCache(stale, asOf: stale.fetchedAt)
            }
            return .error(message: String(describing: error))
        }
    }
}
