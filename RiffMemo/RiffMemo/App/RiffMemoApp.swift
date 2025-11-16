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
    // SwiftData container
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: Recording.self)
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView(modelContainer: modelContainer)
        }
        .modelContainer(modelContainer)
    }
}
