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
        List {
            if let today = cache.days.first {
                Section("Heute Nacht (\(germanWeekday(for: today.date)))") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        NightTimelineView(day: today)
                            .padding(.vertical, 6)
                    }
                }
            }

            Section("Nächste 6 Tage") {
                ForEach(cache.days.prefix(6), id: \.date) { day in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(germanWeekday(for: day.date))
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            if let illumination = day.moonIlluminationPercent {
                                Label("\(illumination)%", systemImage: NightTimelineView.moonPhaseSymbolName(for: day))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if let avgCloud = day.averageNightCloudPercent {
                                Text("\(Int(avgCloud))% Ø")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        NightTimelineView(day: day, style: .compact)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func germanWeekday(for date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "de_DE")))
    }
}

#Preview {
    ContentView()
}
