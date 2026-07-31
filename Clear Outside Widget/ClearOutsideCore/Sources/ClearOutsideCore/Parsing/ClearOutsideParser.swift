import Foundation
import SwiftSoup

public enum ParserError: Error, Equatable {
    case noDaySections
    case malformedDay(String)
}

public enum ClearOutsideParser {
    /// Parses a ClearOutside forecast page. `referenceDate` anchors day 0 to "today" -
    /// the page itself does not include the year/month, only weekday + day-of-month.
    public static func parse(
        html: String,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) throws -> ForecastCache {
        let doc = try SwiftSoup.parse(html)
        let dayElements = try doc.select("div.fc_day").array()
        guard !dayElements.isEmpty else { throw ParserError.noDaySections }

        let days = try dayElements.enumerated().map { index, element in
            try parseDay(element, dayIndex: index, referenceDate: referenceDate, calendar: calendar)
        }

        return ForecastCache(fetchedAt: Date(), latitude: 48.00, longitude: 7.85, days: days)
    }

    private static func parseDay(
        _ dayEl: Element,
        dayIndex: Int,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> DayForecast {
        let anchor = calendar.date(byAdding: .day, value: dayIndex, to: referenceDate) ?? referenceDate
        let baseDate = calendar.startOfDay(for: anchor)

        guard let ratingsList = try dayEl.select("div.fc_hours.fc_hour_ratings > ul").first() else {
            throw ParserError.malformedDay("missing fc_hour_ratings row")
        }
        let ratingItems = try ratingsList.select("li").array()
        guard !ratingItems.isEmpty else { throw ParserError.malformedDay("empty fc_hour_ratings row") }

        var hourLabels: [Int] = []
        var ratings: [HourRating] = []
        for item in ratingItems {
            let classAttr = try item.attr("class")
            ratings.append(rating(fromClass: classAttr))
            let text = try item.text()
            guard let leadingToken = text.split(separator: " ").first, let hour = Int(leadingToken) else {
                throw ParserError.malformedDay("unparsable hour label: \(text)")
            }
            hourLabels.append(hour)
        }

        var hourDates: [Date] = []
        var runningDate = baseDate
        var previousHour: Int?
        for hour in hourLabels {
            if let previous = previousHour, hour < previous {
                runningDate = calendar.date(byAdding: .day, value: 1, to: runningDate) ?? runningDate
            }
            hourDates.append(calendar.date(bySettingHour: hour, minute: 0, second: 0, of: runningDate) ?? runningDate)
            previousHour = hour
        }

        let totalCloud = try detailValues(in: dayEl, label: "Total Clouds (% Sky Obscured)")
        let seeing = try detailValues(in: dayEl, label: "7Timer Seeing")
        let transparency = try detailValues(in: dayEl, label: "7Timer Transparency")

        var hours: [HourForecast] = []
        hours.reserveCapacity(hourLabels.count)
        for i in 0..<hourLabels.count {
            hours.append(HourForecast(
                date: hourDates[i],
                hourLabel: hourLabels[i],
                rating: ratings[i],
                totalCloudPercent: i < totalCloud.count ? totalCloud[i] : nil,
                seeingRaw: i < seeing.count ? seeing[i] : nil,
                transparencyRaw: i < transparency.count ? transparency[i] : nil
            ))
        }

        let moonEl = try dayEl.select("div.fc_moon").first()
        let moonPhaseName = try moonEl?.select("span.fc_moon_phase").first()?.text()
        let moonPercentText = try moonEl?.select("span.fc_moon_percentage").first()?.text()
        let moonIllumination = moonPercentText.flatMap { Int($0.replacingOccurrences(of: "%", with: "")) }
        let moonPopoverContent = try moonEl?.attr("data-content")
        let moonrise = dateFromPopover(moonPopoverContent, label: "Rise", calendar: calendar)
        let moonset = dateFromPopover(moonPopoverContent, label: "Set", calendar: calendar)
        // "Time:" in the moon meridian popover is the transit ("zenith") moment.
        let moonTransit = dateFromPopover(moonPopoverContent, label: "Time", calendar: calendar)

        let nextDay = calendar.date(byAdding: .day, value: 1, to: baseDate) ?? baseDate
        let popoverContent = try dayEl.select("div.fc_daylight").first()?.attr("data-content")
        // Sunrise belongs to the following morning - this day block runs 17:00 -> 16:00 next day.
        let sunrise = timeFromPopover(popoverContent, label: "Sunrise", baseDate: nextDay, calendar: calendar)
        let sunset = timeFromPopover(popoverContent, label: "Sunset", baseDate: baseDate, calendar: calendar)
        let (civilStart, civilEnd) = darkWindow(popoverContent, label: "Civil Dark", baseDate: baseDate, calendar: calendar)
        let (nauticalStart, nauticalEnd) = darkWindow(popoverContent, label: "Nautical Dark", baseDate: baseDate, calendar: calendar)
        let (astroStart, astroEnd) = darkWindow(popoverContent, label: "Astro Dark", baseDate: baseDate, calendar: calendar)

        let weekdayName = try dayEl.select("div.fc_day_date span").first()?.text() ?? ""

        return DayForecast(
            date: baseDate,
            weekdayName: weekdayName,
            hours: hours,
            moonPhaseName: moonPhaseName,
            moonIlluminationPercent: moonIllumination,
            moonrise: moonrise,
            moonset: moonset,
            moonTransit: moonTransit,
            sunrise: sunrise,
            sunset: sunset,
            civilDarkStart: civilStart,
            civilDarkEnd: civilEnd,
            nauticalDarkStart: nauticalStart,
            nauticalDarkEnd: nauticalEnd,
            astroDarkStart: astroStart,
            astroDarkEnd: astroEnd
        )
    }

    private static func rating(fromClass classAttr: String) -> HourRating {
        if classAttr.contains("fc_good") { return .good }
        if classAttr.contains("fc_ok") { return .ok }
        if classAttr.contains("fc_bad") { return .bad }
        return .unknown
    }

    /// Looks up a `.fc_detail_row` by its visible label rather than positional index,
    /// so re-ordering the site's metric rows doesn't silently misalign values.
    private static func detailValues(in dayEl: Element, label: String) throws -> [Int] {
        let rows = try dayEl.select("div.fc_detail_row")
        for row in rows {
            let rowLabel = try row.select("span.fc_detail_label span").first()?.text()
            guard rowLabel == label else { continue }
            let items = try row.select("div.fc_hours ul li").array()
            return try items.map { Int(try $0.text()) ?? 0 }
        }
        return []
    }

    private static func timeFromPopover(
        _ content: String?,
        label: String,
        baseDate: Date,
        calendar: Calendar
    ) -> Date? {
        guard let content, let labelRange = content.range(of: "\(label):</strong> ") else { return nil }
        let tail = content[labelRange.upperBound...]
        guard let match = tail.range(of: #"\d{2}:\d{2}"#, options: .regularExpression) else { return nil }
        return time(String(tail[match]), on: baseDate, calendar: calendar)
    }

    /// Darkness windows ("Civil Dark", "Nautical Dark", "Astro Dark") are shown as e.g.
    /// "23:27 - 03:45" - start on `baseDate`, end the following morning.
    private static func darkWindow(
        _ content: String?,
        label: String,
        baseDate: Date,
        calendar: Calendar
    ) -> (Date?, Date?) {
        guard let content, let labelRange = content.range(of: "\(label):</strong> ") else { return (nil, nil) }
        let tail = content[labelRange.upperBound...]
        guard let match = tail.range(of: #"\d{2}:\d{2} - \d{2}:\d{2}"#, options: .regularExpression) else {
            return (nil, nil)
        }
        let parts = String(tail[match]).components(separatedBy: " - ")
        guard parts.count == 2 else { return (nil, nil) }
        let nextDay = calendar.date(byAdding: .day, value: 1, to: baseDate) ?? baseDate
        return (time(parts[0], on: baseDate, calendar: calendar), time(parts[1], on: nextDay, calendar: calendar))
    }

    /// The moon popover embeds full dates, e.g. "Rise:</strong> 21:58 31/07/2026", so unlike the
    /// sun/darkness windows we don't need a same-day/next-day heuristic here.
    private static func dateFromPopover(_ content: String?, label: String, calendar: Calendar) -> Date? {
        guard let content, let labelRange = content.range(of: "\(label):</strong> ") else { return nil }
        let tail = content[labelRange.upperBound...]
        guard let match = tail.range(of: #"\d{2}:\d{2} \d{2}/\d{2}/\d{4}"#, options: .regularExpression) else {
            return nil
        }
        let components = String(tail[match]).split(separator: " ")
        guard components.count == 2 else { return nil }
        let timeParts = components[0].split(separator: ":")
        let dateParts = components[1].split(separator: "/")
        guard timeParts.count == 2, dateParts.count == 3,
              let hour = Int(timeParts[0]), let minute = Int(timeParts[1]),
              let day = Int(dateParts[0]), let month = Int(dateParts[1]), let year = Int(dateParts[2])
        else { return nil }

        var dateComponents = DateComponents()
        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = day
        dateComponents.hour = hour
        dateComponents.minute = minute
        return calendar.date(from: dateComponents)
    }

    private static func time(_ hhmm: String, on day: Date, calendar: Calendar) -> Date? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }
}
