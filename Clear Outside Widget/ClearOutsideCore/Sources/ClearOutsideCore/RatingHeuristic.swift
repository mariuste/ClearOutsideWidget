import Foundation

/// Our own bad/ok/good rating for the new (Open-Meteo + 7Timer) data stack - neither source
/// hands us a ready-made quality label the way ClearOutside's `fc_hour_ratings` row did.
///
/// Thresholds are deliberately simple and documented here rather than derived from anything
/// official; tune freely if they don't feel right in practice.
public enum RatingHeuristic {
    public static func rate(
        cloudPercent: Int?,
        precipitationMm: Double?,
        seeingRaw: Int?,
        transparencyRaw: Int?
    ) -> HourRating {
        guard let cloudPercent else { return .unknown }

        let hasPrecipitation = (precipitationMm ?? 0) > 0
        let astroIsBad = (seeingRaw.map { $0 >= 7 } ?? false) || (transparencyRaw.map { $0 >= 7 } ?? false)

        if cloudPercent >= 60 || hasPrecipitation || astroIsBad {
            return .bad
        }

        // When seeing/transparency aren't available (beyond 7Timer's 3-day astro window),
        // a "good" rating falls back to cloud cover + precipitation alone.
        let astroIsGood = (seeingRaw.map { $0 <= 4 } ?? true) && (transparencyRaw.map { $0 <= 4 } ?? true)

        if cloudPercent <= 20 && !hasPrecipitation && astroIsGood {
            return .good
        }

        return .ok
    }
}
