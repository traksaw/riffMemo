//
//  RiffMemoUITests.swift
//  RiffMemoUITests
//
//  Created by Waskar Paulino on 11/16/25.
//

import XCTest

final class RiffMemoUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    // MARK: - WAS-53 repro walkthrough (temporary verification test)

    /// Reading `.value` immediately after `.tap()` can catch a stale accessibility-tree
    /// snapshot before SwiftUI's render pass catches up — poll instead of asserting inline.
    @MainActor
    private func waitForToggle(_ toggle: XCUIElement, toBe value: String, timeout: TimeInterval = 3, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: toggle)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "Toggle did not reach value \"\(value)\" in time", file: file, line: line)
    }

    @MainActor
    func testMetronomeStateDoesNotLeakSilentlyAcrossTabs() throws {
        let app = XCUIApplication()
        app.launch()

        func screenshot(_ name: String) {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        // 1. Go to Recording tab, enable the click track
        app.tabBars.buttons["Record"].tap()
        screenshot("01-recording-tab-initial")

        let clickTrackToggle = app.switches["clickTrackToggle"]
        XCTAssertTrue(clickTrackToggle.waitForExistence(timeout: 5))
        if (clickTrackToggle.value as? String) != "1" {
            // SwiftUI's Toggle exposes an overlapping unlabeled inner Switch element at
            // this same location; a plain .tap() (center of the whole labeled row) doesn't
            // reliably land on the actual interactive control. Target the switch knob itself.
            clickTrackToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        waitForToggle(clickTrackToggle, toBe: "1")
        screenshot("02-click-track-enabled")

        // 2. Start recording with the click track (pre-count, then recording)
        let recordButton = app.buttons["recordButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
        recordButton.tap()

        XCTAssertTrue(app.staticTexts["Recording..."].waitForExistence(timeout: 15), "Recording should start after pre-count")
        screenshot("03-recording-active-with-click-track")
        waitForToggle(clickTrackToggle, toBe: "1")

        // 3. Switch to the Metronome tab mid-recording
        app.tabBars.buttons["Metronome"].tap()
        screenshot("04-metronome-tab-while-recording")

        let metronomeStopButton = app.buttons["metronomeStartStopButton"]
        XCTAssertTrue(metronomeStopButton.waitForExistence(timeout: 5))
        XCTAssertFalse(metronomeStopButton.isEnabled, "Stop control must be guarded while a click-tracked recording is active (WAS-53)")

        // 4. Switch back to Recording — the toggle must still reflect reality, not a stale value
        app.tabBars.buttons["Record"].tap()
        screenshot("05-back-to-recording-after-guarded-metronome-tab")

        XCTAssertTrue(app.staticTexts["Recording..."].exists, "Recording should be uninterrupted since Stop was guarded")
        waitForToggle(clickTrackToggle, toBe: "1")

        // 5. Clean up: stop the recording from the Recording tab itself
        recordButton.tap()
        XCTAssertTrue(app.staticTexts["Tap to Record"].waitForExistence(timeout: 5))
        screenshot("06-recording-stopped-cleanly")
    }
}
