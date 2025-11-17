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
    var frequencyMagnitudes: [Float] = []
    var waveformSamples: [Float] = []
    var detectedPitch: String?

    // Metronome settings for current recording
    var recordingBPM: Int?
    var recordingTimeSignature: String?

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
    private var waveformBuffer: [Float] = []
    private let maxWaveformSamples = 150
    private var samplesSinceLastUpdate: Int = 0
    private let samplesPerUpdate: Int = 2  // Update display every 2 samples (Shape is very efficient)

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
                    guard let self = self else { return }
                    Task { @MainActor [weak self] in
                        self?.audioLevel = level
                    }
                }

                // Set up frequency data callback
                await audioRecorder.onFrequencyData = { [weak self] frequencies in
                    guard let self = self else { return }
                    Task { @MainActor [weak self] in
                        self?.frequencyMagnitudes = frequencies
                    }
                }

                // Set up waveform sample callback
                await audioRecorder.onWaveformSample = { [weak self] sample in
                    guard let self = self else { return }
                    Task { @MainActor [weak self] in
                        self?.addWaveformSample(sample)
                    }
                }

                try await audioRecorder.startRecording()
                isRecording = true
                currentDuration = 0
                waveformBuffer.removeAll()
                waveformSamples = []
                samplesSinceLastUpdate = 0  // Reset throttle counter
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
                let recording = try await audioRecorder.stopRecording(
                    duration: duration,
                    recordedWithBPM: recordingBPM,
                    recordedWithTimeSignature: recordingTimeSignature
                )
                isRecording = false
                currentDuration = 0
                audioLevel = 0 // Reset audio level

                // Reset metronome settings for next recording
                recordingBPM = nil
                recordingTimeSignature = nil

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

    private func addWaveformSample(_ sample: Float) {
        waveformBuffer.append(sample)

        // Keep only the most recent samples
        if waveformBuffer.count > maxWaveformSamples {
            waveformBuffer.removeFirst(waveformBuffer.count - maxWaveformSamples)
        }

        // Throttle UI updates for optimal performance (Shape is very efficient)
        samplesSinceLastUpdate += 1

        if samplesSinceLastUpdate >= samplesPerUpdate {
            // Update published samples - SwiftUI Shape will animate smoothly
            waveformSamples = Array(waveformBuffer)

            // Reset counter
            samplesSinceLastUpdate = 0
        }
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
