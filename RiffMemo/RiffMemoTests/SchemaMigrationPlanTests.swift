//
//  SchemaMigrationPlanTests.swift
//  RiffMemoTests
//

import XCTest
import SwiftData
@testable import RiffMemo

/// WAS-61: catches the day a real `MigrationStage` gets added but wired up
/// wrong (wrong schema order, models missing from the new version, etc.) -
/// that kind of mistake builds fine and only crashes at first launch on a
/// device with an existing store, so it needs a real container round-trip,
/// not just a compile check.
final class SchemaMigrationPlanTests: XCTestCase {

    func testModelContainerInitializesThroughTheMigrationPlan() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WAS61-\(UUID().uuidString).sqlite")
        let configuration = ModelConfiguration(
            url: tempURL,
            cloudKitDatabase: .none
        )
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let container = try ModelContainer(
            for: Schema(versionedSchema: RiffMemoSchemaV1.self),
            migrationPlan: RiffMemoMigrationPlan.self,
            configurations: configuration
        )

        let context = ModelContext(container)
        let recording = Recording(
            title: "Migration scaffolding test",
            duration: 1,
            audioFileURL: URL(fileURLWithPath: "/tmp/test.m4a")
        )
        context.insert(recording)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Recording>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.title, "Migration scaffolding test")
    }
}
