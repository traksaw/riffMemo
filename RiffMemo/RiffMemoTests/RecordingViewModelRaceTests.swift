//
//  RecordingViewModelRaceTests.swift
//  RiffMemoTests
//

import XCTest
@testable import RiffMemo

/// WAS-55 follow-up: exercises the race-condition fixes found by the code-review pass, using
/// the AudioRecorderProtocol/RecordingRepository mocks the original test file's "FUTURE
/// IMPROVEMENTS" note called for. These previously had zero test coverage — the fixes could
/// have silently regressed without anything catching it.
@MainActor
final class RecordingViewModelRaceTests: XCTestCase {

    private func makeViewModel() -> (RecordingViewModel, MockAudioRecorder, MockRecordingRepository) {
        let recorder = MockAudioRecorder()
        let repository = MockRecordingRepository()
        let viewModel = RecordingViewModel(audioRecorder: recorder, repository: repository)
        return (viewModel, recorder, repository)
    }

    func testStartThenStopSavesExactlyOneRecording() async throws {
        let (viewModel, recorder, repository) = makeViewModel()

        viewModel.startRecording()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(viewModel.isRecording)
        XCTAssertEqual(recorder.startRecordingCallCount, 1)

        viewModel.stopRecording()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(viewModel.isRecording)
        XCTAssertEqual(recorder.stopRecordingCallCount, 1)
        XCTAssertEqual(repository.savedRecordings.count, 1)
        XCTAssertNil(viewModel.errorMessage)
    }

    /// Regression guard: `stopRecording()`'s `isRecording` guard alone doesn't close the
    /// double-stop race, since `isRecording` isn't flipped to `false` until the actor
    /// round-trip completes. The fix added a synchronous `isStoppingRecording` flag set before
    /// that round-trip starts — verified here by calling stopRecording() twice back-to-back
    /// (before either has a chance to complete) and confirming the recorder only saw one call.
    /// Root cause of the intermittent "recording never appears in Library" UI test failure
    /// (testDeletingRecordingRemovesItFromLibrary / testWaveformScrubbingTracksFingerAbsolutePosition):
    /// `isRecording` used to flip to `false` — which drives the "Tap to Record" text the UI
    /// tests treat as their synchronization signal — BEFORE `repository.save(_:)` completed.
    /// `LibraryView` fetches its list once per tab visit with no live-refresh, so a caller
    /// (a real user, or a UI test) that reacts to `isRecording == false` by immediately
    /// switching to Library can race the still-in-flight save and permanently miss the row —
    /// not just see it late. `isRecording` must not become `false` until the recording is
    /// durably persisted.
    func testIsRecordingStaysTrueUntilTheRecordingIsPersisted() async throws {
        let (viewModel, _, repository) = makeViewModel()
        repository.saveDelayNanoseconds = 200_000_000 // simulate a slow SwiftData write

        viewModel.startRecording()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(viewModel.isRecording)

        viewModel.stopRecording()
        try await Task.sleep(nanoseconds: 50_000_000) // well before the simulated save completes

        XCTAssertTrue(viewModel.isRecording, "isRecording must stay true while repository.save(_:) is still in flight")
        XCTAssertTrue(repository.savedRecordings.isEmpty)

        try await Task.sleep(nanoseconds: 300_000_000) // let the save finish
        XCTAssertFalse(viewModel.isRecording)
        XCTAssertEqual(repository.savedRecordings.count, 1)
    }

    func testDoubleStopOnlyInvokesTheRecorderOnce() async throws {
        let (viewModel, recorder, _) = makeViewModel()

        viewModel.startRecording()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(viewModel.isRecording)

        viewModel.stopRecording()
        viewModel.stopRecording() // Rapid second tap, synchronously before the first completes.
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(recorder.stopRecordingCallCount, 1, "The second call should have been suppressed by isStoppingRecording")
        XCTAssertFalse(viewModel.isRecording)
    }

    /// Regression guard: a write failure right as the user taps stop used to let both the
    /// `onRecordingFailed` callback (→ handleRecordingFailure) and stopRecording()'s own catch
    /// block set competing error messages for the same failure. stopRecording() now defers to
    /// the callback's message for `AudioError.writeFailed` instead of overwriting it.
    func testWriteFailureDuringStopDoesNotOverwriteTheMoreSpecificMessage() async throws {
        let (viewModel, recorder, repository) = makeViewModel()

        viewModel.startRecording()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(viewModel.isRecording)

        let underlying = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "disk full"])
        recorder.stopRecordingError = AudioError.writeFailed(underlying: underlying)
        recorder.stopRecordingSideEffect = { [weak recorder] in
            recorder?.onRecordingFailed?(underlying)
        }

        viewModel.stopRecording()
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertFalse(viewModel.isRecording)
        XCTAssertEqual(viewModel.errorMessage, "Recording failed: \(underlying.localizedDescription)")
        XCTAssertTrue(viewModel.showError)
        XCTAssertTrue(repository.savedRecordings.isEmpty, "A write failure must never produce a saved Recording")
    }
}
