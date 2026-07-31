//
//  NightTimelineView.swift
//  ClearOutsideCore
//
//  Shared between the app and the widget extension.
//

import SwiftUI

/// How much chrome `NightTimelineView` shows around the three bars.
public enum TimelineStyle: Sendable {
    /// Full-size single-day view: hour numbers, sun/rise-set ticks, sun+moon caption.
    case detailed
    /// Small multi-row view (e.g. a 6-day list): just the three color bars, no labels.
    case compact
}

/// Hourly sunset -> sunrise timeline in ClearOutside's own red/orange/green scheme
/// (red = daylight or clouds, orange = clear twilight, green = clear night), with a
/// current-time marker, a sun-position tick row above, and a moon-up/down bar below
/// (with a marker at the moon's meridian transit).
public struct NightTimelineView: View {
    let day: DayForecast
    var style: TimelineStyle

    public init(day: DayForecast, style: TimelineStyle = .detailed) {
        self.day = day
        self.style = style
    }

    private var blockWidth: CGFloat { style == .detailed ? 26 : 16 }
    private var blockHeight: CGFloat { style == .detailed ? 44 : 22 }
    private var sunPositionBarHeight: CGFloat { style == .detailed ? 14 : 8 }
    private var moonBarHeight: CGFloat { style == .detailed ? 14 : 8 }
    private var tickRowHeight: CGFloat { 14 }
    private var barSpacing: CGFloat { style == .detailed ? 2 : 1 }
    private var showsHourLabels: Bool { style == .detailed }
    private var showsTickRow: Bool { style == .detailed }
    private var showsCaption: Bool { style == .detailed }

    private var timelineHours: [HourForecast] {
        guard let sunset = day.sunset, let sunrise = day.sunrise else { return day.hours }
        let start = sunset.addingTimeInterval(-2 * 3600)
        let end = sunrise.addingTimeInterval(2 * 3600)
        return day.hours.filter { $0.date >= start && $0.date <= end }
    }

    private var totalWidth: CGFloat {
        CGFloat(timelineHours.count) * blockWidth
    }

    private var combinedBarsHeight: CGFloat {
        blockHeight + barSpacing + sunPositionBarHeight + barSpacing + moonBarHeight
    }

    private var moonBarYOffset: CGFloat {
        blockHeight + barSpacing + sunPositionBarHeight + barSpacing
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsTickRow {
                sunTickRow
                    .frame(width: totalWidth, height: tickRowHeight)
            }

            if style == .detailed {
                // Fixed-width, horizontally scrollable: hour labels/dividers/markers need
                // stable per-hour pixel widths to stay legible and correctly positioned.
                ZStack(alignment: .topLeading) {
                    VStack(spacing: barSpacing) {
                        cloudDarknessBar
                        sunPositionBar
                        moonBar
                    }
                    moonTransitMarker
                    currentTimeLine
                }
                .frame(width: totalWidth, height: combinedBarsHeight)
            } else {
                // Rating bar: genuinely hourly data, so equal-width blocks (with hour labels
                // and dividers) that flex to fill the row still make sense. Sun/moon bars are
                // continuous astronomical functions, so they're rendered as smooth,
                // time-proportional segments (no hourly stepping, no dividers) via GeometryReader.
                VStack(spacing: barSpacing) {
                    compactRatingBar
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            ForEach(Array(sunZoneSegments.enumerated()), id: \.offset) { _, segment in
                                Rectangle()
                                    .fill(sunZoneColor(for: segment.zone))
                                    .frame(width: fractionalWidth(from: segment.start, to: segment.end, in: geo.size.width))
                            }
                        }
                    }
                    .frame(height: sunPositionBarHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            ForEach(Array(moonSegments.enumerated()), id: \.offset) { _, segment in
                                Rectangle()
                                    .fill(segment.isUp ? Color.gray : Color.blue)
                                    .frame(width: fractionalWidth(from: segment.start, to: segment.end, in: geo.size.width))
                            }
                        }
                    }
                    .frame(height: moonBarHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .frame(maxWidth: .infinity)
            }

