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

    private func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Recording.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
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
            return try self.makeInMemoryContainer()
        }
        guard case .failed = store.state else { return XCTFail("First attempt should fail") }

        store.retry()

        guard case .loaded = store.state else { return XCTFail("Retry should load the container") }
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(store.failedRetryCount, 0)

        // Once loaded, neither kind of retry may reopen the store.
        store.retry()
        store.retryAutomatically()
        XCTAssertEqual(attempts, 2)
    }

    func testFailedRetriesAreCounted() {
        let store = LibraryStore { throw StoreOpenFailure() }
        XCTAssertEqual(store.failedRetryCount, 0, "The launch attempt is not a retry")

        store.retry()
        store.retry()

        XCTAssertEqual(store.failedRetryCount, 2)
    }

    func testAutomaticRetryLoadsWithoutCountingAsAFailedRetry() throws {
        var attempts = 0
        let store = LibraryStore {
            attempts += 1
            if attempts <= 2 { throw StoreOpenFailure() }
            return try self.makeInMemoryContainer()
        }

        store.retryAutomatically()
        XCTAssertEqual(store.failedRetryCount, 0, "Silent retries must never show \"still can't open\"")

        store.retryAutomatically()
        guard case .loaded = store.state else { return XCTFail("Automatic retry should load once the cause clears") }
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
        store.retry()
        store.retryAutomatically()

        guard case .failed = store.state else { return XCTFail("A corrupted store should fail to open") }
        XCTAssertEqual(try Data(contentsOf: storeURL), garbage, "The store must never be deleted or rewritten automatically")
    }

    func testDefaultStoreURLMatchesTheConfigurationSwiftDataOpens() {
        XCTAssertEqual(LibraryStore.defaultStoreURL, LibraryStore.defaultConfiguration.url)
        XCTAssertEqual(LibraryStore.defaultStoreURL.lastPathComponent, "default.store")
    }

    // MARK: - AudioRecovery: finding files

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

    // MARK: - AudioRecovery: staging

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
            audioFiles: sources,
            in: stagingDirectory,
            timeZone: TimeZone(identifier: "UTC")!
        )

        XCTAssertEqual(staged.files.map(\.lastPathComponent), [
            "RiffMemo 2026-10-31 at 21.04.07.caf",
            "RiffMemo 2026-10-31 at 21.04.07 (2).caf",
            "RiffMemo 2026-10-31 at 21.05.07.caf"
        ])
        XCTAssertEqual(staged.audioCount, 3)
        XCTAssertFalse(staged.includesLibraryBackup)
        for (source, stagedURL) in zip(sources, staged.files) {
            XCTAssertEqual(try Data(contentsOf: stagedURL), try Data(contentsOf: source))
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "Originals must never be moved")
        }
    }

    func testStageForExportClearsPreviousStagingRun() throws {
        let source = tempDirectory.appendingPathComponent("recording_A.caf")
        try Data([0x01]).write(to: source)
        let stagingDirectory = tempDirectory.appendingPathComponent("staging", isDirectory: true)

        _ = try AudioRecovery.stageForExport(audioFiles: [source], in: stagingDirectory)
        let second = try AudioRecovery.stageForExport(audioFiles: [source], in: stagingDirectory)

        let contents = try FileManager.default.contentsOfDirectory(atPath: stagingDirectory.path)
        XCTAssertEqual(contents, second.files.map(\.lastPathComponent), "A second export must not pick up \" (2)\" duplicates from the first")
    }

    func testClearStagingRemovesStagedEntriesButNotOriginals() throws {
        let source = tempDirectory.appendingPathComponent("recording_A.caf")
        try Data([0x01]).write(to: source)
        let stagingDirectory = tempDirectory.appendingPathComponent("staging", isDirectory: true)
        _ = try AudioRecovery.stageForExport(audioFiles: [source], in: stagingDirectory)

        AudioRecovery.clearStaging(in: stagingDirectory)

        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingDirectory.path))
        XCTAssertEqual(try Data(contentsOf: source), Data([0x01]), "Removing a hard link must not touch the original take")
    }

    func testOneUnreadableTakeDoesNotBlockTheRest() throws {
        let good = tempDirectory.appendingPathComponent("recording_A.caf")
        try Data([0x01]).write(to: good)
        // Listed but gone by the time staging runs: link and copy both fail.
        let vanished = tempDirectory.appendingPathComponent("recording_B.caf")

        let staged = try AudioRecovery.stageForExport(
            audioFiles: [good, vanished],
            in: tempDirectory.appendingPathComponent("staging", isDirectory: true)
        )

        XCTAssertEqual(staged.audioCount, 1)
        XCTAssertEqual(staged.files.count, 1)
        XCTAssertEqual(staged.skippedFiles, ["recording_B.caf"])
    }

    func testLibraryBackupKeepsSQLiteSidecarNamesPaired() throws {
        let storeURL = tempDirectory.appendingPathComponent("default.store")
        try Data("db".utf8).write(to: storeURL)
        try Data("wal".utf8).write(to: URL(fileURLWithPath: storeURL.path + "-wal"))
        // No -shm on disk: it must be skipped, not reported as a failure.

        let libraryFiles = AudioRecovery.libraryStoreFiles(storeURL: storeURL)
        XCTAssertEqual(libraryFiles.map(\.lastPathComponent), ["default.store", "default.store-wal"])

        let staged = try AudioRecovery.stageForExport(
            audioFiles: [],
            libraryFiles: libraryFiles,
            in: tempDirectory.appendingPathComponent("staging", isDirectory: true)
        )

        XCTAssertTrue(staged.includesLibraryBackup)
        XCTAssertEqual(staged.audioCount, 0)
        XCTAssertEqual(staged.files.map(\.lastPathComponent), [
            "RiffMemo Library Backup.store",
            "RiffMemo Library Backup.store-wal"
        ])
        XCTAssertEqual(try Data(contentsOf: staged.files[1]), Data("wal".utf8))
        XCTAssertTrue(staged.skippedFiles.isEmpty)
    }

    func testLibraryBackupIsAllOrNothing() throws {
        let storeURL = tempDirectory.appendingPathComponent("default.store")
        try Data("db".utf8).write(to: storeURL)
        // A WAL that can't be staged: shipping the store without it would silently drop recent edits.
        let missingWAL = URL(fileURLWithPath: storeURL.path + "-wal")

        let staged = try AudioRecovery.stageForExport(
            audioFiles: [],
            libraryFiles: [storeURL, missingWAL],
            in: tempDirectory.appendingPathComponent("staging", isDirectory: true)
        )

        XCTAssertFalse(staged.includesLibraryBackup)
        XCTAssertTrue(staged.files.isEmpty)
        XCTAssertEqual(staged.skippedFiles, ["default.store-wal"])
    }

    // MARK: - Export summary

    func testExportSummaryMentionsBackupAndSkippedFiles() {
        var staged = AudioRecovery.StagedExport()
        staged.audioCount = 2
        staged.includesLibraryBackup = true
        staged.skippedFiles = ["recording_B.caf"]

        let summary = LibraryRecoveryView.exportSummary(for: staged)

        XCTAssertTrue(summary.contains("2 audio takes"))
        XCTAssertTrue(summary.contains(AudioRecovery.libraryBackupBaseName))
        XCTAssertTrue(summary.contains("recording_B.caf"))
    }
}
