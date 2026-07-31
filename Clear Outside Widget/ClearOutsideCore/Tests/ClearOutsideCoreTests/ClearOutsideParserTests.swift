import XCTest
@testable import ClearOutsideCore

final class ClearOutsideParserTests: XCTestCase {
    private func loadFixtureHTML() throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "sample_forecast", withExtension: "html"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testParsesSevenDaysWithTodayFullyResolved() throws {
        let html = try loadFixtureHTML()
        let cache = try ClearOutsideParser.parse(html: html)

        XCTAssertEqual(cache.days.count, 7)
        XCTAssertEqual(cache.latitude, 48.00)
        XCTAssertEqual(cache.longitude, 7.85)

        let today = cache.days[0]
        XCTAssertEqual(today.hours.count, 24)
        XCTAssertEqual(today.weekdayName, "Friday")
    }

    func testHourValuesAreInPlausibleRanges() throws {
        let html = try loadFixtureHTML()
        let cache = try ClearOutsideParser.parse(html: html)

        for day in cache.days {
            for hour in day.hours {
                if let cloud = hour.totalCloudPercent {
                    XCTAssertTrue((0...100).contains(cloud), "cloud % out of range: \(cloud)")
                }
                XCTAssertNotEqual(hour.rating, .unknown)
            }
        }
    }

    func testHourLabelsWrapAcrossMidnightWithIncreasingDates() throws {
        let html = try loadFixtureHTML()
        let cache = try ClearOutsideParser.parse(html: html)
        let today = cache.days[0]

        XCTAssertEqual(today.hours.first?.hourLabel, 17)
        XCTAssertEqual(today.hours.last?.hourLabel, 16)

        for (previous, current) in zip(today.hours, today.hours.dropFirst()) {
            XCTAssertLessThan(previous.date, current.date)
        }
    }

    func testMoonInfoIsPopulated() throws {
        let html = try loadFixtureHTML()
        let cache = try ClearOutsideParser.parse(html: html)
        let today = cache.days[0]

        XCTAssertEqual(today.moonPhaseName, "Waning Gibbous")
        XCTAssertEqual(today.moonIlluminationPercent, 94)
    }

    func testAstroDarkWindowIsWithinSunsetSunriseBounds() throws {
        let html = try loadFixtureHTML()
        let cache = try ClearOutsideParser.parse(html: html)
        let today = cache.days[0]

        let sunset = try XCTUnwrap(today.sunset)
        let sunrise = try XCTUnwrap(today.sunrise)
        let astroStart = try XCTUnwrap(today.astroDarkStart)
        let astroEnd = try XCTUnwrap(today.astroDarkEnd)

        XCTAssertGreaterThan(astroStart, sunset)
        XCTAssertLessThan(astroEnd, sunrise)
        XCTAssertLessThan(astroStart, astroEnd)
    }

    func testGoodNightFractionIsComputable() throws {
        let html = try loadFixtureHTML()
        let cache = try ClearOutsideParser.parse(html: html)
        for day in cache.days {
            XCTAssertTrue((0...1).contains(day.goodNightFraction))
        }
    }

    func testLastDayIsPartial() throws {
        let html = try loadFixtureHTML()
        let cache = try ClearOutsideParser.parse(html: html)
        XCTAssertEqual(cache.days.last?.hours.count, 21)
    }

    func testDarknessWindowsAreNestedAroundAstroDark() throws {
        let html = try loadFixtureHTML()
        let cache = try ClearOutsideParser.parse(html: html)
        let today = cache.days[0]

        let sunset = try XCTUnwrap(today.sunset)
        let sunrise = try XCTUnwrap(today.sunrise)
        let civilStart = try XCTUnwrap(today.civilDarkStart)
        let civilEnd = try XCTUnwrap(today.civilDarkEnd)
        let nauticalStart = try XCTUnwrap(today.nauticalDarkStart)
        let nauticalEnd = try XCTUnwrap(today.nauticalDarkEnd)
        let astroStart = try XCTUnwrap(today.astroDarkStart)
        let astroEnd = try XCTUnwrap(today.astroDarkEnd)

        // sunset < civil < nautical < astro < astroEnd < nauticalEnd < civilEnd < sunrise(+1d)
        XCTAssertLessThan(sunset, civilStart)
        XCTAssertLessThan(civilStart, nauticalStart)
        XCTAssertLessThan(nauticalStart, astroStart)
        XCTAssertLessThan(astroStart, astroEnd)
        XCTAssertLessThan(astroEnd, nauticalEnd)
        XCTAssertLessThan(nauticalEnd, civilEnd)
        XCTAssertLessThan(civilEnd, sunrise)
    }

