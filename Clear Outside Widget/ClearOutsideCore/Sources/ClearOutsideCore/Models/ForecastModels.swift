import Foundation

/// ClearOutside's own composite per-hour rating (from the `fc_hour_ratings` row).
public enum HourRating: String, Codable, Hashable, Sendable {
    case good
    case ok
    case bad
    case unknown
}

public struct HourForecast: Codable, Hashable, Sendable {
    public var date: Date
    /// The hour label as shown on the site (0-23). Day blocks run 17:00 -> 16:00 the next day.
    public var hourLabel: Int
    public var rating: HourRating
    /// "Total Clouds (% Sky Obscured)" - 0 (clear) ... 100 (fully overcast).
    public var totalCloudPercent: Int?
    /// Raw "7Timer Seeing" value as shown on the page (not yet mapped to arcseconds).
    public var seeingRaw: Int?
    /// Raw "7Timer Transparency" value as shown on the page.
    public var transparencyRaw: Int?

    public init(
        date: Date,
        hourLabel: Int,
        rating: HourRating,
        totalCloudPercent: Int? = nil,
        seeingRaw: Int? = nil,
        transparencyRaw: Int? = nil
    ) {
        self.date = date
        self.hourLabel = hourLabel
        self.rating = rating
        self.totalCloudPercent = totalCloudPercent
        self.seeingRaw = seeingRaw
        self.transparencyRaw = transparencyRaw
    }
}

public struct DayForecast: Codable, Hashable, Sendable {
    /// Midnight (local) of the calendar day this block starts on.
    public var date: Date
    public var weekdayName: String
    /// Ordered hourly entries, starting at 17:00 of `date` and running ~24h forward.
    public var hours: [HourForecast]
    public var moonPhaseName: String?
    public var moonIlluminationPercent: Int?
    public var moonrise: Date?
    public var moonset: Date?
    /// Moon meridian transit ("zenith") time.
    public var moonTransit: Date?
    public var sunrise: Date?
    public var sunset: Date?
    /// Civil twilight darkness window (sun >6 deg below horizon).
    public var civilDarkStart: Date?
    public var civilDarkEnd: Date?
    /// Nautical twilight darkness window (sun >12 deg below horizon).
    public var nauticalDarkStart: Date?
    public var nauticalDarkEnd: Date?
    /// Astronomical darkness window (sun >18 deg below horizon) - the best stargazing window.
    public var astroDarkStart: Date?
    public var astroDarkEnd: Date?

    public init(
        date: Date,
        weekdayName: String,
        hours: [HourForecast],
        moonPhaseName: String? = nil,
        moonIlluminationPercent: Int? = nil,
        moonrise: Date? = nil,
        moonset: Date? = nil,
        moonTransit: Date? = nil,
        sunrise: Date? = nil,
        sunset: Date? = nil,
        civilDarkStart: Date? = nil,
        civilDarkEnd: Date? = nil,
        nauticalDarkStart: Date? = nil,
        nauticalDarkEnd: Date? = nil,
        astroDarkStart: Date? = nil,
        astroDarkEnd: Date? = nil
    ) {
        self.date = date
        self.weekdayName = weekdayName
        self.hours = hours
        self.moonPhaseName = moonPhaseName
        self.moonIlluminationPercent = moonIlluminationPercent
        self.moonrise = moonrise
        self.moonset = moonset
        self.moonTransit = moonTransit
        self.sunrise = sunrise
        self.sunset = sunset
        self.civilDarkStart = civilDarkStart
        self.civilDarkEnd = civilDarkEnd
        self.nauticalDarkStart = nauticalDarkStart
        self.nauticalDarkEnd = nauticalDarkEnd
        self.astroDarkStart = astroDarkStart
        self.astroDarkEnd = astroDarkEnd
    }

