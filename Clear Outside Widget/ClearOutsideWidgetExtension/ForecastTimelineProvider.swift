import WidgetKit
import ClearOutsideCore

struct ForecastEntry: TimelineEntry {
    let date: Date
    let state: ForecastLoadState
}

struct ForecastTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ForecastEntry {
        ForecastEntry(date: Date(), state: .placeholder)
    }

    func snapshot(for configuration: SelectForecastSourceIntent, in context: Context) async -> ForecastEntry {
        if context.isPreview {
            return ForecastEntry(date: Date(), state: .placeholder)
        }
        let repository = ForecastRepository(sourceKind: configuration.source.kind)
        let state = await repository.cachedOrRefresh(maxAge: 3600)
        return ForecastEntry(date: Date(), state: state)
    }

    func timeline(for configuration: SelectForecastSourceIntent, in context: Context) async -> Timeline<ForecastEntry> {
        let repository = ForecastRepository(sourceKind: configuration.source.kind)
        let state = await repository.cachedOrRefresh(maxAge: 3600)
        let entry = ForecastEntry(date: Date(), state: state)
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date().addingTimeInterval(7200)
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
}
