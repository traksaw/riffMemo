//
//  PrivacyManifestTests.swift
//  RiffMemoTests
//

import Foundation
import Testing

/// WAS-112: App Store Connect rejects uploads (ITMS-91053) when the app uses a
/// "required reason" API without declaring it in `PrivacyInfo.xcprivacy`. That
/// only surfaces at upload time, so these tests turn it into a local/CI failure:
///
/// 1. The manifest actually ships inside the built app bundle. A manifest that
///    sits in the repo but isn't copied into the target is the classic regression.
/// 2. Every entry uses a category and reason code App Store Connect accepts
///    (an unknown reason code is its own rejection, ITMS-91056).
/// 3. The declared categories match what the app source actually uses, in both
///    directions, so a new `@AppStorage` or `stat()` call can't silently drift
///    from the manifest, and stale declarations get removed.
struct PrivacyManifestTests {

    // MARK: - Shipped manifest

    @Test func manifestShipsInTheAppBundleAsAValidPlist() throws {
        let manifest = try Self.loadShippedManifest()
        #expect(!manifest.isEmpty, "PrivacyInfo.xcprivacy parsed to an empty dictionary")
    }

    @Test func declaresNoTrackingAndNoDataCollection() throws {
        let manifest = try Self.loadShippedManifest()

        let tracking = try #require(
            manifest["NSPrivacyTracking"] as? Bool,
            "NSPrivacyTracking must be present and a Boolean"
        )
        #expect(tracking == false, "RiffMemo does not track users; NSPrivacyTracking must be false")

        if let domains = manifest["NSPrivacyTrackingDomains"] {
            let list = try #require(domains as? [String], "NSPrivacyTrackingDomains must be an array of strings")
            #expect(list.isEmpty, "RiffMemo has no tracking domains, found: \(list)")
        }

