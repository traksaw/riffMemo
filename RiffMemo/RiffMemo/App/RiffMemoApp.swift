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
            // WAS-51 added the iCloud/CloudKit entitlement so Recording's schema
            // could be verified as CloudKit-compatible, but sync itself isn't
            // live yet. SwiftData auto-enables CloudKit sync whenever the
            // entitlement is present and no configuration says otherwise, so
            // this stays local-only until sync is deliberately turned on.
            let configuration = ModelConfiguration(cloudKitDatabase: .none)
            modelContainer = try ModelContainer(
                for: Schema(versionedSchema: RiffMemoSchemaV1.self),
                migrationPlan: RiffMemoMigrationPlan.self,
                configurations: configuration
            )
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
