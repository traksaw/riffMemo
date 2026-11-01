//
//  LibraryRecoveryTests.swift
//  RiffMemoTests
//

import XCTest
import SwiftData
@testable import RiffMemo

/// WAS-121: a store that can't be opened must surface as recoverable state,
/// not a crash, and the raw audio must still be findable for export.
@MainActor
final class LibraryRecoveryTests: XCTestCase {

    private struct StoreOpenFailure: Error {}

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WAS121-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: - LibraryStore

    func testFailedContainerProducesFailedStateInsteadOfCrashing() {
        let store = LibraryStore { throw StoreOpenFailure() }

        guard case .failed(let error) = store.state else {
            return XCTFail("Expected .failed, got \(store.state)")
        }
        XCTAssertTrue(error is StoreOpenFailure)
    }

    func testRetryLoadsTheContainerOnceItSucceeds() throws {
        var attempts = 0
        let store = LibraryStore {
            attempts += 1
            if attempts == 1 { throw StoreOpenFailure() }
            return try ModelContainer(
                for: Recording.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
        guard case .failed = store.state else { return XCTFail("First attempt should fail") }

        store.retry()

        guard case .loaded = store.state else { return XCTFail("Retry should load the container") }
        XCTAssertEqual(attempts, 2)
    }

    func testCorruptedStoreFileFailsWithoutDeletingIt() throws {
        let storeURL = tempDirectory.appendingPathComponent("corrupt.store")
        let garbage = Data("this is not a sqlite database".utf8)
        try garbage.write(to: storeURL)

        let store = LibraryStore {
            try ModelContainer(
                for: Schema(versionedSchema: RiffMemoSchemaV1.self),
                migrationPlan: RiffMemoMigrationPlan.self,
                configurations: ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
            )
        }

        guard case .failed = store.state else { return XCTFail("A corrupted store should fail to open") }
        XCTAssertEqual(try Data(contentsOf: storeURL), garbage, "The store must never be deleted or rewritten automatically")
    }

    // MARK: - AudioRecovery

    func testAudioFilesFindsEveryAudioFileAndSkipsEverythingElse() throws {
        let audioNames = ["recording_A.caf", "recording_B.caf", "imported.m4a", "bounce.wav"]
        for name in audioNames {
            try Data([0x00]).write(to: tempDirectory.appendingPathComponent(name))
        }
        try Data([0x00]).write(to: tempDirectory.appendingPathComponent("notes.txt"))
        try Data([0x00]).write(to: tempDirectory.appendingPathComponent(".hidden.caf"))
        try FileManager.default.createDirectory(
            at: tempDirectory.appendingPathComponent("folder.caf", isDirectory: true),
            withIntermediateDirectories: false
        )

        let found = try AudioRecovery.audioFiles(in: tempDirectory).map(\.lastPathComponent)

        XCTAssertEqual(found, audioNames.sorted())
    }

    func testStageForExportUsesDateNamesKeepsBytesAndLeavesOriginalsAlone() throws {
        let sourceDirectory = tempDirectory.appendingPathComponent("source", isDirectory: true)
        let stagingDirectory = tempDirectory.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)

        // 2026-10-31 21:04:07 UTC; two takes in the same second must not collide.
        let date = Date(timeIntervalSince1970: 1_793_480_647)
        var sources: [URL] = []
        for (index, name) in ["recording_A.caf", "recording_B.caf", "recording_C.caf"].enumerated() {
            let url = sourceDirectory.appendingPathComponent(name)
            try Data("take \(index)".utf8).write(to: url)
            let takeDate = index < 2 ? date : date.addingTimeInterval(60)
            try FileManager.default.setAttributes([.creationDate: takeDate], ofItemAtPath: url.path)
            sources.append(url)
        }

        let staged = try AudioRecovery.stageForExport(
            sources,
            in: stagingDirectory,
            timeZone: TimeZone(identifier: "UTC")!
        )

        XCTAssertEqual(staged.map(\.lastPathComponent), [
            "RiffMemo 2026-10-31 at 21.04.07.caf",
            "RiffMemo 2026-10-31 at 21.04.07 (2).caf",
            "RiffMemo 2026-10-31 at 21.05.07.caf"
        ])
        for (source, stagedURL) in zip(sources, staged) {
            XCTAssertEqual(try Data(contentsOf: stagedURL), try Data(contentsOf: source))
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "Originals must never be moved")
        }
    }

    func testStageForExportClearsPreviousStagingRun() throws {
        let source = tempDirectory.appendingPathComponent("recording_A.caf")
        try Data([0x01]).write(to: source)
        let stagingDirectory = tempDirectory.appendingPathComponent("staging", isDirectory: true)

        _ = try AudioRecovery.stageForExport([source], in: stagingDirectory)
        let second = try AudioRecovery.stageForExport([source], in: stagingDirectory)

        let contents = try FileManager.default.contentsOfDirectory(atPath: stagingDirectory.path)
        XCTAssertEqual(contents, second.map(\.lastPathComponent), "A second export must not pick up \" (2)\" duplicates from the first")
    }
}
