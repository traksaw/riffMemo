//
//  DiagnosticsStore.swift
//  RiffMemo
//

import CryptoKit
import Foundation

/// WAS-114: keeps MetricKit crash and hang reports on the device so a tester can
/// send them from Settings. Nothing leaves the device unless the user shares the
/// export file, which keeps the "Data Not Collected" privacy label true.
///
/// Files are named `<seconds-since-1970>-<sha256 prefix>.json`. The time prefix
/// gives a sort order without reading file timestamps (a "required reason" API,
/// see PrivacyManifestTests). The hash prefix lets a re-delivered report be
/// skipped instead of stored twice.
///
/// `nonisolated` because MetricKit delivers reports on a background queue, and
/// the target's default actor isolation is MainActor.
nonisolated struct DiagnosticsStore {
    /// Oldest reports are deleted beyond this count, so a crash loop cannot fill the disk.
    static let maxReports = 20

    let directory: URL
    var now: () -> Date = Date.init

    /// `Application Support/Diagnostics`. Not in Caches: the system can purge
    /// Caches, and a crash report is only useful if it is still there later.
    static func makeDefault() -> DiagnosticsStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return DiagnosticsStore(directory: base.appendingPathComponent("Diagnostics", isDirectory: true))
    }

    /// Saves one report's JSON. Returns `false` when the same report is already stored.
    @discardableResult
    func save(_ json: Data) throws -> Bool {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let hash = SHA256.hash(data: json).prefix(8).map { String(format: "%02x", $0) }.joined()
        if try reportURLs().contains(where: { $0.lastPathComponent.hasSuffix("-\(hash).json") }) {
            return false
        }

        let seconds = Int(now().timeIntervalSince1970)
        let url = directory.appendingPathComponent("\(seconds)-\(hash).json")
        try json.write(to: url, options: .atomic)
        try pruneToMaxReports()
        return true
    }

    /// Stored report files, newest first.
    func reportURLs() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { Self.sortKey($0) > Self.sortKey($1) }
    }

    /// Writes every stored report into one JSON file in the temporary directory,
    /// ready for the share sheet. Returns `nil` when there is nothing to send.
    func makeExportFile() throws -> URL? {
        let urls = try reportURLs()
        guard !urls.isEmpty else { return nil }

        // Each stored file is one MXDiagnosticPayload.jsonRepresentation(). Parse them
        // so the export is one valid JSON document, not files glued together.
        let reports = try urls.map { try JSONSerialization.jsonObject(with: Data(contentsOf: $0)) }
        let info = Bundle.main.infoDictionary
        let export: [String: Any] = [
            "app": "RiffMemo",
            "version": info?["CFBundleShortVersionString"] as? String ?? "unknown",
            "build": info?["CFBundleVersion"] as? String ?? "unknown",
            "reports": reports
        ]
        let data = try JSONSerialization.data(withJSONObject: export, options: [.prettyPrinted, .sortedKeys])

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RiffMemo-diagnostics.json")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func pruneToMaxReports() throws {
        for url in try reportURLs().dropFirst(Self.maxReports) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// The seconds prefix of a report file name; 0 for a name that does not match.
    private static func sortKey(_ url: URL) -> Int {
        Int(url.lastPathComponent.split(separator: "-").first ?? "") ?? 0
    }
}
