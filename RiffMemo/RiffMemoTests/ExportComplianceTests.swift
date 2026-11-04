//
//  ExportComplianceTests.swift
//  RiffMemoTests
//

import Foundation
import Testing

/// WAS-113: without `ITSAppUsesNonExemptEncryption`, App Store Connect holds every
/// TestFlight build in "Missing Compliance" until someone answers the export question
/// by hand (builds 4, 6, 7, and 8 all stopped there). These tests keep the answer
/// shipped and keep it true:
///
/// 1. The built app declares `ITSAppUsesNonExemptEncryption = NO`. Removing the
///    build setting would otherwise go unnoticed until the next upload stalls.
/// 2. App source contains no encryption API calls. "NO" is only true while RiffMemo
///    relies on the encryption built into iOS (CloudKit, HTTPS). Hashing, such as the
///    SHA256 in `DiagnosticsStore`, is not encryption and is allowed.
struct ExportComplianceTests {

    // MARK: - Shipped Info.plist

    /// In app-hosted unit tests `Bundle.main` is the host app (RiffMemo.app), which is
    /// exactly the bundle App Store Connect inspects.
    @Test func builtAppDeclaresNoNonExemptEncryption() throws {
        let value = try #require(
            Bundle.main.object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption"),
            """
            ITSAppUsesNonExemptEncryption is missing from the built Info.plist. Every TestFlight \
            build will stop at "Missing Compliance". Restore \
            INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO in the RiffMemo target's build settings.
            """
        )
        let usesNonExemptEncryption = try #require(
            value as? Bool,
            "ITSAppUsesNonExemptEncryption must be a Boolean, found \(type(of: value))"
        )
        #expect(usesNonExemptEncryption == false, "RiffMemo uses only system encryption; the key must be NO")
    }

    // MARK: - Source scan

    @Test(
        .enabled(
            if: ExportComplianceTests.appSourceRootExists,
            "App sources are not reachable from this test host (e.g. running on a physical device)"
        )
    )
    func appSourceCallsNoEncryptionAPIs() throws {
        let matches = try Self.scanAppSourcesForEncryptionAPIs()
        #expect(
            matches.isEmpty,
            """
            App source now calls encryption APIs, so ITSAppUsesNonExemptEncryption = NO may no \
            longer be true. Review the export-compliance answer before the next upload, then update \
            this test's allow-list if the answer stays NO:
                \(matches.joined(separator: "\n    "))
            """
        )
    }

    // MARK: - Helpers

    /// Regexes for APIs that encrypt or decrypt data, matched against comment-stripped Swift source.
    /// Hash functions (SHA256, Insecure.MD5) are deliberately absent: hashing is not encryption.
    private static let encryptionPatterns: [String] = [
        #"\bimport\s+CommonCrypto\b"#,
        #"\bimport\s+CryptoSwift\b"#,
        #"\bCCCrypt(or\w*)?\s*\("#,
        #"\bAES\.(GCM|KeyWrap)\b"#,
        #"\bChaChaPoly\b"#,
        #"\bHPKE\b"#,
        #"\b(Curve25519|P256|P384|P521)\.KeyAgreement\b"#,
        #"\bSecKeyCreate(Encrypted|Decrypted)Data\b"#,
    ]

    /// `.../RiffMemo/RiffMemoTests/ExportComplianceTests.swift` → `.../RiffMemo/RiffMemo`.
    private static let appSourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("RiffMemo", isDirectory: true)

    private static var appSourceRootExists: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: appSourceRoot.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// Returns ["Relative/File.swift:line  <code>", ...] for every encryption API match.
    private static func scanAppSourcesForEncryptionAPIs() throws -> [String] {
        // `.simple` word boundaries, as in PrivacyManifestTests: Swift Regex's default Unicode
        // boundaries treat `AES.GCM` as one word, so `\b` would not match before `GCM`.
        let regexes = try encryptionPatterns.map { try Regex($0).wordBoundaryKind(.simple) }
        let enumerator = try #require(
            FileManager.default.enumerator(at: appSourceRoot, includingPropertiesForKeys: nil),
            "Could not enumerate app sources at \(appSourceRoot.path)"
        )
        let rootPrefix = appSourceRoot.path + "/"

        var matches: [String] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let relativePath = fileURL.path.replacingOccurrences(of: rootPrefix, with: "")
            for (index, line) in try codeLines(strippingCommentsFrom: source).enumerated()
            where regexes.contains(where: { line.contains($0) }) {
                matches.append("\(relativePath):\(index + 1)  \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        return matches
    }

    /// Removes `/* */` and `//` comments so prose mentioning an API doesn't count as usage.
    /// Block comments become the newlines they contained, so line numbers stay accurate.
    private static func codeLines(strippingCommentsFrom source: String) throws -> [String] {
        let blockComment = try Regex(#"/\*[\s\S]*?\*/"#)
        let withoutBlocks = source.replacing(blockComment) { match in
            String(repeating: "\n", count: match.0.filter { $0 == "\n" }.count)
        }
        return withoutBlocks.components(separatedBy: "\n").map { line in
            guard let range = line.range(of: "//") else { return line }
            return String(line[..<range.lowerBound])
        }
    }
}
