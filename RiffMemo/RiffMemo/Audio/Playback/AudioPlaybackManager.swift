//
//  AudioPlaybackManager.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import Foundation
import AVFoundation

/// Manages audio playback using AVAudioPlayer
actor AudioPlaybackManager {

    // MARK: - Properties

    private var audioPlayer: AVAudioPlayer?
    private var currentRecording: Recording?

    // MARK: - Public Methods

    func play(recording: Recording) async throws {
        // Stop current playback if any
        audioPlayer?.stop()

        // Setup audio session for playback
        try setupAudioSession()

        // Verify the file exists before attempting to play
        guard FileManager.default.fileExists(atPath: recording.audioFileURL.path) else {
            Logger.error("Audio file not found at path: \(recording.audioFileURL.path)", category: Logger.audio)
            throw PlaybackError.fileNotFound
        }

        // Create audio player
        do {
            let player = try AVAudioPlayer(contentsOf: recording.audioFileURL)
            player.prepareToPlay()

            // Verify the player is ready
            guard player.play() else {
                Logger.error("Failed to start playback for: \(recording.title)", category: Logger.audio)
                throw PlaybackError.playbackFailed
            }

            audioPlayer = player
            currentRecording = recording

            Logger.info("Started playback for: \(recording.title)", category: Logger.audio)
        } catch let error as NSError {
            Logger.error("Failed to create audio player: \(error.localizedDescription) (Code: \(error.code))", category: Logger.audio)
            throw error
        }
    }

    func pause() async {
        audioPlayer?.pause()
        Logger.info("Paused playback", category: Logger.audio)
    }

    func resume() async {
        audioPlayer?.play()
        Logger.info("Resumed playback", category: Logger.audio)
    }

    func stop() async {
        audioPlayer?.stop()
        audioPlayer = nil
        currentRecording = nil
        Logger.info("Stopped playback", category: Logger.audio)
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

    private func setupAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
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
