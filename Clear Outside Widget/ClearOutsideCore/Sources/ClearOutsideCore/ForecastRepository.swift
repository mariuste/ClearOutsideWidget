import Foundation

/// Used identically by the app and the widget extension - each fetches/caches independently.
public actor ForecastRepository {
    private let client: ClearOutsideClient
    private let store: LocalForecastStore

    public init(client: ClearOutsideClient = ClearOutsideClient(), store: LocalForecastStore = LocalForecastStore()) {
        self.client = client
        self.store = store
    }

    /// Always performs a fresh fetch + parse, and persists the result on success.
    @discardableResult
    public func refresh() async throws -> ForecastCache {
        let html = try await client.fetchHTML()
        let cache = try ClearOutsideParser.parse(html: html)
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
