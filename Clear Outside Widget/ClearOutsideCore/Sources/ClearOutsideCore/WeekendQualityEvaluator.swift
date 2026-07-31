import Foundation

/// Decides whether the upcoming Friday/Saturday/Sunday night is worth a "good weather" notification.
public enum WeekendQualityEvaluator {
    /// Fraction of a night's relevant hours that must be rated "good" for that night to count.
    public static let goodNightThreshold = 0.5

    /// True if any of the upcoming Friday/Saturday/Sunday nights in `cache` clears the quality bar.
    public static func isWeekendGood(in cache: ForecastCache, calendar: Calendar = .current) -> Bool {
        weekendDays(in: cache, calendar: calendar).contains { $0.goodNightFraction >= goodNightThreshold }
    }

    /// The subset of `cache.days` whose date falls on Friday, Saturday, or Sunday.
    public static func weekendDays(in cache: ForecastCache, calendar: Calendar = .current) -> [DayForecast] {
        cache.days.filter { day in
            let weekday = calendar.component(.weekday, from: day.date)
            // Calendar.component(.weekday): 1 = Sunday ... 6 = Friday, 7 = Saturday.
            return weekday == 1 || weekday == 6 || weekday == 7
        }
    }
}
