# Redesign: weg von ClearOutside-Scraping, direkt zu den Quellen

Branch: `redesign/7timer-source`

## Warum

ClearOutside.com hat keine offizielle API — wir scrapen HTML, das bei jeder Layout-Änderung der Seite bricht. ClearOutside selbst baut seine Anzeige größtenteils auf denselben öffentlichen Modelldaten auf (u. a. 7Timer/GFS). Ziel: direkt an diese Quellen andocken und sie zum **neuen Standard** machen. ClearOutside-Scraping wird **nicht gelöscht**, sondern bleibt als wählbare Fallback-Quelle in der App erhalten (siehe Abschnitt weiter unten) — SwiftSoup bleibt entsprechend eine Abhängigkeit, nur eben nicht mehr die einzige Datenquelle.

## Der neue Daten-Stack (3 Quellen statt 1 Scrape)

### 1. Open-Meteo — Wolken/Wetter-Grid (stündlich, kostenlos, kein Key, bis 16 Tage)

```
https://api.open-meteo.com/v1/forecast?latitude=48.00&longitude=7.85
  &hourly=cloudcover,cloudcover_low,cloudcover_mid,cloudcover_high,temperature_2m,
          precipitation,windspeed_10m,relativehumidity_2m,pressure_msl,visibility
  &forecast_days=7&timezone=auto
```

Antwort: `{"hourly": {"time": [...ISO-lokal...], "cloudcover": [...], ...}}`, alle Arrays synchron zum `time`-Array, echte Stundenauflösung. Liefert genau das Cloud-Cover-Niveau, das CO zeigte — aber mit mehr Tagen Vorlauf als bisher (bis zu 16, wir zeigen weiter 6–7).

### 2. 7Timer ASTRO — Seeing/Transparency/Lifted Index (3h-Raster, 3 Tage)

```
https://www.7timer.info/bin/api.pl?lon=7.85&lat=48.00&product=astro&output=json&unit=metric&tzshift=0
```

Antwort: `init` (UTC `yyyyMMddHH` des Modell-Laufs), `dataseries[]` mit `timepoint` (Stunden seit `init`, 3er-Schritte, 24 Punkte = 72h). Felder: `cloudcover`(1-9), `seeing`(1-8), `transparency`(1-8), `lifted_index`, `rh2m`(-4..16), `wind10m{direction,speed}`, `temp2m`(°C, roh), `prec_type`.

Das ist eine GFS-Modell-Eigenschaft, kein Abruf-Limit — es gibt keine kostenlose stündliche Quelle für Seeing/Transparency. Wir übernehmen CO's eigenen Ansatz: jeder 3h-Wert gilt unverändert für die 3 zugehörigen Stundenslots (`hourly_value = threehour_value[floor(hoursSinceInit / 3)]`).

### 3. SunCalc (Port nach Swift) — Sonne & Mond

Reine Berechnung, kein Netzwerk. Portierung der bekannten, gut getesteten SunCalc.js-Formeln (MIT/BSD, ~250 Zeilen):

- `getTimes(date, lat, lon)` → Sonnenaufgang/-untergang, Solar Noon, sowie civil/nautical/astronomical Dawn & Dusk — exakt die drei Dämmerungsstufen, die wir schon als `civilDark*/nauticalDark*/astroDark*` im Modell haben.
- `getMoonTimes(date, lat, lon)` → Mondauf-/-untergang.
- `getMoonIllumination(date)` → beleuchteter Anteil, Phase, Winkel (für Zenit/Transit zusätzlich ein Altitude-Maximum-Scan über den Tag).

Vorteil: für **jeden** angezeigten Tag verfügbar (nicht auf 3 Tage limitiert wie 7Timer), also keine Einschränkung gegenüber heute.

## Zusammenführung

`ForecastRepository.refresh()` holt alle drei Quellen parallel (`async let`) und merged sie in die **bestehende** `ForecastCache`/`DayForecast`/`HourForecast`-Form — die UI (`NightTimelineView`, `ContentView`, Widget) bleibt dadurch unverändert:

- `totalCloudPercent` ← Open-Meteo `cloudcover` (0–100%, direkte Übernahme, sogar genauer als bisher)
- `seeingRaw`/`transparencyRaw` ← 7Timer-Bucket-Werte, konstant über die 3 Stunden gehalten; `nil` für Stunden jenseits des 3-Tage-Astro-Fensters
- `sunrise/sunset/civilDark*/nauticalDark*/astroDark*/moonrise/moonset/moonTransit/moonPhaseName/moonIlluminationPercent` ← SunCalc, für alle Tage
- `rating` (`HourRating`) ← **neu selbst berechnet** (siehe unten), da 7Timer/Open-Meteo keine fertige "gut/ok/schlecht"-Einstufung liefern

## Eigene Bewertungs-Heuristik (ersetzt CO's `fc_hour_ratings`)

Vorschlag (einfach, dokumentiert, später leicht justierbar):

```
bad:  cloudcover% >= 60  ODER  precipitation > 0  ODER  (seeing/transparency vorhanden UND (seeing>=7 ODER transparency>=7))
good: cloudcover% <= 20  UND  precipitation == 0  UND  (seeing/transparency fehlt ODER (seeing<=4 UND transparency<=4))
ok:   alles dazwischen
```

