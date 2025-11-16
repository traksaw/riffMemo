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

    func delete(_ recording: Recording) async throws {
        modelContext.delete(recording)
        try modelContext.save()
        Logger.info("Recording deleted: \(recording.title)", category: Logger.data)
    }

    func update(_ recording: Recording) async throws {
        recording.modifiedDate = Date()
        try modelContext.save()
        Logger.info("Recording updated: \(recording.title)", category: Logger.data)
    }
}
