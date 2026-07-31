# Clear Outside Widget

Eine iOS-App mit Home-Screen-Widget, die das Astro-Wetter (Wolken, Dämmerung, Mondphase) von [clearoutside.com](https://clearoutside.com/forecast/48.00/7.85?experimental=on) für Sternengucker aufbereitet — als Tagesansicht mit stündlichem Detail und als 6-Tage-Wochenübersicht.

## Features

- **App**: heutige Nacht als Zeitleiste von Sonnenuntergang bis -aufgang (stündliche Bewertung, Sonnenstand-Verlauf, Mondauf-/-untergang inkl. Zenit), darunter eine antippbare 6-Tage-Übersicht im gleichen Stil.
- **Widget**:
  - **Mittel**: heutige Nacht im Detail (gleiche Zeitleiste wie die App, verdichtet).
  - **Groß**: 6-Tage-Wochenübersicht.
- **Lokale Benachrichtigung**: informiert einmalig, sobald sich die Vorhersage fürs kommende Wochenende (Fr–So) von "nicht gut" auf "gut" ändert — läuft komplett lokal über `BGTaskScheduler` + `UNUserNotificationCenter`, kein Server nötig.
- Farbschema orientiert sich an ClearOutside selbst: Rot = Sonne oben oder Wolken, Orange = klare Dämmerung, Grün = klare Nacht; Sonnenstand-Bar in Gelb/Orange/Hellblau/Dunkelblau/Schwarz; Mond-Bar in Blau (unten) / Grau (oben) mit rotem Zenit-Strich.

## Architektur

```
Clear Outside Widget/
├── Clear Outside Widget/          # App-Target (SwiftUI)
├── ClearOutsideWidgetExtension/    # WidgetKit-Extension
└── ClearOutsideCore/                # Lokales Swift Package, von App + Widget geteilt
    ├── Parsing/                    # SwiftSoup-basierter HTML-Parser für ClearOutside
    ├── Networking/                 # URLSession-Client
    ├── Storage/                    # Lokaler Cache (kein App Group nötig)
    ├── Models/                     # ForecastCache, DayForecast, HourForecast, SunZone, ...
    └── Views/                      # NightTimelineView (von App und Widget genutzt)
```

Es gibt **kein App Group** — App und Widget-Extension holen und cachen die Vorhersage jeweils unabhängig voneinander. Das ist bewusst so, weil App Groups einen kostenpflichtigen Apple-Developer-Account erfordern; mit einem kostenlosen Account funktioniert diese Architektur ohne Einschränkung (die App läuft dann halt nur 7 Tage ohne Neuinstallation über Xcode).

Da ClearOutside.com keine offizielle API hat, wird die Vorhersage direkt aus dem HTML gescraped (SwiftSoup). Der Parser wird gegen eine echte, eingefrorene HTML-Fixture getestet (`ClearOutsideCore/Tests/ClearOutsideCoreTests/Fixtures/sample_forecast.html`) — ändert ClearOutside sein Markup, schlagen die Tests fehl und die Fixture muss aktualisiert werden.

## Bauen & Testen

```bash
# Parser/Model-Tests (schnell, kein Netzwerk, kein Simulator nötig)
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
- Kein App Group → App und Widget können sich nicht denselben Cache teilen, fetchen aber ohnehin dieselbe öffentliche URL.
- Scraping ist an das aktuelle HTML von ClearOutside gebunden; Layoutänderungen der Seite können den Parser brechen (siehe Testhinweis oben).
