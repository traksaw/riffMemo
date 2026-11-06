//
//  CIConcurrencyParityTests.swift
//  RiffMemoTests
//

import Foundation
import Testing

/// WAS-181: CI builds with Xcode 16.4 (Swift 6.1), which ignores Swift 6.2 concurrency
/// build settings. With them set, a Mac on Xcode 26+ compiled by different rules than CI,
/// and code that built locally failed there (PR #53). Xcode's "Update to recommended
/// settings" prompt can add them back silently, so this test fails if either one returns.
/// See the comment above `runs-on` in `.github/workflows/ios-build.yml`.
struct CIConcurrencyParityTests {

    static let settingsCIIgnores = [
        "SWIFT_DEFAULT_ACTOR_ISOLATION",
        "SWIFT_APPROACHABLE_CONCURRENCY"
    ]

    /// Each line of `projectFile` that sets a setting CI's compiler ignores.
    static func settingsCIIgnores(in projectFile: String) -> [String] {
        projectFile
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in settingsCIIgnores.contains { line.hasPrefix("\($0) =") } }
    }

    private static let projectFileURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // RiffMemoTests
        .deletingLastPathComponent()  // RiffMemo
        .appendingPathComponent("RiffMemo.xcodeproj/project.pbxproj")

    private static var projectFileExists: Bool {
        FileManager.default.fileExists(atPath: projectFileURL.path)
    }

    @Test(
        .enabled(
            if: CIConcurrencyParityTests.projectFileExists,
            "The project file is not reachable from this test host (e.g. running on a physical device)"
        )
    )
    func projectSetsNoConcurrencySettingsThatCIIgnores() throws {
        let projectFile = try String(contentsOf: Self.projectFileURL, encoding: .utf8)

        let found = Self.settingsCIIgnores(in: projectFile)

        #expect(
            found.isEmpty,
            """
            project.pbxproj sets build settings that CI's Xcode 16.4 ignores, so local builds \
            and CI compile by different rules again. Remove them (Xcode's "Update to recommended \
            settings" may have added them):
                \(found.joined(separator: "\n    "))
            """
        )
    }

    /// Proves the check finds the settings, so an empty result above means something.
    @Test func checkFindsEitherSettingInAProjectFile() {
        let sample = """
            buildSettings = {
                SWIFT_APPROACHABLE_CONCURRENCY = YES;
                SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;
                SWIFT_VERSION = 5.0;
            };
            """

        #expect(Self.settingsCIIgnores(in: sample) == [
            "SWIFT_APPROACHABLE_CONCURRENCY = YES;",
            "SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;"
        ])
    }
}
