import Foundation

/// Raw decode of Open-Meteo's `/v1/forecast` hourly response. Non-commercial use only,
/// data licensed CC-BY 4.0 - see REDESIGN_PLAN.md for the full terms summary.
public struct OpenMeteoResponse: Codable, Sendable {
    public let latitude: Double
    public let longitude: Double
    /// IANA time zone name (e.g. "Europe/Berlin") - `hourly.time` strings are local to this zone.
    public let timezone: String
    public let hourly: Hourly

    public struct Hourly: Codable, Sendable {
        /// Local time strings, e.g. "2026-07-31T00:00" (no offset, no seconds).
        public let time: [String]
        public let cloudcover: [Int]
        public let cloudcoverLow: [Int]
        public let cloudcoverMid: [Int]
        public let cloudcoverHigh: [Int]
        public let temperature2m: [Double]
        public let precipitation: [Double]
        public let windspeed10m: [Double]
        public let relativehumidity2m: [Int]
        public let pressureMsl: [Double]
        public let visibility: [Double]

        enum CodingKeys: String, CodingKey {
            case time
            case cloudcover
            case cloudcoverLow = "cloudcover_low"
            case cloudcoverMid = "cloudcover_mid"
            case cloudcoverHigh = "cloudcover_high"
            case temperature2m = "temperature_2m"
            case precipitation
            case windspeed10m = "windspeed_10m"
            case relativehumidity2m = "relativehumidity_2m"
            case pressureMsl = "pressure_msl"
            case visibility
        }
    }
}

public enum OpenMeteoClientError: Error, Equatable {
    case badStatus(Int)
}

public struct OpenMeteoClient: Sendable {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        self.session = URLSession(configuration: configuration)
    }

    public func fetch(latitude: Double, longitude: Double, forecastDays: Int = 7) async throws -> OpenMeteoResponse {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "hourly", value: [
                "cloudcover", "cloudcover_low", "cloudcover_mid", "cloudcover_high",
                "temperature_2m", "precipitation", "windspeed_10m",
                "relativehumidity_2m", "pressure_msl", "visibility"
            ].joined(separator: ",")),
            URLQueryItem(name: "forecast_days", value: String(forecastDays)),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        let (data, response) = try await session.data(from: components.url!)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw OpenMeteoClientError.badStatus(httpResponse.statusCode)
        }
        return try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
    }
}
