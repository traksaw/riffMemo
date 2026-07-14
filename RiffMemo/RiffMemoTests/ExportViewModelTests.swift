//
//  ExportViewModelTests.swift
//  RiffMemoTests
//

import XCTest
@testable import RiffMemo

/// WAS-100: first ViewModel test coverage for `ExportViewModel`, using a protocol-mocked
/// `ShareManager`. `shareRecording`/`shareMultipleRecordings` never throw in the real manager
/// (export/zip failures are logged and swallowed internally), so — like `AnalysisViewModel` —
/// there is no error-path to cover; `isExporting`/`exportProgress` and the settings handed to the
/// share manager are the entire observable surface.
@MainActor
final class ExportViewModelTests: XCTestCase {

    private func makeRecording() -> Recording {
        Recording(
            title: "Test Recording",
            duration: 10,
            audioFileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        )
    }

    private func makeViewModel() -> (ExportViewModel, MockShareManager) {
        let shareManager = MockShareManager()
        let viewModel = ExportViewModel(shareManager: shareManager)
        return (viewModel, shareManager)
    }

    func testExportAndShareSetsIsExportingFalseAfterCompletion() async {
        let (viewModel, shareManager) = makeViewModel()

        await viewModel.exportAndShare(makeRecording(), format: .m4a, quality: .high, includeMetadata: true)

        XCTAssertFalse(viewModel.isExporting)
        XCTAssertEqual(shareManager.shareRecordingCallCount, 1)
    }

    func testExportAndShareIncludesMetadataOnlyWhenRequested() async {
        let (viewModel, shareManager) = makeViewModel()
        let recording = makeRecording()

        await viewModel.exportAndShare(recording, format: .wav, quality: .lossless, includeMetadata: false)

        XCTAssertEqual(shareManager.lastSettings?.format, .wav)
        XCTAssertEqual(shareManager.lastSettings?.quality, .lossless)
        XCTAssertNil(shareManager.lastSettings?.metadata, "includeMetadata: false must not attach ExportMetadata")
    }

    func testExportAndShareAttachesMetadataWhenRequested() async {
        let (viewModel, shareManager) = makeViewModel()
        let recording = makeRecording()

        await viewModel.exportAndShare(recording, format: .m4a, quality: .high, includeMetadata: true)

        XCTAssertEqual(shareManager.lastSettings?.metadata?.title, recording.title)
    }

    func testExportAllResetsProgressAndSetsIsExportingFalseAfterCompletion() async {
        let (viewModel, shareManager) = makeViewModel()
        let recordings = [makeRecording(), makeRecording()]

        await viewModel.exportAll(recordings, format: .caf, quality: .medium, includeMetadata: false)

        XCTAssertFalse(viewModel.isExporting)
        XCTAssertEqual(viewModel.exportProgress, 0)
        XCTAssertEqual(shareManager.shareMultipleRecordingsCallCount, 1)
        XCTAssertEqual(shareManager.lastSharedRecordings?.count, 2)
    }
}