Für Tage jenseits des 3-Tage-Astro-Fensters fließt Seeing/Transparency nicht ein (fehlt schlicht) — Bewertung dort basiert nur auf Wolken/Niederschlag. Sollte in der UI später erkennbar sein (z. B. dezent andere Darstellung ab Tag 4), ist aber kein Blocker für den Kern-Umbau.

## Quelle in der App wählbar — ClearOutside bleibt als Fallback

Neue Anforderung: ClearOutside wird **nicht gelöscht**, sondern bleibt als alternative Quelle wählbar (Dropdown in der App), falls der neue Stack mal ausfällt oder man vergleichen will. Der bisherige Scraper (`ClearOutsideClient` + `ClearOutsideParser` + SwiftSoup) bleibt also im Package, wird aber hinter eine gemeinsame Abstraktion gezogen:

```swift
public enum ForecastSourceKind: String, CaseIterable, Codable, Sendable {
    case sevenTimerStack  // neuer Standard: Open-Meteo + 7Timer + SunCalc
    case clearOutside     // Fallback: bestehender HTML-Scraper
}

public protocol ForecastSource: Sendable {
    func fetch(latitude: Double, longitude: Double) async throws -> ForecastCache
}
```

- `SevenTimerForecastSource` — orchestriert die drei neuen Clients + Merge + Rating.
- `ClearOutsideForecastSource` — dünner Wrapper um den bestehenden `ClearOutsideClient`/`ClearOutsideParser` (unverändert, nur hinter das Protokoll gehängt).
- `ForecastRepository` bekommt einen `ForecastSourceKind`-Parameter (Standard `.sevenTimerStack`) und wählt beim Fetch die passende Implementierung.

**In der App:** Auswahl-UI (z. B. Picker/Menü im Toolbar oder eigener kleiner Einstellungs-Screen), Auswahl persistiert via `@AppStorage("forecastSourceKind")`. Wechsel der Quelle stößt sofort einen Refresh an.

**Wichtige Einschränkung (kein App Group, siehe oben):** Die Auswahl lässt sich aktuell **nicht** mit dem Widget teilen — das Widget hat keinen Zugriff auf die UserDefaults der App. Vorschlag: Widget nutzt immer den neuen Standard-Stack (`.sevenTimerStack`), die Quellenauswahl wirkt sich nur auf die App aus. Eine Widget-eigene Auswahl wäre nur über eine `AppIntentConfiguration` (konfigurierbares Widget, "Widget bearbeiten" im Home Screen) möglich — das ist ein eigenständiges, größeres Stück Arbeit und hier bewusst **nicht** mit eingeplant, kann aber später ergänzt werden.

## Code-Änderungen in `ClearOutsideCore`

**Bleibt (jetzt als Fallback-Implementierung hinter `ForecastSource`):**
- `Parsing/ClearOutsideParser.swift`, `Networking/ClearOutsideClient.swift`, SwiftSoup-Abhängigkeit, HTML-Fixture + Parser-Tests — alles unverändert, nur neu eingeordnet als `ClearOutsideForecastSource`.

**Neu:**
- `Networking/OpenMeteoClient.swift` — Codable-Structs + `URLSession`
- `Networking/SevenTimerClient.swift` — Codable-Structs + `URLSession`
- `Astronomy/SunMoonCalculator.swift` — SunCalc-Port (reine Funktionen, kein I/O)
- `Sources/SevenTimerForecastSource.swift`, `Sources/ClearOutsideForecastSource.swift`, `ForecastSource`-Protokoll + `ForecastSourceKind`-Enum
- `RatingHeuristic.swift` — Bewertungsfunktion für den neuen Stack, pur & leicht testbar (nur für `.sevenTimerStack` nötig — ClearOutside liefert seine Bewertung wie bisher direkt mit)

**Bleibt unverändert:** `Models/ForecastModels.swift` (Datenmodell + `darknessFraction`/`sunZone`/`isMoonUp` bleiben gültig), alle UI-Views (`NightTimelineView`, `ContentView`, Widget-Views), `LocalForecastStore`.

## Tests

- Eingefrorene JSON-Fixtures für Open-Meteo und 7Timer (analog zur bisherigen HTML-Fixture) → deterministische Decode-/Merge-Tests ohne Netzwerk.
- `SunMoonCalculator`-Tests gegen bekannte Referenzwerte (z. B. veröffentlichte Sonnenauf-/-untergangszeiten für ein festes Datum/Ort, Toleranz ±2 Min; Mondphase ±5%).
- Reine Unit-Tests für die Rating-Heuristik (Tabelle von Eingabe→erwartetem Ergebnis).

## Nutzungsrechte, Lizenzen & Limitierungen

Alle drei Quellen sind **nur für nicht-kommerzielle Nutzung** kostenlos — passt zu diesem Projekt (privates Hobby-Projekt, keine Werbung, keine Abos/IAP), muss aber beachtet werden, falls die App je monetarisiert werden soll (dann bräuchte man kostenpflichtige Pläne bzw. eine andere Quelle).

