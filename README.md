# Clear Outside Widget

Eine iOS-App mit Home-Screen-Widget für das Astro-Wetter (Wolken, Dämmerung, Mondphase) — als Tagesansicht mit stündlichem Detail und als 6-Tage-Wochenübersicht. Ursprünglich ein Aufbereiter für [clearoutside.com](https://clearoutside.com/forecast/48.00/7.85?experimental=on); seit dem Redesign holt die App die Daten standardmäßig direkt von den Quellen, auf denen auch ClearOutside selbst größtenteils aufbaut (siehe unten).

## Features

- **App**: heutige Nacht als Zeitleiste von Sonnenuntergang bis -aufgang (stündliche Bewertung, Sonnenstand-Verlauf, Mondauf-/-untergang inkl. Zenit), darunter eine antippbare 6-Tage-Übersicht im gleichen Stil.
- **Widget**:
  - **Mittel**: heutige Nacht im Detail (gleiche Zeitleiste wie die App, verdichtet).
  - **Groß**: 6-Tage-Wochenübersicht.
- **Datenquelle wählbar**: Antennen-Icon im Toolbar der App wechselt zwischen dem neuen Standard-Stack und ClearOutside als Fallback (siehe unten). Das Widget bleibt technisch bedingt immer auf dem Standard-Stack.
- Farbschema orientiert sich an ClearOutside selbst: Rot = Sonne oben oder Wolken, Orange = klare Dämmerung, Grün = klare Nacht; Sonnenstand-Bar in Gelb/Orange/Hellblau/Dunkelblau/Schwarz; Mond-Bar in Blau (unten) / Grau (oben) mit rotem Zenit-Strich.

## Datenquellen & Lizenzen

Standardmäßig kombiniert die App drei Quellen zu einer Vorhersage (siehe `REDESIGN_PLAN.md` für den vollen Hintergrund):

| Quelle | Liefert | Auflösung/Reichweite | Lizenz/Bedingungen |
|---|---|---|---|
| [Open-Meteo](https://open-meteo.com/) | Wolken, Temperatur, Niederschlag, Wind, Luftfeuchte | stündlich, mehrere Tage | **CC BY 4.0** (Attribution-Pflicht), kostenlos nur für nicht-kommerzielle Nutzung |
| [7Timer!](https://www.7timer.info/doc.php?lang=en) | Astronomisches Seeing, Transparenz, Lifted Index | 3h-Raster, 3 Tage (GFS-Modell-Eigenschaft) | kostenlos, nur nicht-kommerziell; Autor bittet um Hinweis bei Nutzung |
| [SunCalc](https://github.com/mourner/suncalc) (nach Swift portiert, kein Netzwerk) | Sonnenauf-/-untergang, Civil/Nautical/Astro-Dämmerung, Mondauf-/-untergang, Mondphase | beliebig viele Tage, rein lokal berechnet | **BSD-2-Clause** (Copyright-Hinweis in `SunMoonCalculator.swift` erhalten) |

Alle drei sind für dieses nicht-kommerzielle Hobby-Projekt (keine Werbung, keine Abos) im jeweils kostenlosen Rahmen nutzbar. Rate-Limits werden durch getrennte Cache-Fenster respektiert (Open-Meteo ~1h, 7Timer seltener, da es selbst nur 4×/Tag aktualisiert).

**Fallback-Quelle:** ClearOutside.com hat keine offizielle API; der ursprüngliche HTML-Scraper (SwiftSoup-basiert) bleibt im Code erhalten und ist über das Antennen-Icon in der App wählbar, falls der neue Stack einmal ausfällt oder zum Vergleich. Er bricht bei Layout-Änderungen der Seite — daher nicht mehr der Standard.

## Architektur

```
Clear Outside Widget/
├── Clear Outside Widget/          # App-Target (SwiftUI)
├── ClearOutsideWidgetExtension/    # WidgetKit-Extension
└── ClearOutsideCore/               # Lokales Swift Package, von App + Widget geteilt
    ├── Astronomy/                  # SunMoonCalculator (SunCalc-Port, kein Netzwerk)
    ├── Networking/                 # OpenMeteoClient, SevenTimerClient, ClearOutsideClient
    ├── Parsing/                    # ClearOutsideParser (HTML, nur noch Fallback-Pfad)
    ├── Storage/                    # Lokaler Cache (kein App Group nötig)
    ├── Models/                     # ForecastCache, DayForecast, HourForecast, SunZone, ...
    ├── Views/                      # NightTimelineView (von App und Widget genutzt)
    ├── ForecastSource.swift        # Protokoll + ForecastSourceKind (Standard/Fallback)
    ├── SevenTimerForecastSource.swift   # Standard: Open-Meteo + 7Timer + SunMoonCalculator
    ├── ClearOutsideForecastSource.swift # Fallback: wrapt den HTML-Scraper
    ├── RatingHeuristic.swift       # eigene Gut/Ok/Schlecht-Bewertung für den neuen Stack
    └── ForecastRepository.swift    # Cache-first Orchestrierung, quellenunabhängig
```

Es gibt **kein App Group** — App und Widget-Extension holen und cachen die Vorhersage jeweils unabhängig voneinander. Das ist bewusst so, weil App Groups einen kostenpflichtigen Apple-Developer-Account erfordern; mit einem kostenlosen Account funktioniert diese Architektur ohne Einschränkung (die App läuft dann halt nur 7 Tage ohne Neuinstallation über Xcode). Die App-seitige Quellenauswahl kann aus demselben Grund nicht mit dem Widget geteilt werden — das Widget nutzt immer den Standard-Stack.

## Bauen & Testen

```bash
# Parser-, Client-, Astronomie- und Merge-Tests (schnell, kein Netzwerk, kein Simulator nötig)
cd "Clear Outside Widget/ClearOutsideCore"
swift test

# App + Widget für den Simulator bauen
cd "Clear Outside Widget"
xcodebuild -project "Clear Outside Widget.xcodeproj" -scheme "Clear Outside Widget" \
  -destination "platform=iOS Simulator,name=iPhone 17" build
```

Zum Testen auf einem echten iPhone: in Xcode das eigene Team unter *Signing & Capabilities* auswählen (beide Targets: App + `ClearOutsideWidgetExtension`), iPhone per Kabel/WLAN als Ziel wählen und Run. Mit einem kostenlosen Apple-ID-Account muss die App alle 7 Tage einmal neu über Xcode installiert werden.

## Bekannte Einschränkungen

- Free-Account: App läuft 7 Tage, dann Re-Signing über Xcode nötig.
- Kein App Group → App und Widget können sich nicht denselben Cache oder dieselbe Quellenauswahl teilen; das Widget bleibt immer auf dem Standard-Stack.
- 7Timer liefert Seeing/Transparenz nur für die ersten ~3 Tage; danach fällt die Bewertung auf reine Wolken-/Niederschlagsdaten zurück (siehe `RatingHeuristic`).
- ClearOutside-Fallback ist an das aktuelle HTML der Seite gebunden; Layoutänderungen können den Parser brechen (siehe `ClearOutsideCoreTests`).
