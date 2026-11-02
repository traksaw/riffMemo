//
//  DiagnosticsStoreTests.swift
//  RiffMemoTests
//

import Foundation
import Testing
@testable import RiffMemo

/// WAS-114: crash and hang reports must survive on the device, never pile up
/// without limit, and export as one valid JSON file a developer can read.
struct DiagnosticsStoreTests {

    private let directory: URL

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WAS114-\(UUID().uuidString)", isDirectory: true)
    }

    /// A store whose clock moves one second per call, so files sort predictably.
    private func makeStore(startingAt start: Int = 1_000_000_000) -> DiagnosticsStore {
        var tick = start
        var store = DiagnosticsStore(directory: directory)
        store.now = {
            defer { tick += 1 }
            return Date(timeIntervalSince1970: TimeInterval(tick))
        }
        return store
    }

    private func report(_ id: Int) -> Data {
        Data(#"{"crashDiagnostics":[{"id":\#(id)}]}"#.utf8)
    }

    @Test func emptyStoreHasNoReportsAndNoExport() throws {
        let store = makeStore()
        #expect(try store.reportURLs().isEmpty)
        #expect(try store.makeExportFile() == nil)
    }

    @Test func savedReportIsListed() throws {
        let store = makeStore()
        #expect(try store.save(report(1)))
        #expect(try store.reportURLs().count == 1)
    }

    @Test func sameReportDeliveredTwiceIsStoredOnce() throws {
        // start() re-reads pastDiagnosticPayloads on every launch, so the same
        // report can arrive again.
        let store = makeStore()
        #expect(try store.save(report(1)))
        #expect(try store.save(report(1)) == false)
        #expect(try store.reportURLs().count == 1)
    }

    @Test func keepsOnlyTheNewestReports() throws {
        let store = makeStore()
        for id in 0..<(DiagnosticsStore.maxReports + 5) {
            try store.save(report(id))
        }
        let urls = try store.reportURLs()
        #expect(urls.count == DiagnosticsStore.maxReports)

        // The newest report survives and the oldest five are gone.
        let newest = try JSONSerialization.jsonObject(with: Data(contentsOf: urls[0])) as? [String: Any]
        let crashes = newest?["crashDiagnostics"] as? [[String: Int]]
        #expect(crashes?.first?["id"] == DiagnosticsStore.maxReports + 4)
    }

    @Test func listsNewestFirstEvenAcrossADigitBoundary() throws {
        // 999_999_999 -> 1_000_000_000 adds a digit; a plain string sort would
        // put the newer file last.
        let store = makeStore(startingAt: 999_999_999)
        try store.save(report(1))
        try store.save(report(2))
        let names = try store.reportURLs().map(\.lastPathComponent)
        #expect(names.first?.hasPrefix("1000000000-") == true)
    }

    @Test func exportIsOneJSONDocumentWithEveryReport() throws {
        let store = makeStore()
        try store.save(report(1))
        try store.save(report(2))

        let url = try #require(try store.makeExportFile())
        let export = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        #expect(export["app"] as? String == "RiffMemo")
        #expect((export["reports"] as? [Any])?.count == 2)
    }
}
