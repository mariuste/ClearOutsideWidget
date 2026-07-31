//
//  Clear_Outside_WidgetApp.swift
//  Clear Outside Widget
//
//  Created by Marius Tetard on 30.07.26.
//

import SwiftUI

@main
struct Clear_Outside_WidgetApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BackgroundRefreshManager.register()
        BackgroundRefreshManager.requestNotificationAuthorization()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                BackgroundRefreshManager.scheduleNextRefresh()
            }
        }
    }
}
