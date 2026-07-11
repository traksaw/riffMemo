//
//  RecordingCloudKitCompatibilityTests.swift
//  RiffMemoTests
//

import XCTest
import SwiftData
@testable import RiffMemo

/// WAS-51: CloudKit's schema mirroring requires every non-optional stored
/// property to carry a schema-level default. This fails at ModelContainer
/// init time, not at compile time, so it needs a real test - not just a
/// visual check of the model source.
final class RecordingCloudKitCompatibilityTests: XCTestCase {

    func testModelContainerInitializesWithCloudKitSyncEnabled() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WAS51-\(UUID().uuidString).sqlite")
        let configuration = ModelConfiguration(
            url: tempURL,
            cloudKitDatabase: .automatic
        )
        defer { try? FileManager.default.removeItem(at: tempURL) }

        XCTAssertNoThrow(
            try ModelContainer(for: Recording.self, configurations: configuration),
            "Recording's schema must satisfy CloudKit's requirements: every stored property needs a schema-level default and no @Attribute(.unique)"
        )
    }
}
