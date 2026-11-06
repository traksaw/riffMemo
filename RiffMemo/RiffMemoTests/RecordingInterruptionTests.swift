//
//  RecordingInterruptionTests.swift
//  RiffMemoTests
//

import XCTest
@testable import RiffMemo

/// WAS-118: a call (or Siri, or an alarm) cuts the take. Everything up to the cut is saved,
/// the take is marked as interrupted, and the Record screen offers to continue.
@MainActor
final class RecordingInterruptionTests: XCTestCase {

    private var recorder: MockAudioRecorder!
    private var repository: MockRecordingRepository!
    private var viewModel: RecordingViewModel!

    override func setUp() async throws {
        recorder = MockAudioRecorder()
        repository = MockRecordingRepository()
        viewModel = RecordingViewModel(audioRecorder: recorder, repository: repository)
    }

    /// Without this, iOS suspends the app when the screen locks, and the take stops there.
    func testTheAppKeepsRecordingInTheBackground() {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        XCTAssertEqual(modes?.contains("audio"), true)
    }

    private func startAndSettle() async throws {
        viewModel.startRecording()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(viewModel.isRecording)
    }

    func testInterruptionSavesTheTakeAndMarksItInterrupted() async throws {
        try await startAndSettle()

        viewModel.handleAudioSessionEvent(.interruptionBegan)
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertFalse(viewModel.isRecording)
        XCTAssertEqual(repository.savedRecordings.count, 1)
        XCTAssertEqual(repository.savedRecordings.first?.wasInterrupted, true)
    }

    func testInterruptionShowsTheCardForTheSavedTake() async throws {
        try await startAndSettle()

        viewModel.handleAudioSessionEvent(.interruptionBegan)
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(viewModel.interruptedTake?.id, repository.savedRecordings.first?.id)
    }

    func testAStopTheUserTapsIsNotMarkedInterrupted() async throws {
        try await startAndSettle()

        viewModel.stopRecording()
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(repository.savedRecordings.first?.wasInterrupted, false)
        XCTAssertNil(viewModel.interruptedTake)
    }

    func testInterruptionWhileIdleDoesNothing() async throws {
        viewModel.handleAudioSessionEvent(.interruptionBegan)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(recorder.stopRecordingCallCount, 0)
        XCTAssertNil(viewModel.interruptedTake)
    }

    /// "Continue as a new take" starts a normal new take, so the card must go away.
    func testStartingANewTakeClearsTheCard() async throws {
        try await startAndSettle()
        viewModel.handleAudioSessionEvent(.interruptionBegan)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNotNil(viewModel.interruptedTake)

        viewModel.startRecording()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(viewModel.interruptedTake)
        XCTAssertTrue(viewModel.isRecording)
    }
}
