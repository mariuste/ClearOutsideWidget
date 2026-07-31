import Foundation

/// Fallback `ForecastSource` wrapping the original ClearOutside HTML scraper - kept around
/// (not deleted) in case the new Open-Meteo/7Timer stack is ever unavailable or wrong.
/// `latitude`/`longitude` are ignored: `ClearOutsideClient` always targets the URL it was
/// built for (48.00/7.85), same as before this source abstraction existed.
public struct ClearOutsideForecastSource: ForecastSource {
    private let client: ClearOutsideClient

    public init(client: ClearOutsideClient = ClearOutsideClient()) {
        self.client = client
    }

    public func fetch(latitude: Double, longitude: Double) async throws -> ForecastCache {
        let html = try await client.fetchHTML()
        return try ClearOutsideParser.parse(html: html)
    }
}
