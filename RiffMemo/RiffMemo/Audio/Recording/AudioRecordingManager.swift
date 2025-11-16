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

    func stopRecording() async throws -> Recording {
        guard isRecording else {
            throw AudioError.notRecording
        }

        audioEngine?.stop()
        isRecording = false

        // Create recording object
        guard let audioFile = audioFile else {
            throw AudioError.noAudioFile
        }

        let recording = Recording(
            title: "New Recording",
            duration: 0, // TODO: Calculate from audio file
            audioFileURL: audioFile.url
        )

        Logger.info("Audio recording stopped", category: Logger.audio)
        return recording
    }

    // MARK: - Private Methods

    private func setupAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
        try session.setActive(true)
    }

    private func setupAudioEngine() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        // Configure audio format
        let format = inputNode.outputFormat(forBus: 0)

        // Create audio file
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFileName = "recording_\(UUID().uuidString).caf"
        let audioFileURL = documentsPath.appendingPathComponent(audioFileName)

        let file = try AVAudioFile(forWriting: audioFileURL, settings: format.settings)
        audioFile = file

        // Install tap to write audio data
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            try? file.write(from: buffer)
        }

        try engine.start()
        self.audioEngine = engine
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
