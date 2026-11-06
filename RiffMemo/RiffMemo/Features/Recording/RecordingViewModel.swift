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
import OSLog
import UIKit

/// ViewModel for the recording screen
@MainActor
@Observable
class RecordingViewModel {

    // MARK: - Published State

    var isRecording: Bool = false
    var currentDuration: TimeInterval = 0
    var audioLevel: Float = 0.0
    var waveformSamples: [Float] = []
    var detectedPitch: String?

    // Metronome settings for current recording
    var recordingBPM: Int?
    var recordingTimeSignature: String?

    // Error handling
    var errorMessage: String?
    var showError: Bool = false

    /// The take a call (or Siri, or an alarm) cut off, saved up to the cut (WAS-118). The
    /// Record screen shows the "A call stopped your recording" card while this is set.
    /// Starting the next take clears it.
    var interruptedTake: Recording?

    // MARK: - Dependencies

    private let audioRecorder: any AudioRecorderProtocol
    private let repository: RecordingRepository

    // MARK: - Private Properties

    private var durationTimer: Timer?
    private var recordingStartTime: Date?
    private var cancellables = Set<AnyCancellable>()
    private var waveformBuffer: [Float] = []
    private let maxWaveformSamples = 150
    private var samplesSinceLastUpdate: Int = 0
    private let samplesPerUpdate: Int = 2  // Update display every 2 samples (Shape is very efficient)

    // Set synchronously at the top of stopRecording(), before the async actor round-trip.
    // `isRecording` itself isn't flipped to false until that round-trip completes, so guarding
    // only on `isRecording` doesn't stop a rapid second tap from firing a concurrent stop that
    // reaches the actor after the first has already finished — producing a spurious "No
    // recording in progress" error even though the first tap's recording saved fine.
    private var isStoppingRecording = false

    // MARK: - Initialization

    init(
        audioRecorder: any AudioRecorderProtocol,
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

                // Set up waveform sample callback
                await audioRecorder.onWaveformSample = { [weak self] sample in
                    guard let self = self else { return }
                    Task { @MainActor [weak self] in
                        self?.addWaveformSample(sample)
                    }
                }

                // Set up recording-failure callback (e.g. disk full mid-recording) so the UI
                // reacts immediately instead of waiting for an explicit stop
                await audioRecorder.onRecordingFailed = { [weak self] error in
                    Task { @MainActor [weak self] in
                        self?.handleRecordingFailure(error)
                    }
                }

                try await audioRecorder.startRecording()
                isRecording = true
                interruptedTake = nil
                currentDuration = 0
                waveformBuffer.removeAll()
                waveformSamples = []
                samplesSinceLastUpdate = 0  // Reset throttle counter
                recordingStartTime = Date()
                startDurationTimer()
                Logger.audio.info("Recording started")
            } catch {
                errorMessage = "Failed to start recording: \(error.localizedDescription)"
                showError = true
                Logger.audio.error("Failed to start recording: [\(error.logCode, privacy: .public)] \(error)")
            }
        }
    }

    func stopRecording() {
        stopRecording(interrupted: false)
    }

    /// - Parameter interrupted: true when a call (or similar) cut the take (WAS-118). The take
    ///   is saved the same way, marked as interrupted, and offered on the card.
    private func stopRecording(interrupted: Bool) {
        guard isRecording, !isStoppingRecording else { return }
        isStoppingRecording = true
        stopDurationTimer()

        // A call can send the app to the background. Ask iOS for time to finish the save,
        // or a suspension between the stop and the save leaves an orphan file. The expiration
        // handler must end the task too: iOS kills an app whose background time runs out with
        // a task still open. If that happens, the next launch recovers the file instead.
        let backgroundTask = BackgroundTaskHandle(name: "Save cut take")

        Task {
            defer {
                isStoppingRecording = false
                backgroundTask.end()
            }
            do {
                let duration = currentDuration
                let recording = try await audioRecorder.stopRecording(
                    duration: duration,
                    recordedWithBPM: recordingBPM,
                    recordedWithTimeSignature: recordingTimeSignature
                )
                recording.wasInterrupted = interrupted

                try await repository.save(recording)
                if interrupted {
                    interruptedTake = recording
                }
                Logger.audio.info("Recording stopped and saved with duration: \(duration)s")

                // Only flip to "stopped" once the recording is durably persisted — a caller
                // reacting to isRecording==false (e.g. immediately switching to the Library tab,
                // which fetches its list once per visit with no live-refresh) must be able to
                // rely on the recording already being queryable, not racing an in-flight save.
                isRecording = false
                currentDuration = 0
                audioLevel = 0 // Reset audio level

                // Reset metronome settings for next recording
                recordingBPM = nil
                recordingTimeSignature = nil

                // Queue automatic analysis
                AudioAnalysisManager.shared.queueAnalysis(recording)
                Logger.audio.info("Queued automatic analysis for: \(recording.title)")

            } catch AudioError.writeFailed {
                // Already surfaced via the onRecordingFailed callback → handleRecordingFailure(_:),
                // which fires unconditionally whenever AudioRecordingManager records a write
                // failure. Don't clobber that more specific message with a generic one here —
                // just make sure recording state is cleared.
                isRecording = false
                Logger.audio.error("Stop reported a write failure already surfaced via onRecordingFailed")
            } catch {
                errorMessage = "Failed to save recording: \(error.localizedDescription)"
                showError = true
                isRecording = false // Make sure we stop recording even if save fails
                Logger.audio.error("Failed to stop recording: [\(error.logCode, privacy: .public)] \(error)")
            }
        }
    }

    /// Called when `AudioRecordingManager` tears down a recording mid-write (e.g. disk full).
    /// Surfaces the error immediately rather than waiting for the user to tap stop, and never
    /// calls `repository.save` — there's no usable Recording for a write that failed partway.
    private func handleRecordingFailure(_ error: Error) {
        guard isRecording else { return }

        stopDurationTimer()
        isRecording = false
        audioLevel = 0
        errorMessage = "Recording failed: \(error.localizedDescription)"
        showError = true

        Logger.audio.error("Recording failed mid-write: [\(error.logCode, privacy: .public)] \(error)")
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
        // The coordinator parses interruption and route-change notifications once and
        // publishes typed events (WAS-117).
        AudioSessionCoordinator.shared.events
            .sink { [weak self] event in
                self?.handleAudioSessionEvent(event)
            }
            .store(in: &cancellables)
    }

    /// Internal, not private, so tests can send events without the shared coordinator.
    func handleAudioSessionEvent(_ event: AudioSessionCoordinator.Event) {
        switch event {
        case .interruptionBegan:
            // Phone call, alarm, Siri. iOS has already stopped the input, so save what
            // was recorded up to the cut (WAS-118).
            if isRecording {
                Logger.audio.info("Audio interruption began - saving the take up to the cut")
                stopRecording(interrupted: true)
            }

        case .interruptionEnded(let shouldResume):
            if shouldResume {
                Logger.audio.info("Audio interruption ended - ready to record again")
            }

        case .audioDeviceLost:
            // Headphones unplugged, Bluetooth disconnected
            if isRecording {
                Logger.audio.info("Audio device disconnected - stopping recording")
                stopRecording()
            }

        case .audioDeviceAdded:
            Logger.audio.info("New audio device connected")
        }
    }
}

/// One `UIApplication` background task that ends exactly once: from the code that finishes
/// the work, or from iOS's expiration handler, whichever comes first (WAS-118).
@MainActor
private final class BackgroundTaskHandle {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            // iOS calls this on the main thread when the time is almost up.
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
