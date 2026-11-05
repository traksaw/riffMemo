//
//  AudioRecordingManager.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import Foundation
import AVFoundation
import OSLog

/// Manages audio recording using AVAudioEngine
actor AudioRecordingManager {

    // MARK: - Properties

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var isRecording = false
    private var inputNode: AVAudioInputNode?

    // Callback for real-time audio level updates
    nonisolated(unsafe) var onAudioLevel: (@Sendable (Float) -> Void)?

    // Callback for waveform sample updates (for live waveform visualization)
    nonisolated(unsafe) var onWaveformSample: (@Sendable (Float) -> Void)?

    // Callback fired when the render-thread tap hits an unrecoverable error (e.g. disk full)
    // and the recording is being torn down before the caller explicitly stopped it.
    nonisolated(unsafe) var onRecordingFailed: (@Sendable (Error) -> Void)?

    // Set by handleWriteFailure(_:) so stopRecording() can report the real cause instead of
    // just "not recording" if the caller stops after a mid-recording failure already tore
    // things down.
    private var failureError: Error?

    // Incremented on every startRecording(). Captured by the tap closure and passed back to
    // handleWriteFailure(_:) so a write-failure Task that was scheduled for one recording but
    // (due to actor scheduling delay) doesn't run until after that recording already ended and
    // a new one started can recognize it's stale and no-op, instead of tearing down the new
    // (unrelated, healthy) recording.
    private var recordingSession = 0

    // The audio session demand held while recording; returned in stopEngineAndTap().
    private var sessionToken: AudioSessionCoordinator.Token?

    // MARK: - Public Methods

    func startRecording() async throws {
        guard !isRecording else {
            throw AudioError.alreadyRecording
        }

        // Ask the coordinator for a session that covers recording (WAS-117). This is a
        // suspension point, so re-check the guard afterwards: a second start that raced in
        // while we waited must not leave two engines writing.
        let token = try await AudioSessionCoordinator.shared.acquire(.record)
        guard !isRecording, sessionToken == nil else {
            await AudioSessionCoordinator.shared.release(token)
            throw AudioError.alreadyRecording
        }
        sessionToken = token

        // Clear any failure state left over from a previous recording
        failureError = nil
        recordingSession += 1

        // Setup audio engine
        do {
            try setupAudioEngine(session: recordingSession)
        } catch {
            stopEngineAndTap()
            clearEngineState()
            throw error
        }

        isRecording = true
        Logger.audio.info("Audio recording started")
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
            // Whichever path (this one or handleWriteFailure(_:)) detects the failure last is
            // responsible for clearing engine state — idempotent, so safe even if the other
            // path already did it.
            clearEngineState()
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

        Logger.audio.info("Audio recording stopped - Duration: \(finalDuration)s, File size: \(fileSize) bytes")

        clearEngineState()

        return recording
    }

    // MARK: - Private Methods

    private func setupAudioEngine(session: Int) throws {
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

        // Install tap to write audio data and calculate levels
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            // Write audio to file. On failure, stop the recording rather than silently
            // producing a truncated file — hand off to the actor since tearing down
            // engine/tap/actor state must not happen directly from this render thread.
            do {
                try file.write(from: buffer)
            } catch {
                Task { await self?.handleWriteFailure(error, session: session) }
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
    ///
    /// `session` guards against a Task scheduling delay: if this doesn't run until after its
    /// recording already ended and a new one started (`recordingSession` incremented,
    /// `failureError` reset), a stale failure must not tear down the new, unrelated recording.
    ///
    /// `onRecordingFailed` fires unconditionally (once `failureError` is set) rather than only
    /// when this call is the one doing teardown — `stopRecording()` may have already claimed
    /// the stop and will itself throw `AudioError.writeFailed` from `failureError`, but it
    /// never re-invokes `onRecordingFailed` itself, so skipping the call here would drop the
    /// notification entirely in that interleaving.
    private func handleWriteFailure(_ error: Error, session: Int) {
        guard session == recordingSession else { return }
        guard failureError == nil else { return }
        failureError = error

        Logger.audio.error("Audio write failed, stopping recording: [\(error.logCode, privacy: .public)] \(error)")

        // If stopRecording() already claimed the stop (isRecording is already false), it will
        // pick up `failureError` itself after its flush sleep and clear state there — don't
        // redo the teardown.
        if isRecording {
            stopEngineAndTap()
            isRecording = false
            clearEngineState()
        }

        onRecordingFailed?(error)
    }

    /// Removes the tap, stops the engine and gives the audio session back. Safe to call
    /// regardless of whether any of them is active.
    private func stopEngineAndTap() {
        if let inputNode {
            inputNode.removeTap(onBus: 0)
        }
        audioEngine?.stop()
        releaseSession()
    }

    /// Returns this recording's session demand to the coordinator (WAS-117).
    ///
    /// Synchronous on purpose: `handleWriteFailure(_:session:)` relies on running without a
    /// suspension point, so the release hops to the main actor in its own task. The engine
    /// is already stopped, so the session can deactivate safely whenever that task runs.
    private func releaseSession() {
        guard let token = sessionToken else { return }
        sessionToken = nil
        Task { @MainActor in AudioSessionCoordinator.shared.release(token) }
    }

    /// Clears engine-related state so the next recording starts clean.
    private func clearEngineState() {
        audioEngine = nil
        audioFile = nil
        inputNode = nil
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
