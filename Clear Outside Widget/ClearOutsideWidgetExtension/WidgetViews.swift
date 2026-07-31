import SwiftUI
import WidgetKit
import ClearOutsideCore

struct ClearOutsideWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ForecastEntry

    var body: some View {
        switch entry.state {
        case .placeholder:
            placeholderView
        case .loaded(let cache):
            content(for: cache)
        case .staleCache(let cache, let asOf):
            content(for: cache, staleAsOf: asOf)
        case .error(let message):
            errorView(message)
        }
    }

    @ViewBuilder
    private func content(for cache: ForecastCache, staleAsOf: Date? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Astro-Wetter").font(.headline)
                Spacer()
                if let staleAsOf {
                    Text(staleAsOf, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            DayStripView(days: Array(cache.days.prefix(6)))
            if family == .systemLarge, let today = cache.days.first {
                Divider()
                TodayHourlyDetailView(day: today)
            }
        }
    }

    private var placeholderView: some View {
        VStack(spacing: 4) {
            ProgressView()
            Text("Lade Vorhersage…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "cloud.slash")
                .font(.title2)
            Text("Vorhersage nicht verfügbar")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DayStripView: View {
    let days: [DayForecast]

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                DaySummaryCell(day: day)
            }
        }
    }
}

struct DaySummaryCell: View {
    let day: DayForecast

    var body: some View {
        VStack(spacing: 4) {
            Text(day.date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "de_DE"))))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Circle()
                .fill(QualityColor.color(forGoodFraction: day.goodNightFraction))
                .frame(width: 14, height: 14)
            if let cloud = day.averageNightCloudPercent {
                Text("\(Int(cloud))%")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct TodayHourlyDetailView: View {
    let day: DayForecast

    private var relevantHours: [HourForecast] {
        let night = day.nightHours
        return night.isEmpty ? Array(day.hours.prefix(8)) : night
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(relevantHours.prefix(8).enumerated()), id: \.offset) { _, hour in
                HourDetailColumn(hour: hour)
            }
        }
    }
}

struct HourDetailColumn: View {
    let hour: HourForecast

    var body: some View {
        VStack(spacing: 2) {
            Text(String(format: "%02d", hour.hourLabel))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: 2)
                .fill(QualityColor.color(for: hour.rating))
                .frame(width: 10, height: 18)
        }
        .frame(maxWidth: .infinity)
    }
}

enum QualityColor {
    static func color(for rating: HourRating) -> Color {
        switch rating {
        case .good: return .green
        case .ok: return .orange
        case .bad: return .red
        case .unknown: return .gray
        }
    }

    static func color(forGoodFraction fraction: Double) -> Color {
        switch fraction {
        case 0.6...: return .green
        case 0.3..<0.6: return .yellow
        default: return .red
        }
    }
}
