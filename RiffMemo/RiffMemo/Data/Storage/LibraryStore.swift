//
//  LibraryStore.swift
//  RiffMemo
//

import Foundation
import Observation
import SwiftData

/// Owns opening the SwiftData library. WAS-121: a failed `ModelContainer` used to
/// `fatalError`, which crashed every launch until the user deleted the app (and every
/// take with it). Now a failure is captured as state so the UI can offer Retry and an
/// audio export instead. This type never deletes or resets the store on its own.
@MainActor
@Observable
final class LibraryStore {
    enum State {
        case loaded(ModelContainer)
        case failed(any Error)
    }

    private(set) var state: State
    private let makeContainer: () throws -> ModelContainer

    init(makeContainer: @escaping () throws -> ModelContainer = LibraryStore.makeDefaultContainer) {
        self.makeContainer = makeContainer
        self.state = Self.open(using: makeContainer)
    }

    /// Tries to open the store again (e.g. after the device frees space or unlocks).
    func retry() {
        state = Self.open(using: makeContainer)
    }

    private static func open(using makeContainer: () throws -> ModelContainer) -> State {
        do {
            return .loaded(try makeContainer())
        } catch {
            Logger.error("Failed to open library store: \(error)", category: Logger.data)
            return .failed(error)
        }
    }

    nonisolated static func makeDefaultContainer() throws -> ModelContainer {
        // WAS-51 added the iCloud/CloudKit entitlement so Recording's schema
        // could be verified as CloudKit-compatible, but sync itself isn't
        // live yet. SwiftData auto-enables CloudKit sync whenever the
        // entitlement is present and no configuration says otherwise, so
        // this stays local-only until sync is deliberately turned on.
        let configuration = ModelConfiguration(cloudKitDatabase: .none)
        return try ModelContainer(
            for: Schema(versionedSchema: RiffMemoSchemaV1.self),
            migrationPlan: RiffMemoMigrationPlan.self,
            configurations: configuration
        )
    }
}
