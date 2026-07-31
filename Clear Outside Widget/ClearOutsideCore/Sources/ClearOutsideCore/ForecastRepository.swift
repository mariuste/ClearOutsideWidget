import Foundation

/// Used identically by the app and the widget extension - each fetches/caches independently.
/// Takes a `ForecastSourceKind` (not a raw `ForecastSource`) so its on-disk cache can be
/// namespaced per source - otherwise switching sources could read back a still-fresh cache
/// entry the *other* source wrote, and the UI would silently keep showing old data.
public actor ForecastRepository {
    private let source: ForecastSource
    private let store: LocalForecastStore
    private let latitude: Double
    private let longitude: Double

    public init(
        sourceKind: ForecastSourceKind = .sevenTimerStack,
        latitude: Double = 48.00,
        longitude: Double = 7.85
    ) {
        self.source = sourceKind.makeSource()
        self.store = LocalForecastStore(namespace: sourceKind.rawValue)
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
