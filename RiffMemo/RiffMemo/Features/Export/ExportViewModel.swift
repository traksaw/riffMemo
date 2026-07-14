//
//  ExportViewModel.swift
//  RiffMemo
//

import Foundation
import Observation

/// ViewModel for the export screens (single-recording and batch)
@MainActor
@Observable
class ExportViewModel {

    // MARK: - Published State

    var isExporting: Bool = false
    var exportProgress: Double = 0

    // MARK: - Dependencies

    private let shareManager: any ShareManagerProtocol

    // MARK: - Initialization

    init(shareManager: any ShareManagerProtocol = ShareManager.shared) {
        self.shareManager = shareManager
    }

    // MARK: - Actions

    func exportAndShare(
        _ recording: Recording,
        format: AudioFormat,
        quality: ExportQuality,
        includeMetadata: Bool
    ) async {
        isExporting = true

        let settings = ExportSettings(
            format: format,
            quality: quality,
            includeMetadata: includeMetadata,
            metadata: includeMetadata ? ExportMetadata.from(recording) : nil
        )
        // `from` has no default in the protocol; the concrete manager's `nil` default is now explicit.
        await shareManager.shareRecording(recording, settings: settings, from: nil)

        isExporting = false
    }

    func exportAll(
        _ recordings: [Recording],
        format: AudioFormat,
        quality: ExportQuality,
        includeMetadata: Bool
    ) async {
        isExporting = true
        exportProgress = 0

        let settings = ExportSettings(
            format: format,
            quality: quality,
            includeMetadata: includeMetadata,
            metadata: nil
        )
        await shareManager.shareMultipleRecordings(recordings, settings: settings, from: nil)

        isExporting = false
    }
}
