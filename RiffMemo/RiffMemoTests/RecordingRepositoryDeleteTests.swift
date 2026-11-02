//
//  RecordingRepositoryDeleteTests.swift
//  RiffMemoTests
//

import XCTest
import SwiftData
@testable import RiffMemo

/// WAS-50: RecordingRepository.delete(_:) must remove the underlying audio
/// file, not just the SwiftData row — otherwise every deletion (including
/// "delete all," which just loops over this method) leaks storage.
@MainActor
final class RecordingRepositoryDeleteTests: XCTestCase {

    var repository: SwiftDataRecordingRepository!
    /// Held for the whole test: a `ModelContext` does not keep its container alive,
    /// so a container that falls out of scope invalidates `mainContext`.
    var container: ModelContainer!
    var createdFileURLs: [URL] = []

    override func setUpWithError() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Recording.self, configurations: configuration)
        self.container = container
        let repository = SwiftDataRecordingRepository(modelContext: container.mainContext)
        self.repository = repository
        createdFileURLs = []
    }

    override func tearDownWithError() throws {
        for url in createdFileURLs {
            try? FileManager.default.removeItem(at: url)
        }

        // Release dependents before the container whose context they use.
        repository = nil
        container = nil
    }

    // Recording.audioFileURL always resolves against the real Documents
    // directory, so these tests write real files there rather than to a
    // temp/injectable location.
    private func makeRecordingWithFile() throws -> Recording {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WAS50-\(UUID().uuidString).caf")
        try Data("fake audio".utf8).write(to: url)
        createdFileURLs.append(url)
        return Recording(title: "Test", duration: 1, audioFileURL: url)
    }

    func testDeleteRemovesAudioFileFromDisk() async throws {
        let recording = try makeRecordingWithFile()
        try await repository.save(recording)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recording.audioFileURL.path))

        try await repository.delete(recording)

        XCTAssertFalse(FileManager.default.fileExists(atPath: recording.audioFileURL.path))
    }

    func testDeleteRemovesModelRow() async throws {
        let recording = try makeRecordingWithFile()
        try await repository.save(recording)

        try await repository.delete(recording)

        let fetched = try await repository.fetch(by: recording.id)
        XCTAssertNil(fetched)
    }

    func testDeleteWithAlreadyMissingFileDoesNotThrowAndStillRemovesRow() async throws {
        let recording = try makeRecordingWithFile()
        try await repository.save(recording)
        try FileManager.default.removeItem(at: recording.audioFileURL)

        try await repository.delete(recording)

        let fetched = try await repository.fetch(by: recording.id)
        XCTAssertNil(fetched)
    }

    func testDeletingAllLikeLibraryViewModelRemovesEveryAudioFile() async throws {
        let recordings = try [makeRecordingWithFile(), makeRecordingWithFile(), makeRecordingWithFile()]
        for recording in recordings {
            try await repository.save(recording)
        }

        for recording in recordings {
            try await repository.delete(recording)
        }

        for recording in recordings {
            XCTAssertFalse(FileManager.default.fileExists(atPath: recording.audioFileURL.path))
        }
    }

    // MARK: - Staging primitive (the two-phase move that makes delete's
    // failure handling possible)

    func testStageAudioFileForDeletionMovesFileOutOfPlace() throws {
        let recording = try makeRecordingWithFile()
        let originalURL = recording.audioFileURL

        let stagedURL = try repository.stageAudioFileForDeletion(at: originalURL)

        XCTAssertNotNil(stagedURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedURL!.path))
        if let stagedURL {
            createdFileURLs.append(stagedURL)
        }
    }

    func testStageAudioFileForDeletionReturnsNilWhenFileAlreadyMissing() throws {
        let missingURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WAS50-missing-\(UUID().uuidString).caf")

        let stagedURL = try repository.stageAudioFileForDeletion(at: missingURL)

        XCTAssertNil(stagedURL)
    }

    // MARK: - Restore on a failed DB save

    private struct InjectedSaveFailure: Error {}

    /// A chmod-based attempt to force a *real* SwiftData save failure was
    /// tried and discarded (SQLite's WAL journaling doesn't need directory
    /// write access for an already-open store, so the save silently
    /// succeeded instead of throwing). Injecting the save call itself is the
    /// reliable way to exercise this path deterministically.
    func testDeleteRestoresFileWhenDatabaseSaveFails() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Recording.self, configurations: configuration)

        let savingRepository = SwiftDataRecordingRepository(modelContext: container.mainContext)

        let recording = try makeRecordingWithFile()
        try await savingRepository.save(recording)

        let failingRepository = SwiftDataRecordingRepository(
            modelContext: container.mainContext,
            performSave: { throw InjectedSaveFailure() }
        )

        do {
            try await failingRepository.delete(recording)
            XCTFail("Expected delete to propagate the injected save failure")
        } catch is InjectedSaveFailure {
            // expected
        }

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: recording.audioFileURL.path),
            "Audio file should be restored after a failed DB save"
        )

        // container.mainContext still has the delete queued as an unsaved
        // pending change, which taints fetches on that same context. Verify
        // against a fresh context instead — the same thing a relaunched app
        // would see reading the actually-persisted store.
        let freshRepository = SwiftDataRecordingRepository(modelContext: ModelContext(container))

        let fetched = try await freshRepository.fetch(by: recording.id)
        XCTAssertNotNil(fetched, "DB row should still exist in the persisted store after a failed save")
    }
}
