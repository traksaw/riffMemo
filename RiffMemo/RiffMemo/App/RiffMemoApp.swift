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
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Transient causes (device locked, disk full) may have cleared while the
            // user was away, so retry automatically on return. Only from .background,
            // not the launch-time .inactive → .active, which would retry immediately.
            if oldPhase == .background && newPhase == .active {
                libraryStore.retry()
            }
        }
    }
}
