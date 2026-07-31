//
//  ContentView.swift
//  Clear Outside Widget
//
//  Created by Marius Tetard on 30.07.26.
//

import SwiftUI
import ClearOutsideCore

struct ContentView: View {
    @State private var loadState: ForecastLoadState = .placeholder
    @State private var isRefreshing = false
    @State private var selectedDayIndex = 0
    @Environment(\.scenePhase) private var scenePhase

    private let repository = ForecastRepository()

    var body: some View {
        NavigationStack {
            Group {
                switch loadState {
                case .placeholder:
                    ProgressView("Lade Vorhersage…")
                case .loaded(let cache):
                    forecastList(for: cache)
                case .staleCache(let cache, let asOf):
                    VStack(spacing: 0) {
                        staleBanner(asOf: asOf)
                        forecastList(for: cache)
                    }
                case .error(let message):
                    ContentUnavailableView("Vorhersage nicht verfügbar", systemImage: "cloud.slash", description: Text(message))
                }
            }
            .navigationTitle("Astro-Wetter")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing)
                }
            }
        }
        .task {
            loadState = await repository.cachedOrRefresh(maxAge: 3600)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { loadState = await repository.cachedOrRefresh(maxAge: 3600) }
        }
    }

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let cache = try await repository.refresh()
            loadState = .loaded(cache)
        } catch {
            if case .loaded(let previous) = loadState {
                loadState = .staleCache(previous, asOf: previous.fetchedAt)
            } else {
                loadState = .error(message: String(describing: error))
            }
        }
    }

    private func staleBanner(asOf: Date) -> some View {
        Text("Zuletzt aktualisiert: \(asOf.formatted(date: .omitted, time: .shortened))")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(.yellow.opacity(0.2))
    }

    private func forecastList(for cache: ForecastCache) -> some View {
        let days = Array(cache.days.prefix(6))
        let selectedDay = days.indices.contains(selectedDayIndex) ? days[selectedDayIndex] : days.first

        return List {
            if let selectedDay {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        NightTimelineView(day: selectedDay)
                            .padding(.vertical, 6)
                    }
                } header: {
                    Text(relativeDayHeader(for: selectedDay.date, dayIndex: selectedDayIndex))
                        .foregroundStyle(selectedDayIndex == 0 ? .secondary : Color.accentColor)
                }
            }

            Section("Nächste 6 Tage") {
                ForEach(Array(days.enumerated()), id: \.element.date) { index, day in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(germanWeekday(for: day.date))
                                .font(.subheadline.weight(.medium))
                            if let illumination = day.moonIlluminationPercent {
                                Label("\(illumination)%", systemImage: NightTimelineView.moonPhaseSymbolName(for: day))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 70, alignment: .leading)

                        NightTimelineView(day: day, style: .compact)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .listRowBackground(index == selectedDayIndex ? Color.accentColor.opacity(0.12) : nil)
                    .onTapGesture {
                        selectedDayIndex = index
                    }
                }
            }
        }
    }

    private func germanWeekday(for date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "de_DE")))
    }

    private func relativeDayHeader(for date: Date, dayIndex: Int) -> String {
        let weekday = germanWeekday(for: date)
        switch dayIndex {
        case 0: return "Heute Nacht (\(weekday))"
        case 1: return "Morgen Nacht (\(weekday))"
        case 2: return "Übermorgen Nacht (\(weekday))"
        default: return "In \(dayIndex) Tagen (\(weekday))"
        }
    }
}

#Preview {
    ContentView()
}
