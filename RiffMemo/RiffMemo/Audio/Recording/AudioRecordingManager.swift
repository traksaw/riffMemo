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

    // MARK: - Public Methods

    func startRecording() async throws {
        guard !isRecording else {
            throw AudioError.alreadyRecording
        }

        // Setup audio session
        try setupAudioSession()

        // Setup audio engine
        try setupAudioEngine()

        isRecording = true
        Logger.info("Audio recording started", category: Logger.audio)
    }

    func stopRecording(duration: TimeInterval, recordedWithBPM: Int? = nil, recordedWithTimeSignature: String? = nil) async throws -> Recording {
        guard isRecording else {
            throw AudioError.notRecording
        }

        // Remove tap from input node BEFORE stopping engine
        // This ensures audio data is properly flushed to file
        if let inputNode = inputNode {
            inputNode.removeTap(onBus: 0)
        }

        // Stop the engine
        audioEngine?.stop()
        isRecording = false

        // Give the file system a moment to flush all buffers to disk
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

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

        // Clean up references for next recording
        self.audioEngine = nil
        self.audioFile = nil
        self.inputNode = nil

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

        // Install tap to write audio data AND calculate levels
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            // Write audio to file
            try? file.write(from: buffer)

            // Calculate and send audio level
            if let level = self?.calculateLevel(from: buffer) {
                self?.onAudioLevel?(level)
            }
        }

        try engine.start()
        self.audioEngine = engine
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
        }
    }
}