    /// Fraction (0 = full daylight, 1 = full astronomical darkness) of "night-ness" at a given
    /// moment, ramping through civil -> nautical -> astronomical twilight on both sides of the night.
    public func darknessFraction(at date: Date) -> Double {
        guard let sunset, let sunrise, sunset < sunrise else { return 0 }
        guard date > sunset, date < sunrise else { return 0 }

        let civilStart = civilDarkStart ?? sunset
        let civilEnd = civilDarkEnd ?? sunrise
        let nauticalStart = nauticalDarkStart ?? civilStart
        let nauticalEnd = nauticalDarkEnd ?? civilEnd
        let astroStart = astroDarkStart ?? nauticalStart
        let astroEnd = astroDarkEnd ?? nauticalEnd

        func ramp(_ date: Date, from: Date, to: Date, fromValue: Double, toValue: Double) -> Double {
            guard to > from else { return toValue }
            let progress = date.timeIntervalSince(from) / to.timeIntervalSince(from)
            return fromValue + (toValue - fromValue) * min(max(progress, 0), 1)
        }

        switch date {
        case ..<civilStart:
            return ramp(date, from: sunset, to: civilStart, fromValue: 0, toValue: 1.0 / 3)
        case ..<nauticalStart:
            return ramp(date, from: civilStart, to: nauticalStart, fromValue: 1.0 / 3, toValue: 2.0 / 3)
        case ..<astroStart:
            return ramp(date, from: nauticalStart, to: astroStart, fromValue: 2.0 / 3, toValue: 1.0)
        case ...astroEnd:
            return 1.0
        case ..<nauticalEnd:
            return ramp(date, from: astroEnd, to: nauticalEnd, fromValue: 1.0, toValue: 2.0 / 3)
        case ..<civilEnd:
            return ramp(date, from: nauticalEnd, to: civilEnd, fromValue: 2.0 / 3, toValue: 1.0 / 3)
        default:
            return ramp(date, from: civilEnd, to: sunrise, fromValue: 1.0 / 3, toValue: 0)
        }
    }

    /// Discrete sun-position zone at a given moment, e.g. for categorical (non-gradient) UI.
    public enum SunZone: String, Sendable {
        case day
        case civilTwilight
        case civilDark
        case nauticalDark
        case astroDark
    }

    /// The named darkness zone `date` falls into (mirrors `darknessFraction`'s boundaries,
    /// but as discrete bands rather than a continuous ramp).
    public func sunZone(at date: Date) -> SunZone {
        guard let sunset, let sunrise, sunset < sunrise else { return .day }
        guard date > sunset, date < sunrise else { return .day }

        let civilStart = civilDarkStart ?? sunset
        let civilEnd = civilDarkEnd ?? sunrise
        let nauticalStart = nauticalDarkStart ?? civilStart
        let nauticalEnd = nauticalDarkEnd ?? civilEnd
        let astroStart = astroDarkStart ?? nauticalStart
        let astroEnd = astroDarkEnd ?? nauticalEnd

        switch date {
        case ..<civilStart: return .civilTwilight
        case ..<nauticalStart: return .civilDark
        case ..<astroStart: return .nauticalDark
        case ...astroEnd: return .astroDark
        case ..<nauticalEnd: return .nauticalDark
        case ..<civilEnd: return .civilDark
        default: return .civilTwilight
        }
    }

    /// True if the moon is above the horizon at `date`, handling a moonset that falls the next day.
    public func isMoonUp(at date: Date) -> Bool {
        guard let moonrise else { return false }
        guard let moonset else { return date >= moonrise }
        if moonset >= moonrise {
            return date >= moonrise && date <= moonset
        }
        // Moonset recorded before moonrise means it wraps past midnight into the next day.
        return date >= moonrise || date <= moonset
    }

    /// Hours falling inside the astronomical darkness window (falls back to all hours if unknown).
    public var nightHours: [HourForecast] {
        guard let start = astroDarkStart, let end = astroDarkEnd else { return hours }
        return hours.filter { $0.date >= start && $0.date <= end }
    }

    /// Fraction (0...1) of night hours rated "good" by ClearOutside - the headline quality signal.
    public var goodNightFraction: Double {
        let relevant = nightHours
        guard !relevant.isEmpty else { return 0 }
        let goodCount = relevant.filter { $0.rating == .good }.count
        return Double(goodCount) / Double(relevant.count)
    }

    public var averageNightCloudPercent: Double? {
        let values = nightHours.compactMap { $0.totalCloudPercent }
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }
}

public struct ForecastCache: Codable, Sendable {
    public var fetchedAt: Date
    public var latitude: Double
    public var longitude: Double
    /// Index 0 = today, ascending.
    public var days: [DayForecast]

    public init(fetchedAt: Date, latitude: Double, longitude: Double, days: [DayForecast]) {
        self.fetchedAt = fetchedAt
        self.latitude = latitude
        self.longitude = longitude
        self.days = days
    }
}

/// State the UI (widget or app) renders from - never crashes on missing/stale data.
public enum ForecastLoadState: Sendable {
    case placeholder
    case loaded(ForecastCache)
    case staleCache(ForecastCache, asOf: Date)
    case error(message: String)
}
