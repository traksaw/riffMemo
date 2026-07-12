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

    private let shareManager: ShareManager

    // MARK: - Initialization

    init(shareManager: ShareManager = .shared) {
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
        await shareManager.shareRecording(recording, settings: settings)

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
        await shareManager.shareMultipleRecordings(recordings, settings: settings)

        isExporting = false
    }
}
