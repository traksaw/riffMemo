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
    private let audioPlayer: AudioPlaybackManager
    private var playbackTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(recording: Recording, audioPlayer: AudioPlaybackManager) {
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
                Logger.info("Playback started", category: Logger.audio)
            } catch {
                errorMessage = "Failed to play recording: \(error.localizedDescription)"
                showError = true
                isPlaying = false
                Logger.error("Failed to play recording: \(error)", category: Logger.audio)
            }
        }
    }

    func pause() {
        Task {
            await audioPlayer.pause()
            isPlaying = false
            stopPlaybackTimer()
            Logger.info("Playback paused", category: Logger.audio)
        }
    }

    func stop() {
        Task {
            await audioPlayer.stop()
            isPlaying = false
            currentTime = 0
            stopPlaybackTimer()
            Logger.info("Playback stopped", category: Logger.audio)
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
                self.currentTime = await self.audioPlayer.currentTime()

                // Check if playback finished
                if self.currentTime >= self.duration {
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
        // Observe audio interruptions (phone calls, alarms, Siri, etc.)
        NotificationCenter.default
            .publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] notification in
                self?.handleInterruption(notification)
            }
            .store(in: &cancellables)

        // Observe audio route changes (headphones unplugged, Bluetooth disconnected)
        NotificationCenter.default
            .publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] notification in
                self?.handleRouteChange(notification)
            }
            .store(in: &cancellables)
    }

    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            // Interruption began - pause playback
            if isPlaying {
                Logger.info("Audio interruption began - pausing playback", category: Logger.audio)
                pause()
            }

        case .ended:
            // Interruption ended - could optionally resume
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                return
            }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                Logger.info("Audio interruption ended - ready to resume playback", category: Logger.audio)
                // Optionally auto-resume: play()
            }

        @unknown default:
            Logger.info("Unknown interruption type", category: Logger.audio)
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable:
            // Headphones unplugged - pause playback
            if isPlaying {
                Logger.info("Audio device disconnected - pausing playback", category: Logger.audio)
                pause()
            }

        case .newDeviceAvailable:
            Logger.info("New audio device connected", category: Logger.audio)

        case .routeConfigurationChange, .categoryChange, .override, .wakeFromSleep, .noSuitableRouteForCategory, .unknown:
            break

        @unknown default:
            break
        }
    }
}
