import Foundation

// Ported from SunCalc.js (https://github.com/mourner/suncalc).
//
// Copyright (c) 2026, Volodymyr Agafonkin
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without modification, are
// permitted provided that the following conditions are met:
//
//    1. Redistributions of source code must retain the above copyright notice, this list of
//       conditions and the following disclaimer.
//
//    2. Redistributions in binary form must reproduce the above copyright notice, this list
//       of conditions and the following disclaimer in the documentation and/or other materials
//       provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
// COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
// EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
// HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
// TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

/// Self-contained sun/moon position and rise/set/phase calculator, so the app doesn't need
/// any network call (or a third source) for sunrise/sunset, twilight windows, or moon data.
public enum SunMoonCalculator {
    private static let rad = Double.pi / 180
    private static let dayMs = 1000.0 * 60 * 60 * 24
    private static let j1970 = 2440588.0
    private static let j2000 = 2451545.0
    private static let obliquityOfEarth = (23.4397) * Double.pi / 180

    // MARK: - Date <-> Julian day

    private static func toJulian(_ date: Date) -> Double {
        date.timeIntervalSince1970 * 1000 / dayMs - 0.5 + j1970
    }

    private static func fromJulian(_ j: Double) -> Date {
        Date(timeIntervalSince1970: ((j + 0.5 - j1970) * dayMs) / 1000)
    }

    private static func toDays(_ date: Date) -> Double {
        toJulian(date) - j2000
    }

    // MARK: - General sun/moon position math

    private static func rightAscension(_ l: Double, _ b: Double) -> Double {
        atan2(sin(l) * cos(obliquityOfEarth) - tan(b) * sin(obliquityOfEarth), cos(l))
    }

    private static func declination(_ l: Double, _ b: Double) -> Double {
        asin(sin(b) * cos(obliquityOfEarth) + cos(b) * sin(obliquityOfEarth) * sin(l))
    }

    private static func azimuth(_ h: Double, _ phi: Double, _ dec: Double) -> Double {
        atan2(sin(h), cos(h) * sin(phi) - tan(dec) * cos(phi))
    }

    private static func altitude(_ h: Double, _ phi: Double, _ dec: Double) -> Double {
        asin(sin(phi) * sin(dec) + cos(phi) * cos(dec) * cos(h))
    }

    private static func siderealTime(_ d: Double, _ lw: Double) -> Double {
        rad * (280.16 + 360.9856235 * d) - lw
    }

    private struct EquatorialCoordinates {
        let declination: Double
        let rightAscension: Double
        let distanceKm: Double
    }

    private static func solarMeanAnomaly(_ d: Double) -> Double {
        rad * (357.5291 + 0.98560028 * d)
    }

    private static func eclipticLongitude(_ m: Double) -> Double {
        let c = rad * (1.9148 * sin(m) + 0.02 * sin(2 * m) + 0.0003 * sin(3 * m))
        let p = rad * 102.9372
        return m + c + p + Double.pi
    }

    private static func sunCoordinates(_ d: Double) -> (declination: Double, rightAscension: Double) {
        let m = solarMeanAnomaly(d)
        let l = eclipticLongitude(m)
        return (declination(l, 0), rightAscension(l, 0))
    }

    private static func moonCoordinates(_ d: Double) -> EquatorialCoordinates {
        let l = rad * (218.316 + 13.176396 * d)
        let m = rad * (134.963 + 13.064993 * d)
        let f = rad * (93.272 + 13.229350 * d)

        let longitude = l + rad * 6.289 * sin(m)
        let latitude = rad * 5.128 * sin(f)
        let distance = 385001.0 - 20905.0 * cos(m)

        return EquatorialCoordinates(
            declination: declination(longitude, latitude),
            rightAscension: rightAscension(longitude, latitude),
            distanceKm: distance
        )
    }

    private static func moonAltitude(atDays d: Double, lw: Double, phi: Double) -> Double {
        let c = moonCoordinates(d)
        let h = siderealTime(d, lw) - c.rightAscension
        return altitude(h, phi, c.declination)
    }

    // MARK: - Sun times (sunrise/sunset + civil/nautical/astronomical twilight)

