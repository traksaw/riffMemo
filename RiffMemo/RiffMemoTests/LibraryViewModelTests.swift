//
//  LibraryViewModelTests.swift
//  RiffMemoTests
//

import XCTest
import SwiftData
@testable import RiffMemo

/// WAS-59: LibraryViewModel now owns bulk-delete and rename so LibraryView can't
/// reach past it into the repository or mutate `recording.title` directly.
///
/// Deiniting a `SwiftDataRecordingRepository` (a @MainActor class from the app
/// module, deallocated across the @testable boundary) crashes on this
/// Xcode 26.1.1 / Swift 6.2.1 toolchain — see RecordingRepositoryDeleteTests
/// for the full explanation. Tests below leak the container/repository/view
/// model to route around it.
@MainActor
final class LibraryViewModelTests: XCTestCase {

    private static var leakedToAvoidToolchainDeinitCrash: [Any] = []

    var viewModel: LibraryViewModel!
    var createdFileURLs: [URL] = []

    override func setUpWithError() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Recording.self, configurations: configuration)
        let repository = SwiftDataRecordingRepository(modelContext: container.mainContext)
        let viewModel = LibraryViewModel(repository: repository)
        Self.leakedToAvoidToolchainDeinitCrash.append(container)
        Self.leakedToAvoidToolchainDeinitCrash.append(repository)
        Self.leakedToAvoidToolchainDeinitCrash.append(viewModel)
        self.viewModel = viewModel
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
    private func makeRecordingWithFile(title: String = "Test") throws -> Recording {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WAS59-\(UUID().uuidString).caf")
        try Data("fake audio".utf8).write(to: url)
        createdFileURLs.append(url)
        return Recording(title: title, duration: 1, audioFileURL: url)
    }

    func testDeleteRecordingsWithIDsOnlyDeletesSelected() async throws {
        let keep = try makeRecordingWithFile(title: "Keep")
        let remove = try makeRecordingWithFile(title: "Remove")
        try await viewModel.saveForTest(keep)
        try await viewModel.saveForTest(remove)
        await viewModel.loadRecordings()

        await viewModel.deleteRecordings(withIDs: [remove.id])

        XCTAssertEqual(viewModel.recordings.map(\.title), ["Keep"])
    }

    func testDeleteRecordingsWithEmptyIDsIsNoOp() async throws {
        let recording = try makeRecordingWithFile()
        try await viewModel.saveForTest(recording)
        await viewModel.loadRecordings()

        await viewModel.deleteRecordings(withIDs: [])

        XCTAssertEqual(viewModel.recordings.count, 1)
    }

    func testRenameRecordingUpdatesTitle() async throws {
        let recording = try makeRecordingWithFile(title: "Old Title")
        try await viewModel.saveForTest(recording)

        await viewModel.renameRecording(recording, to: "New Title")

        XCTAssertEqual(recording.title, "New Title")
    }

    func testRenameRecordingIgnoresEmptyTitle() async throws {
        let recording = try makeRecordingWithFile(title: "Keep Me")

        await viewModel.renameRecording(recording, to: "")

        XCTAssertEqual(recording.title, "Keep Me")
    }
}
