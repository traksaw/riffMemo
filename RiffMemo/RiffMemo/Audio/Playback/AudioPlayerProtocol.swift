//
//  AudioPlayerProtocol.swift
//  RiffMemo
//

import Foundation

/// Narrow protocol over `AudioPlaybackManager`'s public surface, scoped to exactly what
/// `RecordingDetailViewModel` calls.
protocol AudioPlayerProtocol: AnyObject {
    func play(recording: Recording) async throws
    func pause() async
    func resume() async
    func stop() async
    func isPlaying() async -> Bool
    func currentTime() async -> TimeInterval
    func duration() async -> TimeInterval
    func seek(to time: TimeInterval) async
}

extension AudioPlaybackManager: AudioPlayerProtocol {}
