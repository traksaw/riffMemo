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
    ///
    /// The file is staged (moved aside) rather than deleted outright, so if
    /// the DB save fails afterward (e.g. a CloudKit sync conflict), it can
    /// be moved back — keeping the still-existing row pointing at a real
    /// file instead of leaking the opposite way this bug originally did.
    func delete(_ recording: Recording) async throws {
        let originalURL = recording.audioFileURL
        let stagedURL = try stageAudioFileForDeletion(at: originalURL)

        do {
            modelContext.delete(recording)
            try modelContext.save()
        } catch {
            if let stagedURL {
                try? FileManager.default.moveItem(at: stagedURL, to: originalURL)
            }
            throw error
        }

        if let stagedURL {
            try? FileManager.default.removeItem(at: stagedURL)
        }
        Logger.info("Recording deleted: \(recording.title)", category: Logger.data)
    }

    /// Moves the audio file into a staging directory instead of removing it,
    /// so a failed DB save can restore it. Returns nil if there was nothing
    /// to move — a missing file (e.g. from a prior partial failure) is not a
    /// blocking error.
    func stageAudioFileForDeletion(at url: URL) throws -> URL? {
        let stagingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PendingRecordingDeletes", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        let stagedURL = stagingDirectory.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")

        do {
            try FileManager.default.moveItem(at: url, to: stagedURL)
            return stagedURL
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            Logger.info("Audio file already absent, skipping: \(url.lastPathComponent)", category: Logger.data)
            return nil
        }
    }

    func update(_ recording: Recording) async throws {
        recording.modifiedDate = Date()
        try modelContext.save()
        Logger.info("Recording updated: \(recording.title)", category: Logger.data)
    }
}
