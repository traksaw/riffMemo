//
//  RecordingDetailViewModelTests.swift
//  RiffMemoTests
//

import XCTest
@testable import RiffMemo

/// WAS-100: first ViewModel test coverage for `RecordingDetailViewModel` (Playback), using a
/// protocol-mocked `AudioPlaybackManager`. Follows `RecordingViewModelRaceTests.swift`'s
/// Task.sleep-based synchronization style since play()/pause()/stop()/seek(to:) all fire off an
/// internal detached `Task` rather than being directly awaitable.
@MainActor
final class RecordingDetailViewModelTests: XCTestCase {

    private func makeRecording(duration: TimeInterval = 120) -> Recording {
        Recording(
            title: "Test Recording",
            duration: duration,
            audioFileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        )
    }

    private func makeViewModel(duration: TimeInterval = 120) -> (RecordingDetailViewModel, MockAudioPlayer) {
        let player = MockAudioPlayer()
        let viewModel = RecordingDetailViewModel(recording: makeRecording(duration: duration), audioPlayer: player)
        return (viewModel, player)
    }

    func testTogglePlaybackStartsPlaybackWhenStopped() async throws {
        let (viewModel, player) = makeViewModel()

        viewModel.togglePlayback()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(viewModel.isPlaying)
        XCTAssertEqual(player.playCallCount, 1)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testTogglePlaybackPausesWhenPlaying() async throws {
        let (viewModel, player) = makeViewModel()
        viewModel.togglePlayback() // play
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(viewModel.isPlaying)

        viewModel.togglePlayback() // pause
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(viewModel.isPlaying)
        XCTAssertEqual(player.pauseCallCount, 1)
    }

    func testPlayFailureSetsErrorMessageAndClearsIsPlaying() async throws {
        let (viewModel, player) = makeViewModel()
        player.playError = PlaybackError.fileNotFound

        viewModel.play()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(viewModel.isPlaying)
        XCTAssertTrue(viewModel.showError)
        XCTAssertEqual(viewModel.errorMessage, "Failed to play recording: \(PlaybackError.fileNotFound.localizedDescription)")
    }

    func testStopResetsCurrentTimeAndIsPlaying() async throws {
        let (viewModel, player) = makeViewModel()
        viewModel.play()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(viewModel.isPlaying)

        viewModel.stop()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(viewModel.isPlaying)
        XCTAssertEqual(viewModel.currentTime, 0)
        XCTAssertEqual(player.stopCallCount, 1)
    }

    func testSeekUpdatesCurrentTimeAndForwardsToThePlayer() async throws {
        let (viewModel, player) = makeViewModel()

        viewModel.seek(to: 42)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(viewModel.currentTime, 42)
        XCTAssertEqual(player.lastSeekTime, 42)
        XCTAssertEqual(player.seekCallCount, 1)
    }
}
