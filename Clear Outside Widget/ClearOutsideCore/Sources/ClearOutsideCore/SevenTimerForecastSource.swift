import Foundation

/// Builds a `ForecastCache` from Open-Meteo (hourly cloud/weather) + 7Timer ASTRO
/// (3-hour seeing/transparency, held constant across the matching hour slots, mirroring
/// how ClearOutside itself displays 7Timer-derived metrics) + a locally computed sun/moon
/// ephemeris (`SunMoonCalculator`) - no HTML scraping involved.
public struct SevenTimerForecastSource: Sendable {
    private let openMeteo: OpenMeteoClient
    private let sevenTimer: SevenTimerClient
    private let calendar: Calendar

    public init(
        openMeteo: OpenMeteoClient = OpenMeteoClient(),
        sevenTimer: SevenTimerClient = SevenTimerClient(),
        calendar: Calendar = .current
    ) {
        self.openMeteo = openMeteo
        self.sevenTimer = sevenTimer
        self.calendar = calendar
    }

    public func fetch(latitude: Double, longitude: Double, days: Int = 6) async throws -> ForecastCache {
        async let weatherResponse = openMeteo.fetch(latitude: latitude, longitude: longitude, forecastDays: days + 1)
        async let astroResponse = sevenTimer.fetch(latitude: latitude, longitude: longitude)
        let (weather, astro) = try await (weatherResponse, astroResponse)

        return Self.merge(
            weather: weather, astro: astro,
            latitude: latitude, longitude: longitude,
            days: days, referenceDate: Date(), calendar: calendar
        )
    }

    // MARK: - Merge (pure function, unit-testable against frozen fixtures)

    static func merge(
        weather: OpenMeteoResponse,
        astro: SevenTimerAstroResponse,
        latitude: Double,
        longitude: Double,
        days: Int,
        referenceDate: Date,
        calendar: Calendar
    ) -> ForecastCache {
        let weatherHours = parseWeatherHours(weather)
        let astroLookup = AstroLookup(response: astro)

        var dayForecasts: [DayForecast] = []
        dayForecasts.reserveCapacity(days)

        for dayIndex in 0..<days {
            let anchor = calendar.date(byAdding: .day, value: dayIndex, to: referenceDate) ?? referenceDate
            let baseDate = calendar.startOfDay(for: anchor)
            dayForecasts.append(
                buildDay(baseDate: baseDate, weatherHours: weatherHours, astroLookup: astroLookup,
                         latitude: latitude, longitude: longitude, calendar: calendar)
            )
        }

        return ForecastCache(fetchedAt: Date(), latitude: latitude, longitude: longitude, days: dayForecasts)
    }

    // MARK: - Open-Meteo hourly parsing

    private struct WeatherHour {
        let date: Date
        let cloudPercent: Int
        let precipitationMm: Double
    }

    private static func parseWeatherHours(_ response: OpenMeteoResponse) -> [WeatherHour] {
        guard let timeZone = TimeZone(identifier: response.timezone) else { return [] }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let hourly = response.hourly
        var result: [WeatherHour] = []
        result.reserveCapacity(hourly.time.count)
        for i in 0..<hourly.time.count {
            guard let date = formatter.date(from: hourly.time[i]) else { continue }
            let cloud = i < hourly.cloudcover.count ? hourly.cloudcover[i] : 0
            let precipitation = i < hourly.precipitation.count ? hourly.precipitation[i] : 0
            result.append(WeatherHour(date: date, cloudPercent: cloud, precipitationMm: precipitation))
        }
        return result
    }

    // MARK: - 7Timer astro lookup (held constant across each 3-hour window)

    /// Wraps the 7Timer response so a given absolute `Date` can be mapped to the 3-hour
    /// bucket ("timepoint") it falls into, or nil if outside the 3-day forecast window.
    private struct AstroLookup {
        let initDate: Date?
        let pointsByTimepoint: [Int: SevenTimerAstroResponse.DataPoint]

        init(response: SevenTimerAstroResponse) {
            initDate = response.initDate
            var map: [Int: SevenTimerAstroResponse.DataPoint] = [:]
            for point in response.dataseries {
                map[point.timepoint] = point
            }
            pointsByTimepoint = map
        }

        /// 7Timer holds each 3-hour value constant across its 3 matching hourly slots -
        /// e.g. timepoint 6 (hours 3...6 after init) covers hours 4, 5, and 6.
        func dataPoint(at date: Date) -> SevenTimerAstroResponse.DataPoint? {
            guard let initDate else { return nil }
            let hoursSinceInit = date.timeIntervalSince(initDate) / 3600
            guard hoursSinceInit > 0 else { return nil }
            let timepoint = Int((hoursSinceInit / 3).rounded(.up)) * 3
            return pointsByTimepoint[timepoint]
        }
    }

    // MARK: - Per-day assembly

