import XCTest
@testable import ClearOutsideCore

final class WeekendQualityEvaluatorTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return cal
    }

    /// Builds a single day with `nightGoodFraction` of its (fake) night hours rated "good".
    private func makeDay(weekday: Int, goodFraction: Double) -> DayForecast {
        // Find the next date matching `weekday` (1 = Sunday ... 7 = Saturday) so astroDark math stays simple.
        let cal = calendar
        let today = cal.startOfDay(for: Date())
        var date = today
        for _ in 0..<8 {
            if cal.component(.weekday, from: date) == weekday { break }
            date = cal.date(byAdding: .day, value: 1, to: date)!
        }

        let astroStart = cal.date(bySettingHour: 22, minute: 0, second: 0, of: date)!
        let nextDay = cal.date(byAdding: .day, value: 1, to: date)!
        let astroEnd = cal.date(bySettingHour: 4, minute: 0, second: 0, of: nextDay)!

        let totalHours = 6
        let goodCount = Int(Double(totalHours) * goodFraction)
        var hours: [HourForecast] = []
        for i in 0..<totalHours {
            let hourDate = cal.date(byAdding: .hour, value: i, to: astroStart)!
            hours.append(HourForecast(
                date: hourDate,
                hourLabel: cal.component(.hour, from: hourDate),
                rating: i < goodCount ? .good : .bad
            ))
        }

        return DayForecast(
            date: date,
            weekdayName: "Test",
            hours: hours,
            astroDarkStart: astroStart,
            astroDarkEnd: astroEnd
        )
    }

    func testWeekendDaysFiltersToFridaySaturdaySunday() {
        let days = (1...7).map { makeDay(weekday: $0, goodFraction: 0) }
        let cache = ForecastCache(fetchedAt: Date(), latitude: 48.0, longitude: 7.85, days: days)

        let weekend = WeekendQualityEvaluator.weekendDays(in: cache, calendar: calendar)
        let weekdays = Set(weekend.map { calendar.component(.weekday, from: $0.date) })

        XCTAssertEqual(weekdays, [1, 6, 7])
    }

    func testIsWeekendGoodFalseWhenAllNightsBad() {
        let days = (1...7).map { makeDay(weekday: $0, goodFraction: 0.1) }
        let cache = ForecastCache(fetchedAt: Date(), latitude: 48.0, longitude: 7.85, days: days)

        XCTAssertFalse(WeekendQualityEvaluator.isWeekendGood(in: cache, calendar: calendar))
    }

    func testIsWeekendGoodTrueWhenOneWeekendNightIsGood() {
        var days = (1...7).map { makeDay(weekday: $0, goodFraction: 0.1) }
        let saturdayIndex = days.firstIndex { calendar.component(.weekday, from: $0.date) == 7 }!
        days[saturdayIndex] = makeDay(weekday: 7, goodFraction: 0.9)
        let cache = ForecastCache(fetchedAt: Date(), latitude: 48.0, longitude: 7.85, days: days)

        XCTAssertTrue(WeekendQualityEvaluator.isWeekendGood(in: cache, calendar: calendar))
    }

    func testGoodWeekdayNightDoesNotCountAsWeekend() {
        // A great Tuesday night should not flip the weekend verdict.
        var days = (1...7).map { makeDay(weekday: $0, goodFraction: 0.1) }
        let tuesdayIndex = days.firstIndex { calendar.component(.weekday, from: $0.date) == 3 }!
        days[tuesdayIndex] = makeDay(weekday: 3, goodFraction: 1.0)
        let cache = ForecastCache(fetchedAt: Date(), latitude: 48.0, longitude: 7.85, days: days)

        XCTAssertFalse(WeekendQualityEvaluator.isWeekendGood(in: cache, calendar: calendar))
    }
}