            if showsCaption {
                sunCaption
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Equal-width hourly blocks (genuinely hourly-resolution data), with hour labels and
    /// thin dividers, that flex to fill the row instead of using a fixed pixel width.
    private var compactRatingBar: some View {
        HStack(spacing: 0) {
            ForEach(Array(timelineHours.enumerated()), id: \.element.date) { index, hour in
                Rectangle()
                    .fill(blockColor(for: hour))
                    .frame(maxWidth: .infinity)
                    .overlay {
                        Text(String(format: "%02d", hour.hourLabel))
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .overlay(alignment: .trailing) {
                        if index < timelineHours.count - 1 {
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: 1)
                        }
                    }
            }
        }
        .frame(height: blockHeight)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    /// Width of a `[start, end)` segment as a fraction of the full displayed time range,
    /// scaled to `totalWidth` - used to render continuous (non-hour-stepped) bars.
    private func fractionalWidth(from start: Date, to end: Date, in totalWidth: CGFloat) -> CGFloat {
        guard let rangeStart = timelineHours.first?.date, let lastHourStart = timelineHours.last?.date else {
            return 0
        }
        let rangeEnd = lastHourStart.addingTimeInterval(3600)
        let totalDuration = rangeEnd.timeIntervalSince(rangeStart)
        guard totalDuration > 0 else { return 0 }
        return totalWidth * CGFloat(end.timeIntervalSince(start) / totalDuration)
    }

    /// Continuous moon up/down segments (mirrors `sunZoneSegments`) - a moonrise/moonset
    /// pair produces at most 3 segments across the displayed range, not one per hour.
    private var moonSegments: [(start: Date, end: Date, isUp: Bool)] {
        guard let rangeStart = timelineHours.first?.date, let lastHourStart = timelineHours.last?.date else {
            return []
        }
        let rangeEnd = lastHourStart.addingTimeInterval(3600)

        let boundaries = [day.moonrise, day.moonset]
            .compactMap { $0 }
            .filter { $0 > rangeStart && $0 < rangeEnd }
            .sorted()

        let points = [rangeStart] + boundaries + [rangeEnd]
        var segments: [(start: Date, end: Date, isUp: Bool)] = []
        for i in 0..<(points.count - 1) {
            let start = points[i]
            let end = points[i + 1]
            guard end > start else { continue }
            let midpoint = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
            segments.append((start, end, day.isMoonUp(at: midpoint)))
        }
        return segments
    }

    private var cloudDarknessBar: some View {
        HStack(spacing: 0) {
            ForEach(Array(timelineHours.enumerated()), id: \.element.date) { index, hour in
                Rectangle()
                    .fill(blockColor(for: hour))
                    .frame(width: blockWidth, height: blockHeight)
                    .overlay {
                        if showsHourLabels {
                            Text(String(format: "%02d", hour.hourLabel))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .overlay(alignment: .trailing) {
                        // Thin divider between hours - skip after the last block.
                        if index < timelineHours.count - 1 {
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: 1)
                        }
                    }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    /// Sun altitude band: day (yellow) -> civil twilight (orange) -> civil/nautical/astro dark
    /// (light blue -> dark blue -> black), mirrored on the way back to sunrise.
    ///
    /// Rendered as time-proportional segments rather than one flat color per hour block -
    /// several twilight phases (37-58 min) are shorter than an hour and would otherwise
    /// vanish entirely if a single per-hour sample happened to land just outside them.
    private var sunPositionBar: some View {
        HStack(spacing: 0) {
            ForEach(Array(sunZoneSegments.enumerated()), id: \.offset) { _, segment in
                Rectangle()
                    .fill(sunZoneColor(for: segment.zone))
                    .frame(width: segment.end.timeIntervalSince(segment.start) / 3600 * blockWidth, height: sunPositionBarHeight)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var sunZoneSegments: [(start: Date, end: Date, zone: DayForecast.SunZone)] {
        guard let rangeStart = timelineHours.first?.date, let lastHourStart = timelineHours.last?.date else {
            return []
        }
        let rangeEnd = lastHourStart.addingTimeInterval(3600)

        let boundaries = [
            day.sunset, day.civilDarkStart, day.nauticalDarkStart, day.astroDarkStart,
            day.astroDarkEnd, day.nauticalDarkEnd, day.civilDarkEnd, day.sunrise
        ]
        .compactMap { $0 }
        .filter { $0 > rangeStart && $0 < rangeEnd }
        .sorted()

        let points = [rangeStart] + boundaries + [rangeEnd]
        var segments: [(start: Date, end: Date, zone: DayForecast.SunZone)] = []
        for i in 0..<(points.count - 1) {
            let start = points[i]
            let end = points[i + 1]
            guard end > start else { continue }
            let midpoint = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
            segments.append((start, end, day.sunZone(at: midpoint)))
        }
        return segments
    }

    private var moonBar: some View {
        HStack(spacing: 0) {
            ForEach(timelineHours, id: \.date) { hour in
                Rectangle()
                    .fill(day.isMoonUp(at: hour.date) ? Color.gray : Color.blue)
                    .frame(width: blockWidth, height: moonBarHeight)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    @ViewBuilder
    private var sunTickRow: some View {
        // Each tick claims the full row width itself (rather than relying on the ZStack to
        // size to totalWidth) - otherwise a ZStack of two small icons sizes to its content
        // and gets centered by the outer .frame(), silently discarding the .offset() math.
        ZStack(alignment: .topLeading) {
            if let sunset = day.sunset, let x = xOffset(for: sunset) {
                sunTick(at: x, systemImage: "sunset.fill")
                    .frame(width: totalWidth, height: tickRowHeight, alignment: .topLeading)
            }
            if let sunrise = day.sunrise, let x = xOffset(for: sunrise) {
                sunTick(at: x, systemImage: "sunrise.fill")
                    .frame(width: totalWidth, height: tickRowHeight, alignment: .topLeading)
            }
        }
    }

    private func sunTick(at x: CGFloat, systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 10))
            .foregroundStyle(.orange)
            .offset(x: x - 7)
    }

    /// Vertical red line marking "now", spanning both the cloud/darkness bar and the moon bar.
    @ViewBuilder
    private var currentTimeLine: some View {
        if let x = xOffset(for: Date()), x >= 0, x <= totalWidth {
            Rectangle()
                .fill(Color.red)
                .frame(width: 1.5, height: combinedBarsHeight)
                .offset(x: x)
        }
    }

    /// Vertical red tick marking the moon's meridian transit ("zenith"), on the moon bar only.
    @ViewBuilder
    private var moonTransitMarker: some View {
        if let transit = day.moonTransit, let x = xOffset(for: transit), x >= 0, x <= totalWidth {
            Rectangle()
                .fill(Color.red)
                .frame(width: 1.5, height: moonBarHeight)
                .offset(x: x, y: moonBarYOffset)
        }
    }

    private var sunCaption: some View {
        HStack(spacing: 12) {
            if let sunset = day.sunset {
                Label(sunset.formatted(date: .omitted, time: .shortened), systemImage: "sunset.fill")
            }
            if let sunrise = day.sunrise {
                Label(sunrise.formatted(date: .omitted, time: .shortened), systemImage: "sunrise.fill")
            }
            if let illumination = day.moonIlluminationPercent {
                Label("\(illumination)%", systemImage: Self.moonPhaseSymbolName(for: day))
            }
        }
    }

    private static let moonPhaseSymbols: [String: String] = [
        "new moon": "moonphase.new.moon",
        "waxing crescent": "moonphase.waxing.crescent",
        "first quarter": "moonphase.first.quarter",
        "waxing gibbous": "moonphase.waxing.gibbous",
        "full moon": "moonphase.full.moon",
        "waning gibbous": "moonphase.waning.gibbous",
        "last quarter": "moonphase.last.quarter",
        "waning crescent": "moonphase.waning.crescent"
    ]

    /// SF Symbol name matching this day's moon phase - shared with other views (e.g. the
    /// week overview header) so the icon mapping only lives in one place.
    public static func moonPhaseSymbolName(for day: DayForecast) -> String {
        guard let name = day.moonPhaseName?.lowercased() else { return "moon" }
        return moonPhaseSymbols[name] ?? "moon"
    }

    private func xOffset(for date: Date) -> CGFloat? {
        guard let firstDate = timelineHours.first?.date else { return nil }
        let hoursFromStart = date.timeIntervalSince(firstDate) / 3600
        return CGFloat(hoursFromStart) * blockWidth
    }

    /// ClearOutside's own scheme: red = sun up or clouds, orange = clear twilight, green = clear night.
    private func blockColor(for hour: HourForecast) -> Color {
        switch hour.rating {
        case .good: return .green
        case .ok: return .orange
        case .bad, .unknown: return .red
        }
    }

    private func sunZoneColor(for zone: DayForecast.SunZone) -> Color {
        switch zone {
        case .day: return .yellow
        case .civilTwilight: return .orange
        case .civilDark: return Color(hue: 0.58, saturation: 0.55, brightness: 0.95)
        case .nauticalDark: return Color(hue: 0.62, saturation: 0.75, brightness: 0.45)
        case .astroDark: return .black
        }
    }
}
