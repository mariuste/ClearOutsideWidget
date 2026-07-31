import XCTest
@testable import ClearOutsideCore

final class SevenTimerForecastSourceTests: XCTestCase {
    private let latitude = 48.00
    private let longitude = 7.85

    private var berlinCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    /// Matches the frozen fixtures: Open-Meteo data starts 2026-07-31T00:00 local, 7Timer's
    /// model run is init'd 2026-07-31 12:00 UTC.
    private func referenceDate() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 31
        components.hour = 10
        return berlinCalendar.date(from: components)!
    }

    private func loadWeather() throws -> OpenMeteoResponse {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "sample_openmeteo", withExtension: "json"))
        return try JSONDecoder().decode(OpenMeteoResponse.self, from: Data(contentsOf: url))
    }

    private func loadAstro() throws -> SevenTimerAstroResponse {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "sample_7timer_astro", withExtension: "json"))
        return try JSONDecoder().decode(SevenTimerAstroResponse.self, from: Data(contentsOf: url))
    }

    private func merge(days: Int = 6) throws -> ForecastCache {
        SevenTimerForecastSource.merge(
            weather: try loadWeather(), astro: try loadAstro(),
            latitude: latitude, longitude: longitude,
            days: days, referenceDate: referenceDate(), calendar: berlinCalendar
        )
    }

    func testProducesRequestedNumberOfDays() throws {
        let cache = try merge(days: 6)
        XCTAssertEqual(cache.days.count, 6)
        XCTAssertEqual(cache.latitude, latitude)
        XCTAssertEqual(cache.longitude, longitude)
    }

    func testFirstDayIsTodayWithPopulatedHours() throws {
        let cache = try merge()
        let today = cache.days[0]

        let expectedStart = berlinCalendar.startOfDay(for: referenceDate())
        XCTAssertEqual(today.date, expectedStart)
        XCTAssertFalse(today.hours.isEmpty)
    }

    func testSunAndTwilightTimesArePopulatedAndOrdered() throws {
        let cache = try merge()
        let today = cache.days[0]

        let sunset = try XCTUnwrap(today.sunset)
        let sunrise = try XCTUnwrap(today.sunrise)
        let astroStart = try XCTUnwrap(today.astroDarkStart)
        let astroEnd = try XCTUnwrap(today.astroDarkEnd)

        XCTAssertLessThan(sunset, astroStart)
        XCTAssertLessThan(astroStart, astroEnd)
        XCTAssertLessThan(astroEnd, sunrise)

        // Cross-check against the known ClearOutside reference for this date/location.
        let sunsetComponents = berlinCalendar.dateComponents([.hour, .minute], from: sunset)
        XCTAssertEqual(sunsetComponents.hour, 21)
    }

    func testMoonIlluminationIsPopulated() throws {
        let cache = try merge()
        let illumination = try XCTUnwrap(cache.days[0].moonIlluminationPercent)
        XCTAssertEqual(illumination, 94, accuracy: 5)
        XCTAssertNotNil(cache.days[0].moonPhaseName)
    }

    func testSeeingAndTransparencyArePopulatedWithinAstroWindow() throws {
        let cache = try merge()
        let today = cache.days[0]

        // Astro data starts becoming available a few hours into the fetched range (7Timer's
        // first timepoint is +3h from init) - pick an hour comfortably inside that window.
        let eveningHour = today.hours.first { hour in
            berlinCalendar.component(.hour, from: hour.date) == 20
        }
        let hour = try XCTUnwrap(eveningHour)
        XCTAssertNotNil(hour.seeingRaw)
        XCTAssertNotNil(hour.transparencyRaw)
    }

    func testSeeingAndTransparencyAreNilBeyondThreeDayAstroWindow() throws {
        let cache = try merge(days: 6)
        let lastDay = try XCTUnwrap(cache.days.last)

        // 7Timer's astro product only covers ~3 days; day 6 is well past that.
        XCTAssertTrue(lastDay.hours.allSatisfy { $0.seeingRaw == nil && $0.transparencyRaw == nil })
        // Cloud-based rating should still work via the Open-Meteo fallback path.
        XCTAssertTrue(lastDay.hours.contains { $0.rating != .unknown })
    }

    func testRatingIsNeverUnknownWhenCloudDataExists() throws {
        let cache = try merge()
        for day in cache.days {
            for hour in day.hours where hour.totalCloudPercent != nil {
                XCTAssertNotEqual(hour.rating, .unknown)
            }
        }
    }
}
