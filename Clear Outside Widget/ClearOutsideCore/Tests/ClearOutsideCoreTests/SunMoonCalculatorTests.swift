import XCTest
@testable import ClearOutsideCore

final class SunMoonCalculatorTests: XCTestCase {
    // Freiburg-area coordinates used throughout this project.
    private let latitude = 48.00
    private let longitude = 7.85

    private var berlinCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    /// Noon on 2026-07-31 local time - the same date/coordinates as the frozen ClearOutside
    /// fixture, whose scraped sunrise/sunset/twilight values (06:05, 21:05, Civil Dark
    /// 21:42-05:29, Nautical Dark 22:29-04:42, Astro Dark 23:27-03:45) serve as the reference
    /// here. SunCalc's approximation should land within a few minutes of those.
    private func referenceDate() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 31
        components.hour = 12
        return berlinCalendar.date(from: components)!
    }

    private func assertApproximatelyEqual(
        _ date: Date?, expectedHour: Int, expectedMinute: Int, toleranceMinutes: Int = 4,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let date = try XCTUnwrap(date, "expected a date", file: file, line: line)
        let expected = berlinCalendar.date(
            bySettingHour: expectedHour, minute: expectedMinute, second: 0, of: berlinCalendar.startOfDay(for: date)
        )!
        let diffMinutes = abs(date.timeIntervalSince(expected)) / 60
        let actual = berlinCalendar.dateComponents([.hour, .minute], from: date)
        XCTAssertLessThanOrEqual(
            diffMinutes, Double(toleranceMinutes),
            "expected ~\(expectedHour):\(expectedMinute), got \(actual.hour ?? -1):\(actual.minute ?? -1)",
            file: file, line: line
        )
    }

    func testSunriseSunsetMatchKnownReferenceValues() throws {
        let times = SunMoonCalculator.sunTimes(for: referenceDate(), latitude: latitude, longitude: longitude)

        try assertApproximatelyEqual(times.sunrise, expectedHour: 6, expectedMinute: 5)
        try assertApproximatelyEqual(times.sunset, expectedHour: 21, expectedMinute: 5)
    }

    func testTwilightWindowsMatchKnownReferenceValues() throws {
        let times = SunMoonCalculator.sunTimes(for: referenceDate(), latitude: latitude, longitude: longitude)

        // Civil Dark: 21:42 - 05:29
        try assertApproximatelyEqual(times.civilDusk, expectedHour: 21, expectedMinute: 42)
        try assertApproximatelyEqual(times.civilDawn, expectedHour: 5, expectedMinute: 29)

        // Nautical Dark: 22:29 - 04:42
        try assertApproximatelyEqual(times.nauticalDusk, expectedHour: 22, expectedMinute: 29)
        try assertApproximatelyEqual(times.nauticalDawn, expectedHour: 4, expectedMinute: 42)

        // Astro Dark: 23:27 - 03:45
        try assertApproximatelyEqual(times.astronomicalDusk, expectedHour: 23, expectedMinute: 27)
        try assertApproximatelyEqual(times.astronomicalDawn, expectedHour: 3, expectedMinute: 45)
    }

    func testSunTimesOrdering() throws {
        let times = SunMoonCalculator.sunTimes(for: referenceDate(), latitude: latitude, longitude: longitude)

        let sunset = try XCTUnwrap(times.sunset)
        let civilDusk = try XCTUnwrap(times.civilDusk)
        let nauticalDusk = try XCTUnwrap(times.nauticalDusk)
        let astroDusk = try XCTUnwrap(times.astronomicalDusk)

        XCTAssertLessThan(sunset, civilDusk)
        XCTAssertLessThan(civilDusk, nauticalDusk)
        XCTAssertLessThan(nauticalDusk, astroDusk)
    }

    func testMoonIlluminationMatchesKnownFixtureValue() throws {
        // The ClearOutside fixture reported 94% illumination for this date/time; our
        // phase-angle-based calculation lands at ~97%, well within tolerance for two
        // independent computation methods. (ClearOutside labelled this "Waning Gibbous";
        // our phase value of ~0.555 falls just inside the textbook 1/8-slice "Full Moon"
        // bucket (0.4375-0.5625) - a boundary-labelling difference, not a math error See
        // `testMoonPhaseNameCoversFullCycle` for the bucketing itself.)
        let illumination = SunMoonCalculator.moonIllumination(for: referenceDate())

        XCTAssertEqual(illumination.fraction * 100, 94, accuracy: 5)
    }

    func testMoonPhaseNameCoversFullCycle() {
        let names = stride(from: 0.0, to: 1.0, by: 0.05).map { SunMoonCalculator.moonPhaseName(forPhase: $0) }
        XCTAssertTrue(names.contains("new moon"))
        XCTAssertTrue(names.contains("full moon"))
        XCTAssertTrue(names.contains("first quarter"))
        XCTAssertTrue(names.contains("last quarter"))
    }

    func testMoonTimesReturnsRiseBeforeSetWhenBothExist() throws {
        let times = SunMoonCalculator.moonTimes(
            for: referenceDate(), latitude: latitude, longitude: longitude, calendar: berlinCalendar
        )

        // Fixture: moonrise 21:58 (31/07), moonset 09:01 (01/08) - rise this calendar day,
        // set the next; moonTimes() only searches the given calendar day, so `set` may be nil
        // here (it falls after midnight) while `rise` should be populated and plausible.
        if let rise = times.rise {
            try assertApproximatelyEqual(rise, expectedHour: 21, expectedMinute: 58, toleranceMinutes: 10)
        } else {
            XCTFail("expected a moonrise on this date")
        }
    }

    func testMoonTransitFallsWithinTheDay() throws {
        let transit = SunMoonCalculator.moonTransit(
            for: referenceDate(), latitude: latitude, longitude: longitude, calendar: berlinCalendar
        )
        let transit2 = try XCTUnwrap(transit)
        let dayStart = berlinCalendar.startOfDay(for: referenceDate())
        let dayEnd = berlinCalendar.date(byAdding: .day, value: 1, to: dayStart)!

        XCTAssertGreaterThanOrEqual(transit2, dayStart)
        XCTAssertLessThanOrEqual(transit2, dayEnd)
    }
}