        let collected = try #require(
            manifest["NSPrivacyCollectedDataTypes"] as? [Any],
            "NSPrivacyCollectedDataTypes must be present (an empty array means 'no data collected')"
        )
        #expect(collected.isEmpty, "RiffMemo declares no data collection, found \(collected.count) entries")
    }

    @Test func accessedAPIEntriesUseAcceptedCategoriesAndReasons() throws {
        let entries = try Self.declaredAccessedAPIEntries()
        #expect(
            !entries.isEmpty,
            "NSPrivacyAccessedAPITypes is present but empty. App Store Connect rejects an empty array; remove the key if nothing is used."
        )

        var seenCategories = Set<String>()
        for entry in entries {
            let category = try #require(
                entry["NSPrivacyAccessedAPIType"] as? String,
                "Each NSPrivacyAccessedAPITypes entry needs a string NSPrivacyAccessedAPIType"
            )
            let api = try #require(
                Self.requiredReasonAPIs.first { $0.category == category },
                "Unknown required-reason category '\(category)'. Valid: \(Self.requiredReasonAPIs.map(\.category))"
            )
            #expect(seenCategories.insert(category).inserted, "Category '\(category)' is declared more than once")

            let reasons = try #require(
                entry["NSPrivacyAccessedAPITypeReasons"] as? [String],
                "'\(category)' needs an NSPrivacyAccessedAPITypeReasons array of strings"
            )
            #expect(!reasons.isEmpty, "'\(category)' declares no reasons; App Store Connect rejects an empty reasons array")
            for reason in reasons {
                #expect(
                    api.acceptedReasons.contains(reason),
                    "Reason '\(reason)' is not accepted for '\(category)'. Accepted: \(api.acceptedReasons.sorted())"
                )
            }
        }
    }

    // MARK: - Source ↔ manifest drift

    @Test(
        .enabled(
            if: PrivacyManifestTests.appSourceRootExists,
            "App sources are not reachable from this test host (e.g. running on a physical device)"
        )
    )
    func declaredCategoriesMatchWhatTheAppSourceUses() throws {
        let declared = Set(try Self.declaredAccessedAPIEntries().compactMap { $0["NSPrivacyAccessedAPIType"] as? String })
        let evidence = try Self.scanAppSourcesForRequiredReasonAPIs()
        let used = Set(evidence.keys)

        let undeclared = used.subtracting(declared).sorted()
        for category in undeclared {
            let locations = (evidence[category] ?? []).joined(separator: "\n    ")
            Issue.record(
                """
                App source uses required-reason API category '\(category)' but PrivacyInfo.xcprivacy \
                does not declare it. Uploading this build would fail with ITMS-91053. Add an entry with \
                one of: \(Self.acceptedReasons(for: category)). Usage found at:
                    \(locations)
                """
            )
        }

        let stale = declared.subtracting(used).sorted()
        for category in stale {
            Issue.record(
                """
                PrivacyInfo.xcprivacy declares '\(category)' but no app source uses an API in that \
                category. Remove the entry (or, if the usage is real, add its API to the scan patterns \
                in PrivacyManifestTests) so the manifest stays accurate.
                """
            )
        }
    }

    // MARK: - Required-reason API catalogue

    /// One entry per category from Apple's "Describing use of required reason API".
    /// `usagePatterns` are regexes matched against comment-stripped Swift source.
    private struct RequiredReasonAPI {
        let category: String
        let acceptedReasons: Set<String>
        let usagePatterns: [String]
    }

    private static let requiredReasonAPIs: [RequiredReasonAPI] = [
        RequiredReasonAPI(
            category: "NSPrivacyAccessedAPICategoryUserDefaults",
            acceptedReasons: ["CA92.1", "1C8F.1", "C56D.1", "AC6B.1"],
            usagePatterns: [
                #"\bUserDefaults\b"#,
                #"\bNSUserDefaults\b"#,
                #"@AppStorage\b"#
            ]
        ),
        RequiredReasonAPI(
            category: "NSPrivacyAccessedAPICategoryFileTimestamp",
            acceptedReasons: ["DDA9.1", "C617.1", "3B52.1", "0A2A.1"],
            usagePatterns: [
                // Reading a file's attribute dictionary returns its timestamps, so treat it as
                // timestamp access (conservative: declaring is harmless, omitting is a rejection).
                #"\battributesOfItem\("#,
                #"FileAttributeKey\.(creationDate|modificationDate)\b"#,
                #"\[\.(creationDate|modificationDate)\]"#,
                #"\.fileModificationDate\b"#,
                #"\b(creationDateKey|contentModificationDateKey)\b"#,
                #"\b(stat|fstat|lstat|fstatat)\("#,
                #"\b(getattrlist|getattrlistbulk|getattrlistat|fgetattrlist)\("#
            ]
        ),
        RequiredReasonAPI(
            category: "NSPrivacyAccessedAPICategorySystemBootTime",
            acceptedReasons: ["35F9.1", "8FFB.1", "3D61.1"],
            usagePatterns: [
                #"\bsystemUptime\b"#,
                #"\bmach_absolute_time\("#,
                #"\bKERN_BOOTTIME\b"#,
                #"kern\.boottime"#
            ]
        ),
        RequiredReasonAPI(
            category: "NSPrivacyAccessedAPICategoryDiskSpace",
            acceptedReasons: ["85F4.1", "E174.1", "7D9E.1", "B728.1"],
            usagePatterns: [
                #"\bvolume(Available|Total)Capacity\w*Key\b"#,
                #"\.(systemFreeSize|systemSize)\b"#,
                #"\battributesOfFileSystem\("#,
                #"\b(statfs|statvfs|fstatfs|fstatvfs)\("#
            ]
        ),
        RequiredReasonAPI(
            category: "NSPrivacyAccessedAPICategoryActiveKeyboards",
            acceptedReasons: ["3EC4.1", "54BD.1"],
            usagePatterns: [
                #"\bactiveInputModes\b"#
            ]
        )
    ]

    private static func acceptedReasons(for category: String) -> [String] {
        requiredReasonAPIs.first { $0.category == category }?.acceptedReasons.sorted() ?? []
    }

    // MARK: - Helpers: shipped manifest

    /// In app-hosted unit tests `Bundle.main` is the host app (RiffMemo.app), which is
    /// exactly the bundle App Store Connect inspects.
    private static func loadShippedManifest() throws -> [String: Any] {
        let url = try #require(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            """
            PrivacyInfo.xcprivacy is missing from the app bundle (\(Bundle.main.bundlePath)). \
            It must live inside RiffMemo/RiffMemo so Xcode's synchronized folder copies it as a resource.
            """
        )
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(plist as? [String: Any], "PrivacyInfo.xcprivacy must be a dictionary-rooted property list")
    }

    private static func declaredAccessedAPIEntries() throws -> [[String: Any]] {
        let manifest = try loadShippedManifest()
        guard let raw = manifest["NSPrivacyAccessedAPITypes"] else { return [] }
        return try #require(raw as? [[String: Any]], "NSPrivacyAccessedAPITypes must be an array of dictionaries")
    }

    // MARK: - Helpers: source scan

    /// `.../RiffMemo/RiffMemoTests/PrivacyManifestTests.swift` → `.../RiffMemo/RiffMemo`.
    private static let appSourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("RiffMemo", isDirectory: true)

    private static var appSourceRootExists: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: appSourceRoot.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// Returns category → ["Relative/File.swift:line", ...] for every match in app sources.
    private static func scanAppSourcesForRequiredReasonAPIs() throws -> [String: [String]] {
        // `.simple` word boundaries: Swift Regex defaults to Unicode (UAX #29) boundaries, under
        // which `FileManager.default.attributesOfItem` is a single word and `\b` never matches
        // before `attributesOfItem`. Simple boundaries behave like the ASCII `\b` the patterns assume.
        let compiled = try requiredReasonAPIs.map { api in
            (
                category: api.category,
                regexes: try api.usagePatterns.map { try Regex($0).wordBoundaryKind(.simple) }
            )
        }

        var evidence: [String: [String]] = [:]
        let enumerator = try #require(
            FileManager.default.enumerator(at: appSourceRoot, includingPropertiesForKeys: nil),
            "Could not enumerate app sources at \(appSourceRoot.path)"
        )
        let rootPrefix = appSourceRoot.path + "/"

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let relativePath = fileURL.path.replacingOccurrences(of: rootPrefix, with: "")

            for (index, line) in try codeLines(strippingCommentsFrom: source).enumerated() {
                for entry in compiled where entry.regexes.contains(where: { line.contains($0) }) {
                    evidence[entry.category, default: []].append("\(relativePath):\(index + 1)")
                }
            }
        }
        return evidence
    }

    /// Removes `/* */` and `//` comments so prose mentioning an API doesn't count as usage.
    /// Block comments are replaced by the newlines they contained, so line numbers stay accurate.
    private static func codeLines(strippingCommentsFrom source: String) throws -> [String] {
        let blockComment = try Regex(#"/\*[\s\S]*?\*/"#)
        let withoutBlocks = source.replacing(blockComment) { match in
            // `match.0` is the whole-match Substring (a string-built Regex has untyped captures).
            String(repeating: "\n", count: match.0.filter { $0 == "\n" }.count)
        }
        return withoutBlocks.components(separatedBy: "\n").map { line in
            guard let range = line.range(of: "//") else { return line }
            return String(line[..<range.lowerBound])
        }
    }
}
