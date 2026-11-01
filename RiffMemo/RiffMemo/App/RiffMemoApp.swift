//
//  RiffMemoApp.swift
//  RiffMemo
//
//  Created by Waskar Paulino on 11/16/25.
//

import SwiftUI
import SwiftData

@main
struct RiffMemoApp: App {
    // Opening the SwiftData store can fail (corruption, failed migration, full
    // disk). WAS-121: show a recovery screen instead of crashing every launch.
    @State private var libraryStore = LibraryStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            switch libraryStore.state {
            case .loaded(let modelContainer):
                MainTabView(modelContainer: modelContainer)
                    .modelContainer(modelContainer)
            case .failed(let error):
                LibraryRecoveryView(
                    error: error,
                    failedRetryCount: libraryStore.failedRetryCount,
                    onRetry: libraryStore.retry
                )
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Transient causes (a prewarmed launch before first unlock, a full disk)
            // may have cleared by the time the app is actually in front of the user,
            // so retry silently on every activation, including the first one.
            if newPhase == .active {
                libraryStore.retryAutomatically()
            }
        }
    }
}
