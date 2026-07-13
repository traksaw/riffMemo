//
//  MockAudioRecorder.swift
//  RiffMemoTests
//

import Foundation
@testable import RiffMemo

/// Test double for `AudioRecorderProtocol`. Lets `RecordingViewModel` tests drive
/// start/stop/failure behavior deterministically without a real `AVAudioEngine`.
final class MockAudioRecorder: AudioRecorderProtocol, @unchecked Sendable {
    var onAudioLevel: (@Sendable (Float) -> Void)?
    var onFrequencyData: (@Sendable ([Float]) -> Void)?
    var onWaveformSample: (@Sendable (Float) -> Void)?
    var onRecordingFailed: (@Sendable (Error) -> Void)?

    private(set) var startRecordingCallCount = 0
    private(set) var stopRecordingCallCount = 0

    /// If set, startRecording() throws this instead of succeeding.
    var startRecordingError: Error?
    /// If set, stopRecording() throws this instead of returning `recordingToReturn`.
    var stopRecordingError: Error?
    var recordingToReturn: Recording?

    /// Invoked at the start of stopRecording(), before it throws/returns — lets a test fire
    /// `onRecordingFailed` synchronously, modeling handleWriteFailure(_:) notifying the caller
    /// before AudioRecordingManager.stopRecording() itself observes `failureError` and throws.
    var stopRecordingSideEffect: (() -> Void)?

    func startRecording() async throws {
        startRecordingCallCount += 1
        if let startRecordingError {
            throw startRecordingError
        }
    }

    func stopRecording(duration: TimeInterval, recordedWithBPM: Int?, recordedWithTimeSignature: String?) async throws -> Recording {
        stopRecordingCallCount += 1
        stopRecordingSideEffect?()
        // Give whatever the side effect scheduled (e.g. onRecordingFailed's `Task { @MainActor
        // in ... }` hop) a chance to run before we return/throw — mirrors the real
        // AudioRecordingManager's genuine actor-boundary suspension here, which this mock
        // otherwise has no actor of its own to reproduce.
        await Task.yield()
        if let stopRecordingError {
            throw stopRecordingError
        }
        return recordingToReturn ?? Recording(
            title: "Mock Recording",
            duration: duration,
            audioFileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        )
    }
}
