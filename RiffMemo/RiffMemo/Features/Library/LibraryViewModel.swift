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

    // MARK: - Dependencies

    private let repository: RecordingRepository

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

    func toggleFavorite(_ recording: Recording) async {
        // TODO: Implement favorite toggle
    }
}

// MARK: - RecordingFilter

enum RecordingFilter {
    case all
    case favorites
    case recent
}
