//
//  AnalysisViewModelTests.swift
//  RiffMemoTests
//

import XCTest
@testable import RiffMemo

/// WAS-100: first ViewModel test coverage for `AnalysisViewModel`, using a protocol-mocked
/// `AudioAnalysisManager`. `analyzeRecording(_:options:)` never throws in the real manager (decode
/// failures are logged and swallowed internally, producing an empty `AnalysisResults` instead),
/// so unlike Recording/Playback there is no error-path (`errorMessage`/`showError`) to cover here
/// — `isAnalyzing`'s state transition is the entire observable surface.
@MainActor
final class AnalysisViewModelTests: XCTestCase {

    private func makeRecording() -> Recording {
        Recording(
            title: "Test Recording",
            duration: 10,
            audioFileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        )
    }

    private func makeViewModel() -> (AnalysisViewModel, MockAnalysisManager) {
        let manager = MockAnalysisManager()
        let viewModel = AnalysisViewModel(analysisManager: manager)
        return (viewModel, manager)
    }

    func testAnalyzeSetsIsAnalyzingFalseAfterCompletion() async {
        let (viewModel, manager) = makeViewModel()
        let recording = makeRecording()

        await viewModel.analyze(recording)

        XCTAssertFalse(viewModel.isAnalyzing)
        XCTAssertEqual(manager.analyzeRecordingCallCount, 1)
    }

    func testAnalyzeIsAnalyzingIsTrueWhileTheManagerIsWorking() async throws {
        let (viewModel, manager) = makeViewModel()
        manager.analyzeDelayNanoseconds = 150_000_000
        let recording = makeRecording()

        let task = Task { await viewModel.analyze(recording) }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(viewModel.isAnalyzing, "isAnalyzing should flip true immediately, before the manager's work completes")

        await task.value
        XCTAssertFalse(viewModel.isAnalyzing)
    }

    func testAnalyzePassesTheRecordingAndAllOptionsToTheManager() async {
        let (viewModel, manager) = makeViewModel()
        let recording = makeRecording()

        await viewModel.analyze(recording)

        XCTAssertEqual(manager.lastRecording?.id, recording.id)
        XCTAssertEqual(manager.lastOptions, .all)
    }
}
