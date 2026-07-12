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
///
/// Deiniting a `SwiftDataRecordingRepository` (a @MainActor class from the
/// app module, deallocated across the @testable boundary) crashes on this
/// Xcode 26.1.1 / Swift 6.2.1 toolchain with a libmalloc corruption in
/// `swift_task_deinitOnExecutorMainActorBackDeploy` — reproducible even with
/// an untouched checkout of RecordingRepository.swift and no calls into it,
/// so it's a toolchain bug, not something this fix introduced. Tests below
/// intentionally leak the container/repository (never let them deinit) to
/// route around it.
@MainActor
final class RecordingRepositoryDeleteTests: XCTestCase {

    private static var leakedToAvoidToolchainDeinitCrash: [Any] = []

    var repository: SwiftDataRecordingRepository!
    var createdFileURLs: [URL] = []

    override func setUpWithError() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Recording.self, configurations: configuration)
        let repository = SwiftDataRecordingRepository(modelContext: container.mainContext)
        Self.leakedToAvoidToolchainDeinitCrash.append(container)
        Self.leakedToAvoidToolchainDeinitCrash.append(repository)
        self.repository = repository
        createdFileURLs = []
    }

    override func tearDownWithError() throws {
        for url in createdFileURLs {
            try? FileManager.default.removeItem(at: url)
        }
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

    // NOTE: The restore-on-failed-save path (delete() moving the staged file
    // back to originalURL when modelContext.save() throws) is not covered by
    // an end-to-end test. Forcing a real SwiftData save failure deterministically
    // isn't reliably possible through the public API — a chmod-based sabotage
    // attempt on the store's directory was tried and discarded because SQLite's
    // WAL journaling doesn't need directory write access for an already-open
    // store, so the save silently succeeded instead of throwing. The two tests
    // above cover the primitive (stageAudioFileForDeletion) that the restore
    // path is built from; the restore call itself is a single FileManager
    // .moveItem in delete()'s catch block, verified by code review.
}
