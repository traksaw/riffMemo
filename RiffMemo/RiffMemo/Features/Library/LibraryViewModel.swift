//
//  LibraryViewModel.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import Foundation
import Observation
import OSLog

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

    /// Private so a View can never reach past the ViewModel to mutate persistence
    /// directly (WAS-59) — the `private` keyword is the enforcement: any View code
    /// that writes `viewModel.repository...` fails to compile. Route all data
    /// operations through ViewModel methods instead.
    private let repository: RecordingRepository
    private let waveformGenerator = WaveformGenerator()

    /// Explicitly nonisolated: with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` the
    /// compiler routes this class's deinit through `swift_task_deinitOnExecutor`
    /// (iOS 18 back-deploy shim), which aborts with a libmalloc error when the object
    /// is released (seen from the test target on Xcode 26.1 and 27.1). The deinit does
    /// no main-actor work, so it doesn't need the hop. Swift 6.1 (CI's Xcode 16.4) has no
    /// isolated deinits, so every deinit there is already nonisolated and the syntax
    /// doesn't compile.
    #if compiler(>=6.2)
    nonisolated deinit {}
    #endif

    #if DEBUG
    /// Test-only seam: lets LibraryViewModelTests save fixtures without
    /// making `repository` non-private for production code.
    func saveForTest(_ recording: Recording) async throws {
        try await repository.save(recording)
    }
    #endif

    // MARK: - Initialization

    init(repository: RecordingRepository) {
        self.repository = repository
    }

    // MARK: - Data Loading

    func loadRecordings() async {
        do {
            recordings = try await repository.fetchAll()
            Logger.data.info("Loaded \(self.recordings.count) recordings")
        } catch {
            Logger.data.error("Failed to load recordings: \(error)")
        }
    }

    // MARK: - Actions

    func deleteRecording(_ recording: Recording) async {
        do {
            try await repository.delete(recording)
            await loadRecordings()
            Logger.data.info("Deleted recording: \(recording.title)")
        } catch {
            Logger.data.error("Failed to delete recording: \(error)")
        }
    }

    func deleteAllRecordings() async {
        guard !recordings.isEmpty else { return }

        Logger.data.info("Deleting all \(self.recordings.count) recordings")
        await deleteRecordings(recordings)
        Logger.data.info("Deleted all recordings")
    }

    /// Deletes the recordings whose id is in `ids`. Used by the Library's
    /// multi-select "Delete" action; kept separate from `deleteAllRecordings`
    /// only because the two log different messages.
    func deleteRecordings(withIDs ids: Set<Recording.ID>) async {
        let recordingsToDelete = recordings.filter { ids.contains($0.id) }
        guard !recordingsToDelete.isEmpty else { return }

        Logger.data.info("Deleting \(recordingsToDelete.count) selected recordings")
        await deleteRecordings(recordingsToDelete)
        Logger.data.info("Deleted selected recordings")
    }

    private func deleteRecordings(_ recordingsToDelete: [Recording]) async {
        for recording in recordingsToDelete {
            do {
                try await repository.delete(recording)
            } catch {
                Logger.data.error("Failed to delete recording \(recording.title): \(error)")
            }
        }
        await loadRecordings()
    }

    /// Renames a recording through the repository (not a direct `recording.title =`
    /// mutation from a View) so the change is persisted via the same path CloudKit
    /// sync relies on (WAS-51).
    func renameRecording(_ recording: Recording, to newTitle: String) async {
        guard !newTitle.isEmpty else { return }
        recording.title = newTitle
        do {
            try await repository.update(recording)
            Logger.data.info("Renamed recording to: \(newTitle)")
        } catch {
            Logger.data.error("Failed to rename recording: \(error)")
        }
    }

    func toggleFavorite(_ recording: Recording) async {
        recording.isFavorite.toggle()
        Logger.data.info("Toggled favorite for: \(recording.title)")
    }

    // MARK: - Batch Waveform Generation

    /// Generates waveforms for all recordings that don't have cached waveforms
    /// Uses background priority to avoid blocking UI
    func generateMissingWaveforms() async {
        let recordingsNeedingWaveforms = recordings.filter { $0.waveformData == nil }

        guard !recordingsNeedingWaveforms.isEmpty else {
            Logger.audio.info("All recordings already have waveforms")
            return
        }

        isGeneratingWaveforms = true
        waveformProgress = 0

        Logger.audio.info("Generating waveforms for \(recordingsNeedingWaveforms.count) recordings")

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

                Logger.audio.info("Generated waveform \(index + 1)/\(recordingsNeedingWaveforms.count)")

            } catch {
                Logger.audio.error("Failed to generate waveform for \(recording.title): \(error)")
            }

            // Small delay to keep UI responsive
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        isGeneratingWaveforms = false
        waveformProgress = 0

        Logger.audio.info("Batch waveform generation complete")
    }

    /// Pre-generates waveforms for the first N recordings for instant display
    func preloadWaveforms(count: Int = 10) async {
        let recordingsToPreload = recordings
            .prefix(count)
            .filter { $0.waveformData == nil }

        guard !recordingsToPreload.isEmpty else { return }

        Logger.audio.info("Preloading waveforms for \(recordingsToPreload.count) recordings")

        for recording in recordingsToPreload {
            do {
                let waveformData = try await waveformGenerator.generateWaveformData(
                    from: recording.audioFileURL,
                    targetSamples: 100
                )
                recording.waveformData = waveformData
            } catch {
                Logger.audio.error("Failed to preload waveform: \(error)")
            }
        }
    }

    // MARK: - Analysis

    /// Analyzes all unanalyzed recordings
    func analyzeAll() {
        let unanalyzed = recordings.filter { $0.lastAnalyzedDate == nil }

        guard !unanalyzed.isEmpty else {
            Logger.audio.info("All recordings already analyzed")
            return
        }

        Logger.audio.info("Queuing \(unanalyzed.count) recordings for analysis")
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
