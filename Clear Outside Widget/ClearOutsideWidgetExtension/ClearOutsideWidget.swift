import WidgetKit
import SwiftUI
import ClearOutsideCore

struct ClearOutsideWidget: Widget {
    let kind: String = "ClearOutsideWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ForecastTimelineProvider()) { entry in
            ClearOutsideWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Clear Outside Forecast")
        .description("Wolken, Seeing und Transparenz für die kommenden Nächte.")
        .supportedFamilies([.systemSmall, .systemLarge])
    }
}

#Preview(as: .systemSmall) {
    ClearOutsideWidget()
} timeline: {
    ForecastEntry(date: .now, state: .placeholder)
}

#Preview(as: .systemLarge) {
    ClearOutsideWidget()
} timeline: {
    ForecastEntry(date: .now, state: .placeholder)
}
