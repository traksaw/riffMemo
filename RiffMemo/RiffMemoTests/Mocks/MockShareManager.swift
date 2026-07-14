//
//  MockShareManager.swift
//  RiffMemoTests
//

import UIKit
@testable import RiffMemo

/// Test double for `ShareManagerProtocol`. Lets `ExportViewModel` tests verify the export
/// settings/recordings it hands off, without presenting a real `UIActivityViewController` or
/// touching the filesystem.
@MainActor
final class MockShareManager: ShareManagerProtocol {
    private(set) var shareRecordingCallCount = 0
    private(set) var shareMultipleRecordingsCallCount = 0
    private(set) var lastSharedRecording: Recording?
    private(set) var lastSharedRecordings: [Recording]?
    private(set) var lastSettings: ExportSettings?

    func shareRecording(_ recording: Recording, settings: ExportSettings?, from sourceView: UIView?) async {
        shareRecordingCallCount += 1
        lastSharedRecording = recording
        lastSettings = settings
    }

    func shareMultipleRecordings(_ recordings: [Recording], settings: ExportSettings?, from sourceView: UIView?) async {
        shareMultipleRecordingsCallCount += 1
        lastSharedRecordings = recordings
        lastSettings = settings
    }
}
