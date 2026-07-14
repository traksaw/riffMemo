//
//  MockAnalysisManager.swift
//  RiffMemoTests
//

import Foundation
@testable import RiffMemo

/// Test double for `AnalysisManagerProtocol`. Lets `AnalysisViewModel` tests drive
/// `isAnalyzing`'s state transition deterministically without decoding real audio.
@MainActor
final class MockAnalysisManager: AnalysisManagerProtocol {
    private(set) var analyzeRecordingCallCount = 0
    private(set) var lastRecording: Recording?
    private(set) var lastOptions: AnalysisOptions?

    var resultsToReturn = AnalysisResults()
    /// Simulates real analysis latency so a test can observe `isAnalyzing == true` mid-flight.
    var analyzeDelayNanoseconds: UInt64 = 0

    func analyzeRecording(_ recording: Recording, options: AnalysisOptions) async -> AnalysisResults {
        analyzeRecordingCallCount += 1
        lastRecording = recording
        lastOptions = options
        if analyzeDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: analyzeDelayNanoseconds)
        }
        return resultsToReturn
    }
}
