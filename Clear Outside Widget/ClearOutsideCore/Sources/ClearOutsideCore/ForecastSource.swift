import Foundation

/// A pluggable way to fetch a `ForecastCache`. Lets the app pick between the primary
/// Open-Meteo + 7Timer + SunMoonCalculator stack and the original ClearOutside HTML scraper
/// (kept as a fallback, not deleted, in case the new stack ever misbehaves).
public protocol ForecastSource: Sendable {
    func fetch(latitude: Double, longitude: Double) async throws -> ForecastCache
}

/// Which `ForecastSource` to use - persisted by the app (e.g. via `@AppStorage`) so the
/// user's choice survives relaunches. The widget always uses `.sevenTimerStack` regardless
/// of this setting, since it has no way to read the app's preference without an App Group.
public enum ForecastSourceKind: String, CaseIterable, Codable, Sendable {
    case sevenTimerStack
    case clearOutside

    public var displayName: String {
        switch self {
        case .sevenTimerStack: return "Open-Meteo + 7Timer"
        case .clearOutside: return "ClearOutside (Fallback)"
        }
    }

    public func makeSource() -> ForecastSource {
        switch self {
        case .sevenTimerStack: return SevenTimerForecastSource()
        case .clearOutside: return ClearOutsideForecastSource()
        }
    }
}