    public struct SunTimes: Sendable {
        public var sunrise: Date?
        public var sunset: Date?
        public var solarNoon: Date?
        public var civilDawn: Date?      // morning: sun crosses -6 deg going up (civil dark ends)
        public var civilDusk: Date?      // evening: sun crosses -6 deg going down (civil dark starts)
        public var nauticalDawn: Date?
        public var nauticalDusk: Date?
        public var astronomicalDawn: Date? // sun crosses -18 deg going up (astro dark ends)
        public var astronomicalDusk: Date? // sun crosses -18 deg going down (astro dark starts)
    }

    /// Angle (degrees below horizon for negative values), rise-name-role, set-name-role.
    private static let sunAngles: [Double] = [-0.833, -6, -12, -18]

    private static func julianCycle(_ d: Double, _ lw: Double) -> Double {
        (d - 0.0009 - lw / (2 * Double.pi)).rounded()
    }

    private static func approxTransit(_ ht: Double, _ lw: Double, _ n: Double) -> Double {
        0.0009 + (ht + lw) / (2 * Double.pi) + n
    }

    private static func solarTransitJ(_ ds: Double, _ m: Double, _ l: Double) -> Double {
        j2000 + ds + 0.0053 * sin(m) - 0.0069 * sin(2 * l)
    }

    private static func hourAngle(_ h: Double, _ phi: Double, _ d: Double) -> Double {
        acos((sin(h) - sin(phi) * sin(d)) / (cos(phi) * cos(d)))
    }

    private static func setJulian(
        angle: Double, lw: Double, phi: Double, dec: Double, n: Double, m: Double, l: Double
    ) -> Double? {
        let w = hourAngle(angle, phi, dec)
        guard w.isFinite else { return nil }
        let a = approxTransit(w, lw, n)
        return solarTransitJ(a, m, l)
    }

    /// Sunrise/sunset and the three twilight windows for the calendar day containing `date`,
    /// at the given coordinates. Returns nils for angles the sun never reaches that day
    /// (e.g. astronomical twilight near midsummer at high latitudes).
    public static func sunTimes(for date: Date, latitude: Double, longitude: Double) -> SunTimes {
        let lw = rad * -longitude
        let phi = rad * latitude
        let d = toDays(date)
        let n = julianCycle(d, lw)
        let ds = approxTransit(0, lw, n)
        let m = solarMeanAnomaly(ds)
        let l = eclipticLongitude(m)
        let dec = declination(l, 0)
        let jNoon = solarTransitJ(ds, m, l)

        var result = SunTimes()
        result.solarNoon = fromJulian(jNoon)

        for angle in sunAngles {
            let h0 = angle * rad
            guard let jSet = setJulian(angle: h0, lw: lw, phi: phi, dec: dec, n: n, m: m, l: l) else {
                continue
            }
            let jRise = jNoon - (jSet - jNoon)
            let rise = fromJulian(jRise)
            let set = fromJulian(jSet)

            switch angle {
            case -0.833:
                result.sunrise = rise
                result.sunset = set
            case -6:
                result.civilDawn = rise
                result.civilDusk = set
            case -12:
                result.nauticalDawn = rise
                result.nauticalDusk = set
            case -18:
                result.astronomicalDawn = rise
                result.astronomicalDusk = set
            default:
                break
            }
        }
        return result
    }

    // MARK: - Moon rise/set

    public struct MoonTimes: Sendable {
        public var rise: Date?
        public var set: Date?
        public var alwaysUp: Bool = false
        public var alwaysDown: Bool = false
    }

