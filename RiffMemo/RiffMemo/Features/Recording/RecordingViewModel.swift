//
//  RecordingViewModel.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import Foundation
import Observation

/// ViewModel for the recording screen
@MainActor
@Observable
class RecordingViewModel {

    // MARK: - Published State

    var isRecording: Bool = false
    var currentDuration: TimeInterval = 0
    var audioLevel: Float = 0.0
    var detectedPitch: String?

    // MARK: - Dependencies

    private let audioRecorder: AudioRecordingManager
    private let repository: RecordingRepository

    // MARK: - Initialization

    init(
        audioRecorder: AudioRecordingManager,
        repository: RecordingRepository
    ) {
        self.audioRecorder = audioRecorder
        self.repository = repository
    }

    // MARK: - Actions

    func startRecording() {
        Task {
            do {
                try await audioRecorder.startRecording()
                isRecording = true
                Logger.info("Recording started", category: Logger.audio)
            } catch {
                Logger.error("Failed to start recording: \(error)", category: Logger.audio)
            }
        }
    }

    func stopRecording() {
        Task {
            do {
                let recording = try await audioRecorder.stopRecording()
                isRecording = false
                try await repository.save(recording)
                Logger.info("Recording stopped and saved", category: Logger.audio)
            } catch {
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
}
