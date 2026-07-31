import AppIntents
import ClearOutsideCore

/// Widget-facing mirror of `ForecastSourceKind` - `AppEnum` needs its own type (rather than
/// making the core enum conform directly) to keep AppIntents out of the shared package.
enum ForecastSourceOption: String, AppEnum {
    case sevenTimerStack
    case clearOutside

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Datenquelle"
    static var caseDisplayRepresentations: [ForecastSourceOption: DisplayRepresentation] = [
        .sevenTimerStack: "Open-Meteo + 7Timer",
        .clearOutside: "ClearOutside (Fallback)"
    ]

    var kind: ForecastSourceKind {
        switch self {
        case .sevenTimerStack: return .sevenTimerStack
        case .clearOutside: return .clearOutside
        }
    }
}

/// Lets the user pick a data source per widget instance via "Edit Widget" (long-press) -
/// the app's own source picker can't reach the widget without an App Group, so this is an
/// independent, widget-native equivalent rather than a synced setting.
struct SelectForecastSourceIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Datenquelle"
    static var description = IntentDescription("Wähle die Datenquelle für dieses Widget.")

    @Parameter(title: "Quelle", default: .sevenTimerStack)
    var source: ForecastSourceOption

    init() {}

    init(source: ForecastSourceOption) {
        self.source = source
    }
}
