//
//  MockAudioPlayer.swift
//  RiffMemoTests
//

import Foundation
@testable import RiffMemo

/// Test double for `AudioPlayerProtocol`. Lets `RecordingDetailViewModel` tests drive
/// play/pause/stop/seek and the play-failure error path deterministically without a real
/// `AVAudioPlayer`.
final class MockAudioPlayer: AudioPlayerProtocol, @unchecked Sendable {
    private(set) var playCallCount = 0
    private(set) var pauseCallCount = 0
    private(set) var resumeCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var seekCallCount = 0
    private(set) var lastPlayedRecording: Recording?
    private(set) var lastSeekTime: TimeInterval?

    /// If set, play(recording:) throws this instead of succeeding.
    var playError: Error?
    var currentTimeReturnValue: TimeInterval = 0

    func play(recording: Recording) async throws {
        playCallCount += 1
        lastPlayedRecording = recording
        if let playError {
            throw playError
        }
    }

    func pause() async {
        pauseCallCount += 1
    }

    func resume() async {
        resumeCallCount += 1
    }

    func stop() async {
        stopCallCount += 1
    }

    func currentTime() async -> TimeInterval {
        currentTimeReturnValue
    }

    func seek(to time: TimeInterval) async {
        seekCallCount += 1
        lastSeekTime = time
        currentTimeReturnValue = time
    }
}
