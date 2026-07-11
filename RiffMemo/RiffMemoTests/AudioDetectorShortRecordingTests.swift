//
//  AudioDetectorShortRecordingTests.swift
//  RiffMemoTests
//

import XCTest
import AVFoundation
@testable import RiffMemo

/// Regression coverage for WAS-48: recordings shorter than a detector's frame
/// size used to produce a negative `numFrames`, which traps unconditionally
/// in Swift (negative array count / negative range).
final class AudioDetectorShortRecordingTests: XCTestCase {

    private func makeShortAudioFile(frameCount: AVAudioFrameCount) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        try file.write(from: buffer)
        return url
    }

    func testBPMDetectorDoesNotCrashOnShortRecording() async throws {
        // ~11ms at 44.1kHz — well below BPM's 2048-sample frame size.
        let url = try makeShortAudioFile(frameCount: 500)
        let bpm = try await BPMDetector().detectBPM(from: url)
        XCTAssertNil(bpm)
    }

    func testKeyDetectorDoesNotCrashOnShortRecording() async throws {
        // ~11ms at 44.1kHz — well below Key's 4096-sample frame size.
        let url = try makeShortAudioFile(frameCount: 500)
        let key = try await KeyDetector().detectKey(from: url)
        XCTAssertNil(key)
    }

    // MARK: - WAS-53 follow-up: oversized/corrupted frameCount used to abort the process
    // (AVAudioPCMBuffer's internal size math overflows unsigned 32-bit arithmetic and
    // throws a C++ exception Swift can't catch) instead of throwing a Swift error.

    func testAudioBufferSafetyAllowsNormalFrameCount() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        XCTAssertFalse(AudioBufferSafety.exceedsMaxBufferSize(frameCount: 44100 * 60 * 5, format: format))
    }

    func testAudioBufferSafetyRejectsOversizedFrameCount() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        XCTAssertTrue(AudioBufferSafety.exceedsMaxBufferSize(frameCount: AVAudioFrameCount.max, format: format))
    }

    private func makeDummyRecording(title: String, duration: TimeInterval) -> Recording {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        return Recording(title: title, duration: duration, audioFileURL: url)
    }

    @MainActor
    func testQueueAnalysisSkipsRecordingsBelowMinimumDuration() {
        let recording = makeDummyRecording(title: "Too short", duration: 0.05)

        let manager = AudioAnalysisManager.shared
        let countBefore = manager.queueCount
        manager.queueAnalysis(recording)

        XCTAssertEqual(manager.queueCount, countBefore, "Recording below minimumAnalyzableDuration should not be queued")
    }

    @MainActor
    func testQueueAnalysisAcceptsRecordingsAtOrAboveMinimumDuration() {
        let recording = makeDummyRecording(title: "Long enough", duration: AudioAnalysisManager.minimumAnalyzableDuration)

        let manager = AudioAnalysisManager.shared
        let countBefore = manager.queueCount
        manager.queueAnalysis(recording)

        XCTAssertEqual(manager.queueCount, countBefore + 1, "Recording at/above minimumAnalyzableDuration should be queued")
    }

    @MainActor
    func testQueueBatchAnalysisFiltersOutRecordingsBelowMinimumDuration() {
        let tooShort = makeDummyRecording(title: "Too short", duration: 0.05)
        let longEnough = makeDummyRecording(title: "Long enough", duration: AudioAnalysisManager.minimumAnalyzableDuration)

        let manager = AudioAnalysisManager.shared
        let countBefore = manager.queueCount
        manager.queueBatchAnalysis([tooShort, longEnough])

        XCTAssertEqual(manager.queueCount, countBefore + 1, "Only the recording at/above minimumAnalyzableDuration should be queued")
    }
}
