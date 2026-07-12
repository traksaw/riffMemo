//
//  RecordingRepository.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import Foundation
import SwiftData

/// Protocol for recording data operations
protocol RecordingRepository {
    func fetchAll() async throws -> [Recording]
    func fetch(by id: UUID) async throws -> Recording?
    func save(_ recording: Recording) async throws
    func delete(_ recording: Recording) async throws
    func update(_ recording: Recording) async throws
}

/// SwiftData implementation of RecordingRepository
@MainActor
class SwiftDataRecordingRepository: RecordingRepository {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() async throws -> [Recording] {
        let descriptor = FetchDescriptor<Recording>(
            sortBy: [SortDescriptor(\.createdDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetch(by id: UUID) async throws -> Recording? {
        let descriptor = FetchDescriptor<Recording>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first
    }

    func save(_ recording: Recording) async throws {
        modelContext.insert(recording)
        try modelContext.save()
        Logger.info("Recording saved: \(recording.title)", category: Logger.data)
    }

    /// Delete operations own both the SwiftData row and its associated audio
    /// file on disk. If a future delete path is added (e.g. a bulk import
    /// rollback), it must route through here or repeat this file cleanup —
    /// otherwise it will silently leak storage the same way WAS-50 did.
    func delete(_ recording: Recording) async throws {
        try deleteAudioFile(at: recording.audioFileURL)
        modelContext.delete(recording)
        try modelContext.save()
        Logger.info("Recording deleted: \(recording.title)", category: Logger.data)
    }

    /// Removes the file first so a failed deletion leaves the DB row pointing
    /// at a real file rather than nothing. A missing file (e.g. from a prior
    /// partial failure) is not a blocking error.
    private func deleteAudioFile(at url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            Logger.info("Audio file already absent, skipping: \(url.lastPathComponent)", category: Logger.data)
        }
    }

    func update(_ recording: Recording) async throws {
        recording.modifiedDate = Date()
        try modelContext.save()
        Logger.info("Recording updated: \(recording.title)", category: Logger.data)
    }
}
