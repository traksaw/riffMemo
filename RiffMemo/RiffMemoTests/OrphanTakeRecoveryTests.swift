//
//  OrphanTakeRecoveryTests.swift
//  RiffMemoTests
//

import AVFoundation
import XCTest
@testable import RiffMemo

/// WAS-118: when iOS kills the app mid-take, the audio file is on disk but no `Recording`
/// row names it. The next launch turns that file into a saved take instead of losing it.
@MainActor
final class OrphanTakeRecoveryTests: XCTestCase {

    private var directory: URL!
    private var repository: MockRecordingRepository!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WAS118-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        repository = MockRecordingRepository()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!

    /// Writes `frames` of silence to a new CAF file, the way `AudioRecordingManager` does.
    @discardableResult
    private func writeTake(named name: String, frames: AVAudioFrameCount) throws -> URL {
        let url = directory.appendingPathComponent(name)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        if frames > 0 {
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
            buffer.frameLength = frames
            try file.write(from: buffer)
        }
        return url
    }

    // MARK: - Finding orphans

    func testFilesWithoutARowAreOrphans() {
        let known = directory.appendingPathComponent("recording_A.caf")
        let orphan = directory.appendingPathComponent("recording_B.caf")

        let orphans = OrphanTakeRecovery.orphans(in: [known, orphan], knownFilenames: ["recording_A.caf"])

        XCTAssertEqual(orphans, [orphan])
    }

    // MARK: - Recovering

    func testAnOrphanBecomesAnInterruptedTakeWithItsRealDuration() async throws {
        try writeTake(named: "recording_orphan.caf", frames: 96_000)  // 2 s at 48 kHz

        let recovered = await OrphanTakeRecovery.recover(audioDirectory: directory, repository: repository)

        XCTAssertEqual(recovered.count, 1)
        let take = try XCTUnwrap(repository.savedRecordings.first)
        XCTAssertEqual(take.audioFilename, "recording_orphan.caf")
        XCTAssertEqual(take.duration, 2.0, accuracy: 0.01)
        XCTAssertTrue(take.wasInterrupted)
        XCTAssertEqual(take.title, OrphanTakeRecovery.recoveredTitle)
    }

    func testATakeThatAlreadyHasARowIsLeftAlone() async throws {
        let url = try writeTake(named: "recording_saved.caf", frames: 48_000)
        try await repository.save(Recording(title: "Saved", duration: 1, audioFileURL: url))

        let recovered = await OrphanTakeRecovery.recover(audioDirectory: directory, repository: repository)

        XCTAssertTrue(recovered.isEmpty)
        XCTAssertEqual(repository.savedRecordings.count, 1)
    }

    /// A kill right after Record leaves a file with no audio in it. There is nothing to keep.
    func testAnEmptyOrphanIsRemovedInsteadOfSaved() async throws {
        let url = try writeTake(named: "recording_empty.caf", frames: 0)

        let recovered = await OrphanTakeRecovery.recover(audioDirectory: directory, repository: repository)

        XCTAssertTrue(recovered.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    /// A forced kill never closes the file, so its header is never finished. Copying the file
    /// while the writer still has it open gives exactly what a kill leaves on disk.
    func testATakeCutOffByAKillIsStillReadable() async throws {
        let livePath = directory.appendingPathComponent("live.caf")
        let writer = try AVAudioFile(forWriting: livePath, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000)!
        buffer.frameLength = 48_000
        try writer.write(from: buffer)
        try FileManager.default.copyItem(
            at: livePath,
            to: directory.appendingPathComponent("recording_killed.caf")
        )
        withExtendedLifetime(writer) {}
        try FileManager.default.removeItem(at: livePath)

        let recovered = await OrphanTakeRecovery.recover(audioDirectory: directory, repository: repository)

        let take = try XCTUnwrap(recovered.first)
        XCTAssertEqual(take.duration, 1.0, accuracy: 0.1)
    }

    /// A file that is not readable audio is kept on disk. The WAS-121 audio export can still
    /// reach it, so deleting it could lose a take.
    func testAnUnreadableOrphanIsKeptOnDisk() async throws {
        let url = directory.appendingPathComponent("recording_garbage.caf")
        try Data("not audio".utf8).write(to: url)

        let recovered = await OrphanTakeRecovery.recover(audioDirectory: directory, repository: repository)

        XCTAssertTrue(recovered.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