**Open-Meteo** (geprüft unter [open-meteo.com/en/terms](https://open-meteo.com/en/terms)):
- Free API nur für nicht-kommerzielle Nutzung (genau unsere Situation: "private ... apps that do not have subscriptions or advertising").
- Rate-Limits: < 10.000 Calls/Tag, 5.000/Stunde, 600/Minute — bei unserem Cache (max. 1 Fetch/Stunde je App-Instanz) niemals relevant.
- Daten stehen unter **CC-BY 4.0** → Attribution ist Pflicht, nicht optional. Muss in README **und** irgendwo in der App (z. B. Einstellungen/Info-Screen oder Footer) als Quellenangabe auftauchen ("Wetterdaten: Open-Meteo.com, CC BY 4.0").

**7Timer!** (geprüft unter [7timer.info/doc.php](https://www.7timer.info/doc.php?lang=en)):
- Kostenlos, aber ausdrücklich nur nicht-kommerziell ("as long as you are not using them for commercial purpose").
- Kein explizites Rate-Limit dokumentiert, aber das Modell aktualisiert nur **4×/Tag** — häufiger als alle paar Stunden abzurufen bringt nichts und ist unhöflich gegenüber einem klein/ehrenamtlich betriebenen Dienst. Cache-Fenster für 7Timer-Abrufe daher bewusst länger (z. B. 3–6h) als für Open-Meteo (1h).
- Höflichkeitsbitte (keine harte Pflicht): Autor über die Nutzung informieren. Kann in README erwähnt/verlinkt werden, kein Blocker.
- Attribution ebenfalls sinnvoll/fair, auch wenn nicht explizit unter einer offenen Lizenz wie CC-BY gefordert.

**SunCalc-Port** (Original: [github.com/mourner/suncalc](https://github.com/mourner/suncalc)):
- **BSD-2-Clause-Lizenz** (nicht MIT, wie zunächst vermutet — geprüft). Erlaubt Portierung/Ableitung, verlangt aber: Copyright-Hinweis + Disclaimer müssen in Quell- **und** ggf. Binärform-Dokumentation erhalten bleiben.
- Umsetzung: Lizenztext + Originalautor (Vladimir Agafonkin) als Kommentarkopf in `SunMoonCalculator.swift` übernehmen, zusätzlich in einer `THIRD-PARTY-NOTICES.md` (oder README-Abschnitt) auflisten.

**Konsequenz fürs Design:** getrennte Cache-/Refresh-Fenster pro Quelle (Open-Meteo ~1h, 7Timer ~3–6h, SunCalc rein lokal/keine Netzabfrage) statt eines einzigen `maxAge` wie bisher — spart unnötige Requests und ist fair gegenüber beiden Diensten. README bekommt einen "Datenquellen & Lizenzen"-Abschnitt mit allen drei Nennungen.

## Entschieden: Wochenend-Benachrichtigung entfällt (vorerst)

Mit nur 3 Tagen Astro-Vorschau wäre Fr/Sa/So die meiste Zeit außerhalb des Fensters gewesen — das Feature wurde daher **komplett entfernt** (nicht nur deaktiviert): `WeekendQualityEvaluator.swift`, `BackgroundRefreshManager.swift`, die zugehörigen Tests, sowie `BGTaskSchedulerPermittedIdentifiers`/`UIBackgroundModes` aus der App-Info.plist. Kann bei Bedarf später neu gedacht werden (z. B. Option 3 aus der ursprünglichen Abwägung: Bewertung nur aus Cloud-Cover, das immer verfügbar ist).

## Etappen (analog zum bisherigen Vorgehen: klein, einzeln testbar)

1. **Clients & Fixtures**: `OpenMeteoClient`, `SevenTimerClient` + eingefrorene JSON-Antworten, reine Decode-Tests.
2. **SunMoonCalculator**: SunCalc-Port + Referenzwert-Tests, unabhängig vom Rest.
3. **Merge & Rating**: `SevenTimerForecastSource` + Rating-Heuristik, baut `ForecastCache` aus den drei Quellen + Fixtures aus Schritt 1+2.
4. **Source-Abstraktion**: `ForecastSource`-Protokoll + `ForecastSourceKind` einführen, bestehenden ClearOutside-Scraper unverändert als `ClearOutsideForecastSource` dahinter hängen, `ForecastRepository` auf die Abstraktion umstellen (Standard: `.sevenTimerStack`).
5. **Auswahl-UI in der App**: Picker/Menü + `@AppStorage`, Wechsel stößt Refresh an. Widget bleibt vorerst fest auf `.sevenTimerStack`.
6. **App + Widget durchtesten**: gegen echte Daten (Simulator), beide Quellen einzeln durchklicken, prüfen dass `NightTimelineView`, Wochenübersicht, Widget unverändert funktionieren (sollten sie, da Datenmodell gleich bleibt).
7. **README/Attribution**: Datenquellen-Abschnitt aktualisieren (Open-Meteo + 7Timer + eigene Sonnen-/Mondberechnung als Standard, ClearOutside als Fallback-Option erwähnt).
