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

    var body: some Scene {
        WindowGroup {
            switch libraryStore.state {
            case .loaded(let modelContainer):
                MainTabView(modelContainer: modelContainer)
                    .modelContainer(modelContainer)
            case .failed(let error):
                LibraryRecoveryView(error: error, onRetry: libraryStore.retry)
            }
        }
    }
}
