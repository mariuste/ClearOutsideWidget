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
        switch family {
        case .systemMedium:
            TodayMediumView(cache: cache, staleAsOf: staleAsOf)
        default:
            WeekLargeView(cache: cache, staleAsOf: staleAsOf)
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

/// Medium widget: today's night timeline (compact rating/sun/moon bars), matching the app.
struct TodayMediumView: View {
    let cache: ForecastCache
    var staleAsOf: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let today = cache.days.first {
                    Text(today.date.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "de_DE"))))
                        .font(.headline)
                }
                Spacer()
                if let staleAsOf {
                    Text(staleAsOf, style: .relative)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }

            if let today = cache.days.first {
                NightTimelineView(day: today, style: .compact, scale: 1.7)
                Spacer(minLength: 0)
                HStack {
                    if let sunset = today.sunset {
                        Label(sunset.formatted(date: .omitted, time: .shortened), systemImage: "sunset.fill")
                    }
                    if let sunrise = today.sunrise {
                        Label(sunrise.formatted(date: .omitted, time: .shortened), systemImage: "sunrise.fill")
                    }
                    Spacer()
                    if let illumination = today.moonIlluminationPercent {
                        Label("\(illumination)%", systemImage: NightTimelineView.moonPhaseSymbolName(for: today))
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
    }
}

/// Large widget: the 6-day week overview, same compact bars as the app's week list.
struct WeekLargeView: View {
    let cache: ForecastCache
    var staleAsOf: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Astro-Wetter").font(.headline)
                Spacer()
                if let staleAsOf {
                    Text(staleAsOf, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(Array(cache.days.prefix(6).enumerated()), id: \.element.date) { _, day in
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(day.date.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "de_DE"))))
                            .font(.system(size: 11, weight: .medium))
                        if let illumination = day.moonIlluminationPercent {
                            Label("\(illumination)%", systemImage: NightTimelineView.moonPhaseSymbolName(for: day))
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 46, alignment: .leading)

                    NightTimelineView(day: day, style: .compact)
                }
            }
        }
    }
}
