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
}
