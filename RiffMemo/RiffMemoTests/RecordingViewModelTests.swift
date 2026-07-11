//
//  RecordingViewModelTests.swift
//  RiffMemoTests
//
//  Created by Claude Code on 11/16/25.
//

import XCTest
@testable import RiffMemo

/// Basic unit tests for RecordingViewModel
/// NOTE: Full testing would require protocol-based dependency injection
/// This demonstrates the testing approach for state management
@MainActor
final class RecordingViewModelTests: XCTestCase {

    // MARK: - Model Tests

    func testRecordingModelInitialization() {
        // Given
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test.caf")
        let title = "Test Recording"
        let duration = 45.5

        // When
        let recording = Recording(
            title: title,
            duration: duration,
            audioFileURL: url,
            fileSize: 1024
        )

        // Then
        XCTAssertNotNil(recording.id)
        XCTAssertEqual(recording.title, title)
        XCTAssertEqual(recording.duration, duration)
        // Recording stores only the filename and resolves audioFileURL against
        // the current Documents directory, so the last path component round-trips
        // but the full URL passed in does not.
        XCTAssertEqual(recording.audioFileURL.lastPathComponent, url.lastPathComponent)
        XCTAssertEqual(recording.fileSize, 1024)
        XCTAssertNotNil(recording.createdDate)
    }

    func testRecordingModelOptionalFields() {
        // Given
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test.caf")

        // When
        let recording = Recording(
            title: "Test",
            duration: 10,
            audioFileURL: url,
            detectedBPM: 120,
            detectedKey: "C Major"
        )

        // Then
        XCTAssertEqual(recording.detectedBPM, 120)
        XCTAssertEqual(recording.detectedKey, "C Major")
    }

    // MARK: - Extension Tests

    func testTimeIntervalFormatting() {
        XCTAssertEqual(0.0.formattedDuration(), "0:00")
        XCTAssertEqual(5.0.formattedDuration(), "0:05")
        XCTAssertEqual(59.0.formattedDuration(), "0:59")
        XCTAssertEqual(60.0.formattedDuration(), "1:00")
        XCTAssertEqual(125.5.formattedDuration(), "2:05")
        // formattedDuration() always renders MM:SS, even past an hour;
        // formattedLongDuration() is the HH:MM:SS variant.
        XCTAssertEqual(3661.0.formattedDuration(), "61:01")
        XCTAssertEqual(3661.0.formattedLongDuration(), "1:01:01")
    }

    func testDateFormatting() {
        // Given
        let oneHourAgo = Date(timeIntervalSinceNow: -3600)

        // When
        let formatted = oneHourAgo.formattedForRecording()

        // Then
        // formattedForRecording() renders a relative string (e.g. "1 hour ago")
        XCTAssertFalse(formatted.isEmpty)
        XCTAssertTrue(formatted.contains("ago"))
    }

    // MARK: - Logger Tests

    func testLoggerCategories() {
        // Verify logger categories are available
        XCTAssertNotNil(Logger.app)
        XCTAssertNotNil(Logger.audio)
        XCTAssertNotNil(Logger.data)
        XCTAssertNotNil(Logger.ui)
    }
}

// MARK: - Testing Notes

/*
 FUTURE IMPROVEMENTS FOR FULL TEST COVERAGE:

 To properly test ViewModels with full mocking support:

 1. Create protocol abstractions:
    - protocol AudioRecorderProtocol { ... }
    - protocol RecordingRepositoryProtocol { ... }

 2. Make managers conform to protocols:
    - extension AudioRecordingManager: AudioRecorderProtocol { }

 3. Update ViewModels to depend on protocols:
    - RecordingViewModel(audioRecorder: AudioRecorderProtocol, ...)

 4. Create mock implementations for testing:
    - class MockAudioRecorder: AudioRecorderProtocol { }

 5. Write comprehensive tests:
    - Test state transitions
    - Test error handling
    - Test audio interruptions
    - Test concurrent operations

 EXAMPLE TEST STRUCTURE:

 @MainActor
 final class RecordingViewModelFullTests: XCTestCase {
     var viewModel: RecordingViewModel!
     var mockRecorder: MockAudioRecorder!
     var mockRepository: MockRepository!

     func testToggleRecordingStartsAndStops() async throws {
         // Given
         viewModel.toggleRecording()
         try await Task.sleep(nanoseconds: 100_000_000)

         // Then
         XCTAssertTrue(viewModel.isRecording)
         XCTAssertTrue(mockRecorder.startCalled)

         // When
         viewModel.toggleRecording()
         try await Task.sleep(nanoseconds: 100_000_000)

         // Then
         XCTAssertFalse(viewModel.isRecording)
         XCTAssertTrue(mockRecorder.stopCalled)
     }
 }
 */
