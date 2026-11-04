//
//  AudioPlaybackManager.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import Foundation
import AVFoundation
import OSLog

/// Manages audio playback using AVAudioPlayer
actor AudioPlaybackManager {

    // MARK: - Properties

    private var audioPlayer: AVAudioPlayer?
    private var currentRecording: Recording?

    // The audio session demand held while a player exists (WAS-117). Released on stop,
    // on a failed start, and when the take plays to its end.
    private var sessionToken: AudioSessionCoordinator.Token?
    private var finishObserver: PlaybackFinishObserver?

    // MARK: - Public Methods

    func play(recording: Recording) async throws {
        // Stop current playback if any. Keep the session demand: the next take reuses it.
        audioPlayer?.stop()
        audioPlayer = nil

        // Ask the coordinator for a session that covers playback (WAS-117).
        if sessionToken == nil {
            sessionToken = try await AudioSessionCoordinator.shared.acquire(.play)
        }

        // Verify the file exists before attempting to play
        guard FileManager.default.fileExists(atPath: recording.audioFileURL.path) else {
            Logger.audio.error("Audio file not found at path: \(recording.audioFileURL.path)")
            await releaseSession()
            throw PlaybackError.fileNotFound
        }

        // Create audio player
        do {
            let player = try AVAudioPlayer(contentsOf: recording.audioFileURL)
            let observer = PlaybackFinishObserver { [weak self] in
                Task { await self?.playbackFinished() }
            }
            player.delegate = observer
            player.prepareToPlay()

            // Verify the player is ready
            guard player.play() else {
                Logger.audio.error("Failed to start playback for: \(recording.title)")
                throw PlaybackError.playbackFailed
            }

            audioPlayer = player
            finishObserver = observer
            currentRecording = recording

            Logger.audio.info("Started playback for: \(recording.title)")
        } catch let error as NSError {
            Logger.audio.error("Failed to create audio player: [\(error.logCode, privacy: .public)] \(error)")
            await releaseSession()
            throw error
        }
    }

    func pause() async {
        audioPlayer?.pause()
        Logger.audio.info("Paused playback")
    }

    func resume() async {
        audioPlayer?.play()
        Logger.audio.info("Resumed playback")
    }

    func stop() async {
        audioPlayer?.stop()
        audioPlayer = nil
        finishObserver = nil
        currentRecording = nil
        await releaseSession()
        Logger.audio.info("Stopped playback")
    }

    func isPlaying() async -> Bool {
        return audioPlayer?.isPlaying ?? false
    }

    func currentTime() async -> TimeInterval {
        return audioPlayer?.currentTime ?? 0
    }

    func duration() async -> TimeInterval {
        return audioPlayer?.duration ?? 0
    }

    func seek(to time: TimeInterval) async {
        audioPlayer?.currentTime = time
    }

    // MARK: - Private Methods

    /// A take played to its end. Give the session back so Music can resume.
    private func playbackFinished() async {
        guard let player = audioPlayer, !player.isPlaying else { return }
        audioPlayer = nil
        finishObserver = nil
        currentRecording = nil
        await releaseSession()
        Logger.audio.info("Playback finished")
    }

    private func releaseSession() async {
        guard let token = sessionToken else { return }
        sessionToken = nil
        await AudioSessionCoordinator.shared.release(token)
    }
}

// MARK: - PlaybackFinishObserver

/// `AVAudioPlayer` reports the end of a take only through its delegate, which must be an
/// `NSObject`. An actor can't be one, so this small object forwards the callback.
nonisolated final class PlaybackFinishObserver: NSObject, AVAudioPlayerDelegate, Sendable {
    private let onFinish: @Sendable () -> Void

    init(onFinish: @escaping @Sendable () -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}

// MARK: - PlaybackError

enum PlaybackError: LocalizedError {
    case fileNotFound
    case playbackFailed
    case invalidAudioFile

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Audio file not found"
        case .playbackFailed:
            return "Failed to start playback"
        case .invalidAudioFile:
            return "Invalid or corrupted audio file"
        }
    }
}
