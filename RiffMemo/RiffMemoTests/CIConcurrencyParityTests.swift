//
//  CIConcurrencyParityTests.swift
//  RiffMemoTests
//

import Foundation
import Testing

/// WAS-181: CI builds with Xcode 16.4 (Swift 6.1), which ignores Swift 6.2 concurrency
/// build settings. With them set, a Mac on Xcode 26+ compiled by different rules than CI,
/// and code that built locally failed there (PR #53). Xcode's "Update to recommended
/// settings" prompt can add them back silently, so this test fails if any one returns.
///
/// It also fails if the CI workflow stops pinning its Xcode version. Without the pin, CI
/// takes the runner image's default Xcode, which GitHub changes without notice, and
/// `scripts/ci-parity-build.sh` could not tell which Xcode to match.
/// See the comment above `runs-on` in `.github/workflows/ios-build.yml`.
struct CIConcurrencyParityTests {

    /// Swift 6.2 settings that Swift 6.1 does not know. The last two are the upcoming
    /// features that `SWIFT_APPROACHABLE_CONCURRENCY` turns on; either can also be set alone.
    static let settingsCIIgnores = [
        "SWIFT_DEFAULT_ACTOR_ISOLATION",
        "SWIFT_APPROACHABLE_CONCURRENCY",
        "SWIFT_UPCOMING_FEATURE_NONISOLATED_NONSENDING_BY_DEFAULT",
        "SWIFT_UPCOMING_FEATURE_INFER_ISOLATED_CONFORMANCES"
    ]

    /// Each line of `projectFile` that sets a setting CI's compiler ignores.
    static func settingsCIIgnores(in projectFile: String) -> [String] {
        projectFile
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in settingsCIIgnores.contains { line.hasPrefix("\($0) =") } }
    }

    /// The Xcode version the workflow pins through `DEVELOPER_DIR`, such as "16.4".
    static func pinnedXcodeVersion(in workflow: String) -> String? {
        let pattern = #/DEVELOPER_DIR:\s*/Applications/Xcode_([0-9.]+)\.app/Contents/Developer/#
        return workflow.firstMatch(of: pattern).map { String($0.1) }
    }

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // RiffMemoTests
        .deletingLastPathComponent()  // RiffMemo
        .deletingLastPathComponent()  // repo root

    private static let projectFileURL = repoRoot
        .appendingPathComponent("RiffMemo/RiffMemo.xcodeproj/project.pbxproj")

    private static let workflowURL = repoRoot
        .appendingPathComponent(".github/workflows/ios-build.yml")

    private static var sourcesExist: Bool {
        FileManager.default.fileExists(atPath: projectFileURL.path)
            && FileManager.default.fileExists(atPath: workflowURL.path)
    }

    // MARK: - The real files

    @Test(
        .enabled(
            if: CIConcurrencyParityTests.sourcesExist,
            "The repo is not reachable from this test host (e.g. running on a physical device)"
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

    @Test(
        .enabled(
            if: CIConcurrencyParityTests.sourcesExist,
            "The repo is not reachable from this test host (e.g. running on a physical device)"
        )
    )
    func workflowPinsItsXcodeVersion() throws {
        let workflow = try String(contentsOf: Self.workflowURL, encoding: .utf8)

        #expect(
            Self.pinnedXcodeVersion(in: workflow) != nil,
            """
            .github/workflows/ios-build.yml no longer pins Xcode with \
            DEVELOPER_DIR: /Applications/Xcode_<version>.app/Contents/Developer. CI then uses the \
            runner's default Xcode, which changes without notice, and scripts/ci-parity-build.sh \
            cannot find the version to match.
            """
        )
    }

    // MARK: - The checks themselves

    /// Proves the setting check can fail, so an empty result above means something.
    @Test func checkFindsEverySettingCIIgnores() {
        let sample = """
            buildSettings = {
                SWIFT_APPROACHABLE_CONCURRENCY = YES;
                SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;
                SWIFT_UPCOMING_FEATURE_INFER_ISOLATED_CONFORMANCES = YES;
                SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;
                SWIFT_UPCOMING_FEATURE_NONISOLATED_NONSENDING_BY_DEFAULT = YES;
                SWIFT_VERSION = 5.0;
            };
            """

        #expect(Self.settingsCIIgnores(in: sample) == [
            "SWIFT_APPROACHABLE_CONCURRENCY = YES;",
            "SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;",
            "SWIFT_UPCOMING_FEATURE_INFER_ISOLATED_CONFORMANCES = YES;",
            "SWIFT_UPCOMING_FEATURE_NONISOLATED_NONSENDING_BY_DEFAULT = YES;"
        ])
    }

    @Test func pinCheckReadsTheVersionAndNoticesAMissingPin() {
        let pinned = "    env:\n      DEVELOPER_DIR: /Applications/Xcode_16.4.app/Contents/Developer\n"

        #expect(Self.pinnedXcodeVersion(in: pinned) == "16.4")
        #expect(Self.pinnedXcodeVersion(in: "    runs-on: macos-15\n") == nil)
    }
}