    /// Moon rise/set for the local calendar day containing `date` (`calendar`/`timeZone`
    /// determine what "start of day" means - the search runs midnight-to-midnight local time).
    public static func moonTimes(for date: Date, latitude: Double, longitude: Double, calendar: Calendar) -> MoonTimes {
        let dayStart = calendar.startOfDay(for: date)
        let lw = rad * -longitude
        let phi = rad * latitude
        let heightCorrection = 0.133 * rad

        func altitudeAt(hoursAfterStart hours: Double) -> Double {
            let t = dayStart.addingTimeInterval(hours * 3600)
            return moonAltitude(atDays: toDays(t), lw: lw, phi: phi) - heightCorrection
        }

        var result = MoonTimes()
        var h0 = altitudeAt(hoursAfterStart: 0)
        var riseHour: Double?
        var setHour: Double?

        var hour = 1.0
        while hour <= 24 {
            let h1 = altitudeAt(hoursAfterStart: hour)
            let h2 = altitudeAt(hoursAfterStart: hour + 1)

            let a = (h0 + h2) / 2 - h1
            let b = (h2 - h0) / 2
            let xe = -b / (2 * a)
            let ye = (a * xe + b) * xe + h1
            let discriminant = b * b - 4 * a * h1

            var roots = 0
            var x1 = 0.0
            var x2 = 0.0

            if discriminant >= 0 {
                let dx = sqrt(discriminant) / (abs(a) * 2)
                x1 = xe - dx
                x2 = xe + dx
                if abs(x1) <= 1 { roots += 1 }
                if abs(x2) <= 1 { roots += 1 }
                if x1 < -1 { x1 = x2 }
            }

            if roots == 1 {
                if h0 < 0 {
                    riseHour = hour + x1
                } else {
                    setHour = hour + x1
                }
            } else if roots == 2 {
                riseHour = hour + (ye < 0 ? x2 : x1)
                setHour = hour + (ye < 0 ? x1 : x2)
            }

            if riseHour != nil, setHour != nil { break }

            h0 = h2
            hour += 2
        }

        if let riseHour {
            result.rise = dayStart.addingTimeInterval(riseHour * 3600)
        }
        if let setHour {
            result.set = dayStart.addingTimeInterval(setHour * 3600)
        }
        if result.rise == nil, result.set == nil {
            result.alwaysUp = h0 > 0
            result.alwaysDown = !result.alwaysUp
        }
        return result
    }

    /// Time of the moon's highest altitude ("zenith"/meridian transit) within the local
    /// calendar day containing `date`. Not part of the original SunCalc API - found here by
    /// coarse-then-fine sampling of altitude rather than an analytic solve.
    public static func moonTransit(for date: Date, latitude: Double, longitude: Double, calendar: Calendar) -> Date? {
        let dayStart = calendar.startOfDay(for: date)
        let lw = rad * -longitude
        let phi = rad * latitude

        func altitudeAt(_ t: Date) -> Double {
            moonAltitude(atDays: toDays(t), lw: lw, phi: phi)
        }

        var bestTime = dayStart
        var bestAltitude = -Double.infinity
        var minutes = 0
        while minutes <= 24 * 60 {
            let t = dayStart.addingTimeInterval(Double(minutes) * 60)
            let alt = altitudeAt(t)
            if alt > bestAltitude {
                bestAltitude = alt
                bestTime = t
            }
            minutes += 5
        }
        return bestTime
    }

    // MARK: - Moon illumination / phase

    public struct MoonIllumination: Sendable {
        /// Fraction of the moon's disk illuminated, 0...1.
        public let fraction: Double
        /// 0 = new moon, 0.25 = first quarter, 0.5 = full, 0.75 = last quarter, 1 = new again.
        public let phase: Double
        public let angle: Double
    }

    public static func moonIllumination(for date: Date) -> MoonIllumination {
        let d = toDays(date)
        let s = sunCoordinates(d)
        let m = moonCoordinates(d)

        let sunEarthDistanceKm = 149598000.0
        let phi = acos(
            sin(s.declination) * sin(m.declination)
                + cos(s.declination) * cos(m.declination) * cos(s.rightAscension - m.rightAscension)
        )
        let inc = atan2(
            sunEarthDistanceKm * sin(phi),
            m.distanceKm - sunEarthDistanceKm * cos(phi)
        )
        let angle = atan2(
            cos(s.declination) * sin(s.rightAscension - m.rightAscension),
            sin(s.declination) * cos(m.declination)
                - cos(s.declination) * sin(m.declination) * cos(s.rightAscension - m.rightAscension)
        )

        let phase = 0.5 + 0.5 * inc * (angle < 0 ? -1.0 : 1.0) / Double.pi
        return MoonIllumination(fraction: (1 + cos(inc)) / 2, phase: phase, angle: angle)
    }

    /// Maps a 0...1 phase fraction to one of the 8 traditional phase names (used to pick the
    /// matching SF Symbol / display name).
    public static func moonPhaseName(forPhase phase: Double) -> String {
        switch phase {
        case ..<0.0625, 0.9375...: return "new moon"
        case ..<0.1875: return "waxing crescent"
        case ..<0.3125: return "first quarter"
        case ..<0.4375: return "waxing gibbous"
        case ..<0.5625: return "full moon"
        case ..<0.6875: return "waning gibbous"
        case ..<0.8125: return "last quarter"
        default: return "waning crescent"
        }
    }
}
