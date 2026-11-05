//
//  RecordingDetailViewModel.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import Foundation
import Observation
import AVFoundation
import Combine
import OSLog

/// ViewModel for the recording detail screen with playback controls
@MainActor
@Observable
class RecordingDetailViewModel {

    // MARK: - Published State

    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0

    // Error handling
    var errorMessage: String?
    var showError: Bool = false

    // MARK: - Dependencies

    private let recording: Recording
    private let audioPlayer: any AudioPlayerProtocol
    private var playbackTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(recording: Recording, audioPlayer: any AudioPlayerProtocol) {
        self.recording = recording
        self.audioPlayer = audioPlayer
        self.duration = recording.duration
        setupAudioSessionObservers()
    }

    // MARK: - Actions

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        Task {
            do {
                if currentTime > 0 {
                    // Resume playback
                    await audioPlayer.resume()
                } else {
                    // Start new playback
                    try await audioPlayer.play(recording: recording)
                }
                isPlaying = true
                startPlaybackTimer()
                Logger.audio.info("Playback started")
            } catch {
                errorMessage = "Failed to play recording: \(error.localizedDescription)"
                showError = true
                isPlaying = false
                Logger.audio.error("Failed to play recording: [\(error.logCode, privacy: .public)] \(error)")
            }
        }
    }

    func pause() {
        Task {
            await audioPlayer.pause()
            isPlaying = false
            stopPlaybackTimer()
            Logger.audio.info("Playback paused")
        }
    }

    func stop() {
        Task {
            await audioPlayer.stop()
            isPlaying = false
            currentTime = 0
            stopPlaybackTimer()
            Logger.audio.info("Playback stopped")
        }
    }

    func seek(to time: TimeInterval) {
        Task {
            await audioPlayer.seek(to: time)
            currentTime = time
        }
    }

    // MARK: - Private Methods

    private func startPlaybackTimer() {
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                let stillPlaying = await self.audioPlayer.isPlaying()
                self.currentTime = await self.audioPlayer.currentTime()

                // A take that plays to its end stops by itself. The playback manager then
                // drops its player (WAS-117), so currentTime reads 0 and can never reach
                // duration. Ask whether it is still playing instead.
                if !stillPlaying || self.currentTime >= self.duration {
                    self.isPlaying = false
                    self.currentTime = 0
                    self.stopPlaybackTimer()
                }
            }
        }
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    // MARK: - Audio Session Handling

    private func setupAudioSessionObservers() {
        // The coordinator parses interruption and route-change notifications once and
        // publishes typed events (WAS-117).
        AudioSessionCoordinator.shared.events
            .sink { [weak self] event in
                self?.handleAudioSessionEvent(event)
            }
            .store(in: &cancellables)
    }

    private func handleAudioSessionEvent(_ event: AudioSessionCoordinator.Event) {
        switch event {
        case .interruptionBegan:
            // Phone call, alarm, Siri
            if isPlaying {
                Logger.audio.info("Audio interruption began - pausing playback")
                pause()
            }

        case .interruptionEnded(let shouldResume):
            if shouldResume {
                Logger.audio.info("Audio interruption ended - ready to resume playback")
            }

        case .audioDeviceLost:
            // Headphones unplugged, Bluetooth disconnected
            if isPlaying {
                Logger.audio.info("Audio device disconnected - pausing playback")
                pause()
            }

        case .audioDeviceAdded:
            Logger.audio.info("New audio device connected")
        }
    }
}
