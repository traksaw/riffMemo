//
//  RiffMemoApp.swift
//  RiffMemo
//
//  Created by Waskar Paulino on 11/16/25.
//

import SwiftUI
import CoreData

@main
struct RiffMemoApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