    func testMoonriseMoonsetAreParsedWithFullDate() throws {
        let html = try loadFixtureHTML()
        let cache = try ClearOutsideParser.parse(html: html)
        let today = cache.days[0]

        let moonrise = try XCTUnwrap(today.moonrise)
        let moonset = try XCTUnwrap(today.moonset)

        // Fixture: "Rise: 21:58 31/07/2026", "Set: 09:01 01/08/2026" - moonset is the next day.
        XCTAssertLessThan(moonrise, moonset)
        XCTAssertTrue(today.isMoonUp(at: moonrise.addingTimeInterval(60)))
        XCTAssertFalse(today.isMoonUp(at: moonrise.addingTimeInterval(-60)))
    }

    func testMoonTransitIsParsedAndWithinRiseSetWindow() throws {
        let html = try loadFixtureHTML()
        let cache = try ClearOutsideParser.parse(html: html)
        let today = cache.days[0]

        let moonrise = try XCTUnwrap(today.moonrise)
        let moonset = try XCTUnwrap(today.moonset)
        let moonTransit = try XCTUnwrap(today.moonTransit)

        // Fixture: "Time: 03:23 01/08/2026" falls between "Rise: 21:58 31/07/2026" and "Set: 09:01 01/08/2026".
        XCTAssertGreaterThan(moonTransit, moonrise)
        XCTAssertLessThan(moonTransit, moonset)
    }

    func testDarknessFractionRampsFromDayToNightAndBack() throws {
        let html = try loadFixtureHTML()
        let cache = try ClearOutsideParser.parse(html: html)
        let today = cache.days[0]

        let sunset = try XCTUnwrap(today.sunset)
        let astroStart = try XCTUnwrap(today.astroDarkStart)
        let astroEnd = try XCTUnwrap(today.astroDarkEnd)
        let sunrise = try XCTUnwrap(today.sunrise)

        XCTAssertEqual(today.darknessFraction(at: sunset.addingTimeInterval(-3600)), 0)
        XCTAssertEqual(today.darknessFraction(at: astroStart.addingTimeInterval(60)), 1.0, accuracy: 0.001)
        XCTAssertEqual(today.darknessFraction(at: astroEnd.addingTimeInterval(-60)), 1.0, accuracy: 0.001)
        XCTAssertEqual(today.darknessFraction(at: sunrise.addingTimeInterval(3600)), 0)

        // Strictly increasing on the way into the night, strictly decreasing on the way out.
        let intoNight = today.darknessFraction(at: sunset.addingTimeInterval(600))
        let deeperIntoNight = today.darknessFraction(at: sunset.addingTimeInterval(1800))
        XCTAssertLessThan(intoNight, deeperIntoNight)
    }

    func testSunZoneMatchesDarknessWindowBoundaries() throws {
        let html = try loadFixtureHTML()
        let cache = try ClearOutsideParser.parse(html: html)
        let today = cache.days[0]

        let sunset = try XCTUnwrap(today.sunset)
        let civilStart = try XCTUnwrap(today.civilDarkStart)
        let nauticalStart = try XCTUnwrap(today.nauticalDarkStart)
        let astroStart = try XCTUnwrap(today.astroDarkStart)
        let astroEnd = try XCTUnwrap(today.astroDarkEnd)
        let nauticalEnd = try XCTUnwrap(today.nauticalDarkEnd)
        let civilEnd = try XCTUnwrap(today.civilDarkEnd)
        let sunrise = try XCTUnwrap(today.sunrise)

        XCTAssertEqual(today.sunZone(at: sunset.addingTimeInterval(-3600)), .day)
        XCTAssertEqual(today.sunZone(at: sunset.addingTimeInterval(60)), .civilTwilight)
        XCTAssertEqual(today.sunZone(at: civilStart.addingTimeInterval(60)), .civilDark)
        XCTAssertEqual(today.sunZone(at: nauticalStart.addingTimeInterval(60)), .nauticalDark)
        XCTAssertEqual(today.sunZone(at: astroStart.addingTimeInterval(60)), .astroDark)
        XCTAssertEqual(today.sunZone(at: astroEnd.addingTimeInterval(-60)), .astroDark)
        XCTAssertEqual(today.sunZone(at: nauticalEnd.addingTimeInterval(-60)), .nauticalDark)
        XCTAssertEqual(today.sunZone(at: civilEnd.addingTimeInterval(-60)), .civilDark)
        XCTAssertEqual(today.sunZone(at: sunrise.addingTimeInterval(3600)), .day)
    }
}
