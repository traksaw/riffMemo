//
//  LibraryViewModelTests.swift
//  RiffMemoTests
//

import XCTest
import SwiftData
@testable import RiffMemo

/// WAS-59: LibraryViewModel now owns bulk-delete and rename so LibraryView can't
/// reach past it into the repository or mutate `recording.title` directly.
@MainActor
final class LibraryViewModelTests: XCTestCase {

    var viewModel: LibraryViewModel!
    /// Held for the whole test: a `ModelContext` does not keep its container alive,
    /// so a container that falls out of scope invalidates `mainContext`.
    var container: ModelContainer!
    var createdFileURLs: [URL] = []

    override func setUpWithError() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Recording.self, configurations: configuration)
        self.container = container
        let repository = SwiftDataRecordingRepository(modelContext: container.mainContext)
        let viewModel = LibraryViewModel(repository: repository)
        self.viewModel = viewModel
        createdFileURLs = []
    }

    override func tearDownWithError() throws {
        for url in createdFileURLs {
            try? FileManager.default.removeItem(at: url)
        }

        // Release dependents before the container whose context they use.
        viewModel = nil
        container = nil
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
