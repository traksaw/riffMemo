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
    /// How many retries have failed since launch, so the UI can show that Retry
    /// actually ran instead of looking like a dead button.
    private(set) var failedRetryCount = 0
    private let makeContainer: () throws -> ModelContainer

    init(makeContainer: @escaping () throws -> ModelContainer = LibraryStore.makeLaunchContainer) {
        self.makeContainer = makeContainer
        self.state = Self.open(using: makeContainer)
    }

    /// Explicitly nonisolated: with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` the
    /// compiler routes this class's deinit through `swift_task_deinitOnExecutor`
    /// (iOS 18 back-deploy shim), which aborts with a libmalloc error when the object
    /// is released (seen from the test target on Xcode 26.1 and 27.1). The deinit does
    /// no main-actor work, so it doesn't need the hop.
    nonisolated deinit {}

    /// User-initiated retry (e.g. after the device frees space). A failure is counted
    /// so the UI can say so. No-op once the store has loaded.
    func retry() {
        guard case .failed = state else { return }
        state = Self.open(using: makeContainer)
        if case .failed = state {
            failedRetryCount += 1
        }
    }

    /// Silent retry for system events such as returning to the foreground: covers
    /// transient causes (a prewarmed launch before first unlock, a full disk that has
    /// since been cleared) without telling the user "still failing" for a retry they
    /// never asked for. No-op once the store has loaded.
    func retryAutomatically() {
        guard case .failed = state else { return }
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

    #if DEBUG
    /// Launch argument that forces the store to fail, so the recovery screen can
    /// be exercised by UI tests and on a device without corrupting real data.
    nonisolated static let simulateOpenFailureArgument = "-simulateLibraryOpenFailure"

    struct SimulatedOpenFailure: LocalizedError {
        var errorDescription: String? { "Simulated library open failure (\(LibraryStore.simulateOpenFailureArgument))." }
    }
    #endif

    nonisolated static func makeLaunchContainer() throws -> ModelContainer {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(simulateOpenFailureArgument) {
            throw SimulatedOpenFailure()
        }
        #endif
        return try makeDefaultContainer()
    }

    // WAS-51 added the iCloud/CloudKit entitlement so Recording's schema
    // could be verified as CloudKit-compatible, but sync itself isn't
    // live yet. SwiftData auto-enables CloudKit sync whenever the
    // entitlement is present and no configuration says otherwise, so
    // this stays local-only until sync is deliberately turned on.
    nonisolated static var defaultConfiguration: ModelConfiguration {
        ModelConfiguration(cloudKitDatabase: .none)
    }

    /// Where the store lives on disk, so recovery can back up the exact file
    /// SwiftData tries to open rather than a hard-coded guess.
    nonisolated static var defaultStoreURL: URL {
        defaultConfiguration.url
    }

    nonisolated static func makeDefaultContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: RiffMemoSchemaV1.self),
            migrationPlan: RiffMemoMigrationPlan.self,
            configurations: defaultConfiguration
        )
    }
}
