//
//  LibraryViewModel.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import Foundation
import Observation

/// ViewModel for the library screen
@MainActor
@Observable
class LibraryViewModel {

    // MARK: - Published State

    var recordings: [Recording] = []
    var searchText: String = ""
    var selectedFilter: RecordingFilter = .all
    var isGeneratingWaveforms: Bool = false
    var waveformProgress: Double = 0

    // MARK: - Dependencies

    let repository: RecordingRepository
    private let waveformGenerator = WaveformGenerator()

    // MARK: - Initialization

    init(repository: RecordingRepository) {
        self.repository = repository
    }

    // MARK: - Data Loading

    func loadRecordings() async {
        do {
            recordings = try await repository.fetchAll()
            Logger.info("Loaded \(recordings.count) recordings", category: Logger.data)
        } catch {
            Logger.error("Failed to load recordings: \(error)", category: Logger.data)
        }
    }

    // MARK: - Actions

    func deleteRecording(_ recording: Recording) async {
        do {
            try await repository.delete(recording)
            await loadRecordings()
            Logger.info("Deleted recording: \(recording.title)", category: Logger.data)
        } catch {
            Logger.error("Failed to delete recording: \(error)", category: Logger.data)
        }
    }

    func deleteAllRecordings() async {
        let count = recordings.count
        guard count > 0 else { return }

        Logger.info("Deleting all \(count) recordings", category: Logger.data)

        for recording in recordings {
            do {
                try await repository.delete(recording)
            } catch {
                Logger.error("Failed to delete recording \(recording.title): \(error)", category: Logger.data)
            }
        }

        await loadRecordings()
        Logger.info("Deleted all recordings", category: Logger.data)
    }

    func toggleFavorite(_ recording: Recording) async {
        recording.isFavorite.toggle()
        Logger.info("Toggled favorite for: \(recording.title)", category: Logger.data)
    }

    // MARK: - Batch Waveform Generation

    /// Generates waveforms for all recordings that don't have cached waveforms
    /// Uses background priority to avoid blocking UI
    func generateMissingWaveforms() async {
        let recordingsNeedingWaveforms = recordings.filter { $0.waveformData == nil }

        guard !recordingsNeedingWaveforms.isEmpty else {
            Logger.info("All recordings already have waveforms", category: Logger.audio)
            return
        }

        isGeneratingWaveforms = true
        waveformProgress = 0

        Logger.info("Generating waveforms for \(recordingsNeedingWaveforms.count) recordings", category: Logger.audio)

        for (index, recording) in recordingsNeedingWaveforms.enumerated() {
            do {
                // Generate with lower priority to not block UI
                let waveformData = try await waveformGenerator.generateWaveformData(
                    from: recording.audioFileURL,
                    targetSamples: 100 // Thumbnails use 100 samples
                )

                recording.waveformData = waveformData

                // Update progress
                waveformProgress = Double(index + 1) / Double(recordingsNeedingWaveforms.count)

                Logger.info("Generated waveform \(index + 1)/\(recordingsNeedingWaveforms.count)", category: Logger.audio)

            } catch {
                Logger.error("Failed to generate waveform for \(recording.title): \(error)", category: Logger.audio)
            }

            // Small delay to keep UI responsive
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        isGeneratingWaveforms = false
        waveformProgress = 0

        Logger.info("Batch waveform generation complete", category: Logger.audio)
    }

    /// Pre-generates waveforms for the first N recordings for instant display
    func preloadWaveforms(count: Int = 10) async {
        let recordingsToPreload = recordings
            .prefix(count)
            .filter { $0.waveformData == nil }

        guard !recordingsToPreload.isEmpty else { return }

        Logger.info("Preloading waveforms for \(recordingsToPreload.count) recordings", category: Logger.audio)

        for recording in recordingsToPreload {
            do {
                let waveformData = try await waveformGenerator.generateWaveformData(
                    from: recording.audioFileURL,
                    targetSamples: 100
                )
                recording.waveformData = waveformData
            } catch {
                Logger.error("Failed to preload waveform: \(error)", category: Logger.audio)
            }
        }
    }

    // MARK: - Analysis

    /// Analyzes all unanalyzed recordings
    func analyzeAll() {
        let unanalyzed = recordings.filter { $0.lastAnalyzedDate == nil }

        guard !unanalyzed.isEmpty else {
            Logger.info("All recordings already analyzed", category: Logger.audio)
            return
        }

        Logger.info("Queuing \(unanalyzed.count) recordings for analysis", category: Logger.audio)
        AudioAnalysisManager.shared.queueBatchAnalysis(unanalyzed)
    }

    /// Returns count of unanalyzed recordings
    var unanalyzedCount: Int {
        recordings.filter { $0.lastAnalyzedDate == nil }.count
    }
}

// MARK: - RecordingFilter

enum RecordingFilter {
    case all
    case favorites
    case recent
}
