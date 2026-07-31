import WidgetKit
import ClearOutsideCore

struct ForecastEntry: TimelineEntry {
    let date: Date
    let state: ForecastLoadState
}

struct ForecastTimelineProvider: TimelineProvider {
    private let repository = ForecastRepository()

    func placeholder(in context: Context) -> ForecastEntry {
        ForecastEntry(date: Date(), state: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (ForecastEntry) -> Void) {
        if context.isPreview {
            completion(ForecastEntry(date: Date(), state: .placeholder))
            return
        }
        Task {
            let state = await repository.cachedOrRefresh(maxAge: 3600)
            completion(ForecastEntry(date: Date(), state: state))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ForecastEntry>) -> Void) {
        Task {
            let state = await repository.cachedOrRefresh(maxAge: 3600)
            let entry = ForecastEntry(date: Date(), state: state)
            let nextUpdate = Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date().addingTimeInterval(7200)
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }
}
