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
    var isPlayingReturnValue = false
    var currentTimeReturnValue: TimeInterval = 0
    var durationReturnValue: TimeInterval = 0

    func play(recording: Recording) async throws {
        playCallCount += 1
        lastPlayedRecording = recording
        if let playError {
            throw playError
        }
        isPlayingReturnValue = true
    }

    func pause() async {
        pauseCallCount += 1
        isPlayingReturnValue = false
    }

    func resume() async {
        resumeCallCount += 1
        isPlayingReturnValue = true
    }

    func stop() async {
        stopCallCount += 1
        isPlayingReturnValue = false
    }

    func isPlaying() async -> Bool {
        isPlayingReturnValue
    }

    func currentTime() async -> TimeInterval {
        currentTimeReturnValue
    }

    func duration() async -> TimeInterval {
        durationReturnValue
    }

    func seek(to time: TimeInterval) async {
        seekCallCount += 1
        lastSeekTime = time
        currentTimeReturnValue = time
    }
}
