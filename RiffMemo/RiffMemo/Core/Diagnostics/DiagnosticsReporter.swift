//
//  DiagnosticsReporter.swift
//  RiffMemo
//

import Foundation
import MetricKit
import OSLog

/// WAS-114: receives crash and hang reports from MetricKit and stores them on the
/// device. MetricKit is Apple's own reporting, so no third-party SDK is involved.
///
/// Delivery timing: a crash report arrives on the next launch after the crash
/// (iOS 15+), not at the moment of the crash. MetricKit does not deliver reports
/// in the Simulator. On a device run from Xcode, use Debug > Simulate MetricKit
/// Payloads to test the path.
///
/// `nonisolated` because MetricKit calls `didReceive` on a background queue.
nonisolated final class DiagnosticsReporter: NSObject, MXMetricManagerSubscriber {
    static let shared = DiagnosticsReporter(store: .makeDefault())

    private let store: DiagnosticsStore

    init(store: DiagnosticsStore) {
        self.store = store
    }

    /// Subscribes to MetricKit. Call once at launch.
    func start() {
        MXMetricManager.shared.add(self)
        // Reports delivered while no subscriber was registered (for example, the
        // launch that crashed before reaching this call) are kept here.
        // `save` skips any report that is already stored.
        didReceive(MXMetricManager.shared.pastDiagnosticPayloads)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads where Self.hasCrashOrHang(payload) {
            do {
                try store.save(payload.jsonRepresentation())
            } catch {
                Logger.app.error("Failed to save diagnostic report: \(error)")
            }
        }
    }

    /// Only crash and hang reports are kept. CPU, disk-write and app-launch
    /// diagnostics are out of scope for WAS-114.
    private static func hasCrashOrHang(_ payload: MXDiagnosticPayload) -> Bool {
        !(payload.crashDiagnostics ?? []).isEmpty || !(payload.hangDiagnostics ?? []).isEmpty
    }
}
