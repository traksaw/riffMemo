//
//  RecordingViewModel.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import Foundation
import Observation
import AVFoundation
import Combine

/// ViewModel for the recording screen
@MainActor
@Observable
class RecordingViewModel {

    // MARK: - Published State

    var isRecording: Bool = false
    var currentDuration: TimeInterval = 0
    var audioLevel: Float = 0.0
    var detectedPitch: String?

    // Error handling
    var errorMessage: String?
    var showError: Bool = false

    // MARK: - Dependencies

    private let audioRecorder: AudioRecordingManager
    private let repository: RecordingRepository

    // MARK: - Private Properties

    private var durationTimer: Timer?
    private var recordingStartTime: Date?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        audioRecorder: AudioRecordingManager,
        repository: RecordingRepository
    ) {
        self.audioRecorder = audioRecorder
        self.repository = repository
        setupAudioSessionObservers()
    }

    // MARK: - Actions

    func startRecording() {
        Task {
            do {
                // Set up audio level callback
                await audioRecorder.onAudioLevel = { [weak self] level in
                    Task { @MainActor in
                        self?.audioLevel = level
                    }
                }

                try await audioRecorder.startRecording()
                isRecording = true
                currentDuration = 0
                recordingStartTime = Date()
                startDurationTimer()
                Logger.info("Recording started", category: Logger.audio)
            } catch {
                errorMessage = "Failed to start recording: \(error.localizedDescription)"
                showError = true
                Logger.error("Failed to start recording: \(error)", category: Logger.audio)
            }
        }
    }

    func stopRecording() {
        stopDurationTimer()
        Task {
            do {
                let duration = currentDuration
                let recording = try await audioRecorder.stopRecording(duration: duration)
                isRecording = false
                currentDuration = 0
                audioLevel = 0 // Reset audio level
                try await repository.save(recording)
                Logger.info("Recording stopped and saved with duration: \(duration)s", category: Logger.audio)

                // Queue automatic analysis
                AudioAnalysisManager.shared.queueAnalysis(recording)
                Logger.info("Queued automatic analysis for: \(recording.title)", category: Logger.audio)

            } catch {
                errorMessage = "Failed to save recording: \(error.localizedDescription)"
                showError = true
                isRecording = false // Make sure we stop recording even if save fails
                Logger.error("Failed to stop recording: \(error)", category: Logger.audio)
            }
        }
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    // MARK: - Private Methods

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                guard let startTime = self.recordingStartTime else { return }
                self.currentDuration = Date().timeIntervalSince(startTime)
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
        recordingStartTime = nil
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
            // Interruption began (phone call, alarm, Siri, etc.)
            if isRecording {
                Logger.info("Audio interruption began - stopping recording", category: Logger.audio)
                stopRecording()
            }

        case .ended:
            // Interruption ended - could optionally resume, but for recording we don't auto-resume
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                return
            }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                Logger.info("Audio interruption ended - ready to record again", category: Logger.audio)
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
            // Headphones unplugged, Bluetooth disconnected during recording
            if isRecording {
                Logger.info("Audio device disconnected - stopping recording", category: Logger.audio)
                stopRecording()
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