    private static func buildDay(
        baseDate: Date,
        weatherHours: [WeatherHour],
        astroLookup: AstroLookup,
        latitude: Double,
        longitude: Double,
        calendar: Calendar
    ) -> DayForecast {
        let windowEnd = calendar.date(byAdding: .day, value: 2, to: baseDate) ?? baseDate

        let relevantWeather = weatherHours.filter { $0.date >= baseDate && $0.date < windowEnd }
        let hours: [HourForecast] = relevantWeather.map { weatherHour in
            let astro = astroLookup.dataPoint(at: weatherHour.date)
            let rating = RatingHeuristic.rate(
                cloudPercent: weatherHour.cloudPercent,
                precipitationMm: weatherHour.precipitationMm,
                seeingRaw: astro?.seeing,
                transparencyRaw: astro?.transparency
            )
            return HourForecast(
                date: weatherHour.date,
                hourLabel: calendar.component(.hour, from: weatherHour.date),
                rating: rating,
                totalCloudPercent: weatherHour.cloudPercent,
                seeingRaw: astro?.seeing,
                transparencyRaw: astro?.transparency
            )
        }

        let sunMoon = sunMoonInfo(baseDate: baseDate, latitude: latitude, longitude: longitude, calendar: calendar)
        let weekdayName = Self.weekdayFormatter.string(from: baseDate)

        return DayForecast(
            date: baseDate,
            weekdayName: weekdayName,
            hours: hours,
            moonPhaseName: sunMoon.moonPhaseName,
            moonIlluminationPercent: sunMoon.moonIlluminationPercent,
            moonrise: sunMoon.moonrise,
            moonset: sunMoon.moonset,
            moonTransit: sunMoon.moonTransit,
            sunrise: sunMoon.sunrise,
            sunset: sunMoon.sunset,
            civilDarkStart: sunMoon.civilDarkStart,
            civilDarkEnd: sunMoon.civilDarkEnd,
            nauticalDarkStart: sunMoon.nauticalDarkStart,
            nauticalDarkEnd: sunMoon.nauticalDarkEnd,
            astroDarkStart: sunMoon.astroDarkStart,
            astroDarkEnd: sunMoon.astroDarkEnd
        )
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    private struct SunMoonInfo {
        var sunrise: Date?
        var sunset: Date?
        var civilDarkStart: Date?
        var civilDarkEnd: Date?
        var nauticalDarkStart: Date?
        var nauticalDarkEnd: Date?
        var astroDarkStart: Date?
        var astroDarkEnd: Date?
        var moonrise: Date?
        var moonset: Date?
        var moonTransit: Date?
        var moonPhaseName: String?
        var moonIlluminationPercent: Int?
    }

    /// This "day" (a night's forecast) runs from this evening's sunset to the next morning's
    /// sunrise, so sun/twilight windows are computed from *two* consecutive calendar days:
    /// today (for sunset/dusk) and tomorrow (for sunrise/dawn) - matching the convention the
    /// rest of the model already assumes (see `ForecastModels.swift`'s doc comments).
    private static func sunMoonInfo(
        baseDate: Date, latitude: Double, longitude: Double, calendar: Calendar
    ) -> SunMoonInfo {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: baseDate) ?? baseDate
        let todayNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: baseDate) ?? baseDate
        let tomorrowNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: tomorrow) ?? tomorrow

        let evening = SunMoonCalculator.sunTimes(for: todayNoon, latitude: latitude, longitude: longitude)
        let morning = SunMoonCalculator.sunTimes(for: tomorrowNoon, latitude: latitude, longitude: longitude)

        var info = SunMoonInfo()
        info.sunset = evening.sunset
        info.civilDarkStart = evening.civilDusk
        info.nauticalDarkStart = evening.nauticalDusk
        info.astroDarkStart = evening.astronomicalDusk

        info.sunrise = morning.sunrise
        info.civilDarkEnd = morning.civilDawn
        info.nauticalDarkEnd = morning.nauticalDawn
        info.astroDarkEnd = morning.astronomicalDawn

        let windowStart = info.sunset ?? todayNoon
        let windowEnd = info.sunrise ?? tomorrowNoon

        let todayMoon = SunMoonCalculator.moonTimes(for: todayNoon, latitude: latitude, longitude: longitude, calendar: calendar)
        let tomorrowMoon = SunMoonCalculator.moonTimes(for: tomorrowNoon, latitude: latitude, longitude: longitude, calendar: calendar)

        let candidateRises = [todayMoon.rise, tomorrowMoon.rise].compactMap { $0 }
        let candidateSets = [todayMoon.set, tomorrowMoon.set].compactMap { $0 }

        // Pick the most recent rise at-or-before the night window ends, then the nearest
        // set at-or-after that rise - reconstructs "is the moon up tonight" without needing
        // a rise/set pair that's both within a single arbitrary calendar day.
        let moonrise = candidateRises.filter { $0 <= windowEnd }.max() ?? candidateRises.min()
        let moonset = candidateSets.filter { moonrise == nil || $0 >= moonrise! }.min() ?? candidateSets.max()
        info.moonrise = moonrise
        info.moonset = moonset

        let todayTransit = SunMoonCalculator.moonTransit(for: todayNoon, latitude: latitude, longitude: longitude, calendar: calendar)
        let tomorrowTransit = SunMoonCalculator.moonTransit(for: tomorrowNoon, latitude: latitude, longitude: longitude, calendar: calendar)
        info.moonTransit = nearest(
            in: [todayTransit, tomorrowTransit].compactMap { $0 },
            toMidpointOf: windowStart, and: windowEnd
        )

        let illumination = SunMoonCalculator.moonIllumination(for: todayNoon)
        info.moonPhaseName = SunMoonCalculator.moonPhaseName(forPhase: illumination.phase)
        info.moonIlluminationPercent = Int((illumination.fraction * 100).rounded())

        return info
    }

    private static func nearest(in candidates: [Date], toMidpointOf start: Date, and end: Date) -> Date? {
        guard !candidates.isEmpty else { return nil }
        let midpoint = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
        return candidates.min(by: { abs($0.timeIntervalSince(midpoint)) < abs($1.timeIntervalSince(midpoint)) })
    }
}
