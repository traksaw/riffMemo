//
//  WaveformViewTests.swift
//  RiffMemoTests
//
//  Created by Claude Code on 07/11/26.
//

import XCTest
@testable import RiffMemo

/// Covers WaveformView.progress(forLocationX:width:), the pure function
/// backing drag-to-seek. Regression coverage for WAS-52: progress must track
/// the finger's absolute position, not the drag's start location, and must
/// never produce NaN.
final class WaveformViewTests: XCTestCase {

    func testProgressAtStart() {
        XCTAssertEqual(WaveformView.progress(forLocationX: 0, width: 300), 0)
    }

    func testProgressAtEnd() {
        XCTAssertEqual(WaveformView.progress(forLocationX: 300, width: 300), 1)
    }

    func testProgressAtMidpoint() {
        XCTAssertEqual(WaveformView.progress(forLocationX: 150, width: 300), 0.5, accuracy: 0.0001)
    }

    func testProgressIndependentOfDragStartLocation() {
        // Same finger location must yield the same progress regardless of
        // where the drag began - this was the root cause of WAS-52.
        let width: CGFloat = 300
        let location: CGFloat = 75

        let progressFromNearStart = WaveformView.progress(forLocationX: location, width: width)
        let progressFromFarStart = WaveformView.progress(forLocationX: location, width: width)

        XCTAssertEqual(progressFromNearStart, progressFromFarStart)
        XCTAssertEqual(progressFromNearStart, 0.25, accuracy: 0.0001)
    }

    func testProgressClampsBelowZero() {
        XCTAssertEqual(WaveformView.progress(forLocationX: -50, width: 300), 0)
    }

    func testProgressClampsAboveOne() {
        XCTAssertEqual(WaveformView.progress(forLocationX: 400, width: 300), 1)
    }

    func testProgressAtZeroWidthDoesNotProduceNaN() {
        // Regression: dividing by startLocation.x (or an unset width) could
        // yield NaN, which broke comparisons like barProgress <= effectiveProgress.
        let progress = WaveformView.progress(forLocationX: 0, width: 0)

        XCTAssertFalse(progress.isNaN)
        XCTAssertEqual(progress, 0)
    }

    func testProgressAtZeroWidthWithNonZeroLocationDoesNotProduceNaN() {
        let progress = WaveformView.progress(forLocationX: 50, width: 0)

        XCTAssertFalse(progress.isNaN)
        XCTAssertEqual(progress, 0)
    }
}
