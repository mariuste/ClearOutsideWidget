import Foundation

/// Raw decode of 7Timer!'s ASTRO product (`product=astro`). Non-commercial use only,
/// updates only ~4x/day - see REDESIGN_PLAN.md for the full terms summary.
public struct SevenTimerAstroResponse: Codable, Sendable {
    public let product: String
    /// Model run init time, UTC, format "yyyyMMddHH".
    public let initTimeRaw: String
    /// Ordered forecast points, `timepoint` hours after `initTimeRaw`, 3-hour steps.
    public let dataseries: [DataPoint]

    enum CodingKeys: String, CodingKey {
        case product
        case initTimeRaw = "init"
        case dataseries
    }

    /// `initTimeRaw` parsed as a UTC `Date`, or nil if malformed.
    public var initDate: Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard initTimeRaw.count == 10,
              let year = Int(initTimeRaw.prefix(4)),
              let month = Int(initTimeRaw.dropFirst(4).prefix(2)),
              let day = Int(initTimeRaw.dropFirst(6).prefix(2)),
              let hour = Int(initTimeRaw.suffix(2))
        else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components)
    }

    public struct DataPoint: Codable, Sendable {
        /// Hours after `initTimeRaw` this point represents (3-hour steps: 3, 6, 9, ...).
        public let timepoint: Int
        /// Bucketed 1-9 (see doc: 1 = 0-6% cloud ... 9 = 94-100%).
        public let cloudcover: Int
        /// Bucketed 1-8 (1 = <0.5" seeing/best ... 8 = >2.5"/worst).
        public let seeing: Int
        /// Bucketed 1-8 (1 = <0.3 mag/airmass/best ... 8 = >1/worst).
        public let transparency: Int
        public let liftedIndex: Int
        /// Bucketed -4...16, each step ~5% (see doc table), not a direct percentage.
        public let rh2m: Int
        public let wind10m: Wind10m
        /// Raw degrees Celsius (not bucketed).
        public let temp2m: Int
        /// "none", "rain", "snow", "frzr", "icep".
        public let precType: String

        enum CodingKeys: String, CodingKey {
            case timepoint
            case cloudcover
            case seeing
            case transparency
            case liftedIndex = "lifted_index"
            case rh2m
            case wind10m
            case temp2m
            case precType = "prec_type"
        }
    }

    public struct Wind10m: Codable, Sendable {
        public let direction: String
        public let speed: Int
    }
}

public enum SevenTimerClientError: Error, Equatable {
    case badStatus(Int)
}

public struct SevenTimerClient: Sendable {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        self.session = URLSession(configuration: configuration)
    }

    public func fetch(latitude: Double, longitude: Double) async throws -> SevenTimerAstroResponse {
        var components = URLComponents(string: "https://www.7timer.info/bin/api.pl")!
        components.queryItems = [
            URLQueryItem(name: "lon", value: String(longitude)),
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "product", value: "astro"),
            URLQueryItem(name: "output", value: "json"),
            URLQueryItem(name: "unit", value: "metric"),
            URLQueryItem(name: "tzshift", value: "0")
        ]

        let (data, response) = try await session.data(from: components.url!)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw SevenTimerClientError.badStatus(httpResponse.statusCode)
        }
        return try JSONDecoder().decode(SevenTimerAstroResponse.self, from: data)
    }
}
