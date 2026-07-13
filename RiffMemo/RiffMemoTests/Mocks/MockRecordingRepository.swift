//
//  MockRecordingRepository.swift
//  RiffMemoTests
//

import Foundation
@testable import RiffMemo

/// In-memory test double for `RecordingRepository` — no SwiftData/ModelContext needed, which
/// also sidesteps the toolchain crash deiniting real SwiftData repositories in tests (see
/// RecordingRepositoryDeleteTests.swift's leak workaround).
final class MockRecordingRepository: RecordingRepository, @unchecked Sendable {
    private(set) var savedRecordings: [Recording] = []
    var saveError: Error?

    func fetchAll() async throws -> [Recording] {
        savedRecordings
    }

    func fetch(by id: UUID) async throws -> Recording? {
        savedRecordings.first { $0.id == id }
    }

    func save(_ recording: Recording) async throws {
        if let saveError {
            throw saveError
        }
        savedRecordings.append(recording)
    }

    func delete(_ recording: Recording) async throws {
        savedRecordings.removeAll { $0.id == recording.id }
    }

    func update(_ recording: Recording) async throws {
        // No-op for these tests: `Recording` is a reference type (@Model class), so in-place
        // mutations are already visible through `savedRecordings`.
    }
}
