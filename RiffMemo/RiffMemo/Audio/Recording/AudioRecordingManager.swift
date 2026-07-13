//
//  AudioRecordingManager.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import Foundation
import AVFoundation

/// Manages audio recording using AVAudioEngine
actor AudioRecordingManager {

    // MARK: - Properties

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var isRecording = false
    private var inputNode: AVAudioInputNode?

    // Callback for real-time audio level updates
    nonisolated(unsafe) var onAudioLevel: (@Sendable (Float) -> Void)?

    // Callback for real-time frequency data updates
    nonisolated(unsafe) var onFrequencyData: (@Sendable ([Float]) -> Void)?

    // Callback for waveform sample updates (for live waveform visualization)
    nonisolated(unsafe) var onWaveformSample: (@Sendable (Float) -> Void)?

    // Frequency analyzer
    private var frequencyAnalyzer: FrequencyAnalyzer?

    // Callback fired when the render-thread tap hits an unrecoverable error (e.g. disk full)
    // and the recording is being torn down before the caller explicitly stopped it.
    nonisolated(unsafe) var onRecordingFailed: (@Sendable (Error) -> Void)?

    // Set by handleWriteFailure(_:) so stopRecording() can report the real cause instead of
    // just "not recording" if the caller stops after a mid-recording failure already tore
    // things down.
    private var failureError: Error?

    // MARK: - Public Methods

    func startRecording() async throws {
        guard !isRecording else {
            throw AudioError.alreadyRecording
        }

        // Clear any failure state left over from a previous recording
        failureError = nil

        // Setup audio session
        try setupAudioSession()

        // Initialize frequency analyzer
        self.frequencyAnalyzer = FrequencyAnalyzer(bandCount: 32)

        // Setup audio engine
        try setupAudioEngine()

        isRecording = true
        Logger.info("Audio recording started", category: Logger.audio)
    }

    func stopRecording(duration: TimeInterval, recordedWithBPM: Int? = nil, recordedWithTimeSignature: String? = nil) async throws -> Recording {
        guard isRecording else {
            // If a write failure already tore the recording down, report the real cause
            // instead of a bare "not recording" — and never fall through to build a
            // Recording for what may be a truncated file.
            if let failureError {
                throw AudioError.writeFailed(underlying: failureError)
            }
            throw AudioError.notRecording
        }

        stopEngineAndTap()
        isRecording = false

        // Give the file system a moment to flush all buffers to disk. This is a suspension
        // point, so a write failure on an in-flight buffer can still run handleWriteFailure(_:)
        // and set `failureError` while we're asleep — re-check it below before trusting the
        // file. (handleWriteFailure(_:) treats `failureError` — not `isRecording` — as its
        // idempotency guard specifically so this race can't silently no-op.)
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        if let failureError {
            throw AudioError.writeFailed(underlying: failureError)
        }

        // Create recording object
        guard let audioFile = audioFile else {
            throw AudioError.noAudioFile
        }

        // Get file size for debugging
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioFile.url.path)[.size] as? Int64) ?? 0

        // Calculate actual duration from audio file
        let calculatedDuration = Double(audioFile.length) / audioFile.fileFormat.sampleRate

        // Use the more accurate duration (prefer calculated from file)
        let finalDuration = calculatedDuration > 0 ? calculatedDuration : duration

        let recording = Recording(
            title: "New Recording",
            duration: finalDuration,
            audioFileURL: audioFile.url,
            fileSize: fileSize,
            recordedWithBPM: recordedWithBPM,
            recordedWithTimeSignature: recordedWithTimeSignature
        )

        Logger.info("Audio recording stopped - Duration: \(finalDuration)s, File size: \(fileSize) bytes", category: Logger.audio)

        clearEngineState()

        return recording
    }

    // MARK: - Private Methods

    private func setupAudioSession() throws {
        let session = AVAudioSession.sharedInstance()

        // Check if audio is currently playing (metronome running)
        let isAudioPlaying = session.isOtherAudioPlaying || session.secondaryAudioShouldBeSilencedHint

        // Only reconfigure if session is not already compatible
        // This prevents audio glitches when metronome is already playing
        if !isAudioPlaying {
            // No audio playing - safe to reconfigure
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try session.setActive(true)
        } else {
            // Audio is playing - only reconfigure if category is wrong
            if session.category != .playAndRecord {
                try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            }
            // Don't call setActive(true) - it's already active and would cause reconfiguration
        }
    }

    private func setupAudioEngine() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        // Store reference to input node so we can remove tap later
        self.inputNode = inputNode

        // Configure audio format
        let format = inputNode.outputFormat(forBus: 0)

        // Create audio file
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFileName = "recording_\(UUID().uuidString).caf"
        let audioFileURL = documentsPath.appendingPathComponent(audioFileName)

        let file = try AVAudioFile(forWriting: audioFileURL, settings: format.settings)
        audioFile = file

        // Captured as a local `let` — a plain class reference — rather than reading
        // `self.frequencyAnalyzer` from inside the tap closure below. `frequencyAnalyzer` is
        // an actor-isolated stored property; `startRecording()` sets it immediately before
        // calling `setupAudioEngine()`, so snapshotting it here is safe, and it keeps the
        // render-thread closure from touching actor-isolated state on every callback.
        //
        // IMPORTANT — ordering guarantee: this tap closure runs on Core Audio's real-time
        // thread, entirely outside this actor's serial executor. It is only safe to use
        // `analyzer` here because `stopRecording()` calls `inputNode.removeTap(onBus:)`
        // BEFORE it nils out `frequencyAnalyzer` (and before the engine/file/inputNode are
        // torn down). That ordering is what prevents this closure from running concurrently
        // with actor-side cleanup — it is not enforced by the type system, so if
        // `stopRecording()` is ever refactored, this ordering must be preserved.
        let analyzer = self.frequencyAnalyzer

        // Install tap to write audio data AND calculate levels AND analyze frequencies
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            // Write audio to file. On failure, stop the recording rather than silently
            // producing a truncated file — hand off to the actor since tearing down
            // engine/tap/actor state must not happen directly from this render thread.
            do {
                try file.write(from: buffer)
            } catch {
                Task { await self?.handleWriteFailure(error) }
                return
            }

            // Calculate and send audio level
            if let level = self?.calculateLevel(from: buffer) {
                self?.onAudioLevel?(level)
                // Also send to waveform (same value, for live waveform bars)
                if let callback = self?.onWaveformSample {
                    callback(level)
                }
            }

            // Analyze and send frequency data
            if let analyzer {
                analyzer.analyze(buffer: buffer)
                self?.onFrequencyData?(analyzer.frequencyMagnitudes)
            }
        }

        try engine.start()
        self.audioEngine = engine
    }

    /// Tears down an in-progress recording after an unrecoverable write failure, and notifies
    /// the caller via `onRecordingFailed` so the UI can react immediately instead of waiting
    /// for an explicit `stopRecording()` call.
    ///
    /// Actor-isolated, so this always runs serialized with `startRecording()`/`stopRecording()`.
    /// Idempotency is guarded on `failureError` (not `isRecording`): `stopRecording()` sets
    /// `isRecording = false` before its own flush `await`, and if this method used `isRecording`
    /// as its guard, a write failure that lands during that suspension would see
    /// `isRecording == false` and silently no-op — dropping `failureError` and letting
    /// `stopRecording()` build a Recording from a truncated file. Guarding on `failureError`
    /// instead means the failure is always recorded exactly once, regardless of which path
    /// reaches the actor first.
    private func handleWriteFailure(_ error: Error) {
        guard failureError == nil else { return }
        failureError = error

        Logger.error("Audio write failed, stopping recording: \(error)", category: Logger.audio)

        // If stopRecording() already claimed the stop (isRecording is already false), it will
        // pick up `failureError` itself after its flush sleep — don't re-teardown or re-notify.
        let wasRecording = isRecording
        if wasRecording {
            stopEngineAndTap()
            isRecording = false
            clearEngineState()
        }

        if wasRecording {
            onRecordingFailed?(error)
        }
    }

    /// Removes the tap and stops the engine. Safe to call regardless of whether either is active.
    private func stopEngineAndTap() {
        if let inputNode {
            inputNode.removeTap(onBus: 0)
        }
        audioEngine?.stop()
    }

    /// Clears engine-related state so the next recording starts clean.
    private func clearEngineState() {
        audioEngine = nil
        audioFile = nil
        inputNode = nil
        frequencyAnalyzer = nil
    }

    private nonisolated func calculateLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }

        let channelDataValue = channelData.pointee
        let frameLength = Int(buffer.frameLength)

        // Calculate RMS (Root Mean Square) for more accurate level representation
        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelDataValue[i]
            sum += sample * sample // Square each sample
        }

        // Calculate RMS
        let rms = sqrt(sum / Float(frameLength))

        // Convert to decibels and normalize to 0-1 range
        // Reference level: -50 dB (quiet) to 0 dB (loud)
        let decibels = 20 * log10(rms)
        let normalizedLevel = max(0, min(1, (decibels + 50) / 50))

        return normalizedLevel
    }
}

// MARK: - AudioError

enum AudioError: LocalizedError {
    case alreadyRecording
    case notRecording
    case noAudioFile
    case setupFailed
    case writeFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "Recording is already in progress"
        case .notRecording:
            return "No recording in progress"
        case .noAudioFile:
            return "Audio file not found"
        case .setupFailed:
            return "Failed to setup audio engine"
        case .writeFailed(let underlying):
            return "Recording failed while writing audio data: \(underlying.localizedDescription)"
        }
    }
}
