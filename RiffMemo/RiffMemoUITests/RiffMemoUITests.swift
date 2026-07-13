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
    /// Default generous enough for a slow/contended CI runner (observed ~3-5x slower than
    /// a local dev machine), not just a fast local one.
    @MainActor
    private func waitForToggle(_ toggle: XCUIElement, toBe value: String, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) {
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
        XCTAssertTrue(clickTrackToggle.waitForExistence(timeout: 10))
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
        XCTAssertTrue(recordButton.waitForExistence(timeout: 10))
        recordButton.tap()

        XCTAssertTrue(app.staticTexts["Recording..."].waitForExistence(timeout: 30), "Recording should start after pre-count")
        screenshot("03-recording-active-with-click-track")
        waitForToggle(clickTrackToggle, toBe: "1")

        // 3. Switch to the Metronome tab mid-recording
        app.tabBars.buttons["Metronome"].tap()
        screenshot("04-metronome-tab-while-recording")

        let metronomeStopButton = app.buttons["metronomeStartStopButton"]
        XCTAssertTrue(metronomeStopButton.waitForExistence(timeout: 10))
        XCTAssertFalse(metronomeStopButton.isEnabled, "Stop control must be guarded while a click-tracked recording is active (WAS-53)")

        // 4. Switch back to Recording — the toggle must still reflect reality, not a stale value
        app.tabBars.buttons["Record"].tap()
        screenshot("05-back-to-recording-after-guarded-metronome-tab")

        XCTAssertTrue(app.staticTexts["Recording..."].exists, "Recording should be uninterrupted since Stop was guarded")
        waitForToggle(clickTrackToggle, toBe: "1")

        // 5. Clean up: stop the recording from the Recording tab itself
        recordButton.tap()
        XCTAssertTrue(app.staticTexts["Tap to Record"].waitForExistence(timeout: 10))
        screenshot("06-recording-stopped-cleanly")
    }

    // MARK: - WAS-52 waveform drag-to-seek repro walkthrough

    /// Records a real clip, opens it, and drags the waveform to prove the fix against the
    /// actual regression rather than just the extracted math: the old formula
    /// (`location.x / startLocation.x`) made the seek result depend on where the drag
    /// began, and a drag starting exactly at x=0 produced NaN, which crashed
    /// `formattedDuration()`'s `Int(self)` conversion when it tried to render the seeked time.
    @MainActor
    func testWaveformScrubbingTracksFingerAbsolutePosition() throws {
        let app = XCUIApplication()
        app.launch()

        func screenshot(_ name: String) {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        // 1. Record a clip long enough to give the waveform a meaningful duration to scrub across.
        app.tabBars.buttons["Record"].tap()
        let recordButton = app.buttons["recordButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 10))
        recordButton.tap()
        // CI's simulator runs this record -> stop -> save -> UI-refresh sequence roughly 4x
        // slower than a local machine (measured: ~20s locally vs. ~85s on a passing CI run) —
        // the waits below need real margin for that, not a local-machine-tuned budget
        // (see WAS-103).
        XCTAssertTrue(app.staticTexts["Recording..."].waitForExistence(timeout: 30), "Recording should start")

        Thread.sleep(forTimeInterval: 5)

        recordButton.tap()
        XCTAssertTrue(app.staticTexts["Tap to Record"].waitForExistence(timeout: 30), "Recording should stop")
        screenshot("01-recording-saved")

        // 2. Open the recording we just made. Library sorts newest-first, so it's the first row.
        app.tabBars.buttons["Library"].tap()
        let recordingRow = app.descendants(matching: .any)["recordingRow"].firstMatch
        XCTAssertTrue(recordingRow.waitForExistence(timeout: 30), "The recording we just made should appear in the Library")
        // The row's NavigationLink combines its title and edit pencil into one accessibility
        // element (the waveform thumbnail is excluded via .accessibilityHidden, see WAS-87), but
        // a plain .tap() still lands ambiguously because the thumbnail's gesture recognizers
        // intercept raw touches regardless of accessibility state (WAS-59 territory). Target the
        // title text specifically, away from both the pencil (trailing edge) and the thumbnail
        // (lower half) - same workaround this file already uses for clickTrackToggle above.
        recordingRow.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.12)).tap()

        let waveform = app.descendants(matching: .any)["waveformView"].firstMatch
        XCTAssertTrue(waveform.waitForExistence(timeout: 15), "Waveform should finish loading")
        screenshot("02-waveform-loaded")

        // 3. Root-cause regression: two drags that END at the same absolute location but
        // START from different points must land on the same seek position. Under the old
        // startLocation-relative formula these would have produced different results.
        let target = CGVector(dx: 0.6, dy: 0.5)

        let slider = app.sliders.firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 5))

        let fromNearStart = waveform.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
        fromNearStart.press(forDuration: 0.05, thenDragTo: waveform.coordinate(withNormalizedOffset: target))
        screenshot("03-dragged-from-near-start")
        let valueAfterDragFromNearStart = try XCTUnwrap(slider.value as? String)

        let fromNearEnd = waveform.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        fromNearEnd.press(forDuration: 0.05, thenDragTo: waveform.coordinate(withNormalizedOffset: target))
        screenshot("04-dragged-from-near-end")
        let valueAfterDragFromNearEnd = try XCTUnwrap(slider.value as? String)

        XCTAssertEqual(
            valueAfterDragFromNearStart,
            valueAfterDragFromNearEnd,
            "Dragging to the same absolute location should land on the same seek position regardless of where the drag started (WAS-52)"
        )

        // 4. NaN regression: starting a drag exactly at x=0 must not crash the app (the old
        // formula divided by startLocation.x, and 0/0 is NaN).
        let fromZero = waveform.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
        fromZero.press(forDuration: 0.05, thenDragTo: waveform.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)))
        screenshot("05-dragged-from-x-zero")

        XCTAssertEqual(app.state, .runningForeground, "App must not crash when a drag starts at x=0 (WAS-52 NaN regression)")

        let timeLabel = app.staticTexts["currentTimeLabel"]
        XCTAssertTrue(timeLabel.waitForExistence(timeout: 5))
        XCTAssertFalse(timeLabel.label.isEmpty, "Current time should still render a valid (non-NaN) value after the x=0 drag")

        // 5. Confirm the app is still fully interactive afterward (proves no NaN froze playback state).
        XCTAssertTrue(waveform.isHittable, "Waveform should remain interactive after the x=0 drag")
    }

    // MARK: - WAS-50 delete-removes-audio-file repro walkthrough

    /// Records a real clip and deletes it via the Library row's swipe action, confirming
    /// it disappears from the list. XCUITest runs out-of-process from the app under test
    /// and can't read its sandboxed Documents directory directly, so the "did the .caf
    /// file actually get removed from disk" half of WAS-50 is verified separately, from
    /// outside this test, by diffing the app's Documents directory (via
    /// `simctl get_app_container`) before and after this test runs.
    @MainActor
    func testDeletingRecordingRemovesItFromLibrary() throws {
        let app = XCUIApplication()
        app.launch()

        func screenshot(_ name: String) {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        // 1. Record a short clip.
        app.tabBars.buttons["Record"].tap()
        let recordButton = app.buttons["recordButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 10))
        recordButton.tap()
        // CI's simulator runs this record -> stop -> save -> UI-refresh sequence roughly 4x
        // slower than a local machine (measured: ~20s locally vs. ~85s on a passing CI run) —
        // the waits below need real margin for that, not a local-machine-tuned budget
        // (see WAS-103).
        XCTAssertTrue(app.staticTexts["Recording..."].waitForExistence(timeout: 30), "Recording should start")

        Thread.sleep(forTimeInterval: 2)

        recordButton.tap()
        XCTAssertTrue(app.staticTexts["Tap to Record"].waitForExistence(timeout: 30), "Recording should stop")
        screenshot("01-recorded-clip")

        // 2. Go to Library and confirm the new recording landed there.
        app.tabBars.buttons["Library"].tap()
        let recordingRow = app.descendants(matching: .any)["recordingRow"].firstMatch
        XCTAssertTrue(recordingRow.waitForExistence(timeout: 30), "The recording we just made should appear in the Library")
        let rowCountBeforeDelete = app.descendants(matching: .any).matching(identifier: "recordingRow").count
        screenshot("02-library-before-delete")

        // 3. Swipe to delete it (Library sorts newest-first, so our clip is the first row).
        // The row's trailing swipe action has allowsFullSwipe: true, so a full-width drag
        // triggers the destructive action directly - there's no separate "Delete" button to
        // wait for and tap afterward (confirmed by inspecting the post-swipe accessibility
        // tree: the row was already gone). A plain .swipeLeft() didn't reliably trigger this
        // in this environment, so use the same press-then-dragTo coordinate gesture this file
        // already relies on elsewhere for gesture-sensitive SwiftUI elements (see the waveform
        // drag above).
        let rowTrailingEdge = recordingRow.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        let rowLeadingEdge = recordingRow.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
        rowTrailingEdge.press(forDuration: 0.05, thenDragTo: rowLeadingEdge)
        screenshot("03-swiped-to-delete")

        // 4. Confirm it's gone: empty state if it was the only recording, otherwise one fewer row.
        if rowCountBeforeDelete == 1 {
            XCTAssertTrue(
                app.staticTexts["No Recordings Yet"].waitForExistence(timeout: 30),
                "Deleting the only recording should show the empty state"
            )
        } else {
            let rowsAfterDelete = app.descendants(matching: .any).matching(identifier: "recordingRow")
            let expectation = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "count == %d", rowCountBeforeDelete - 1),
                object: rowsAfterDelete
            )
            XCTAssertEqual(
                XCTWaiter().wait(for: [expectation], timeout: 30),
                .completed,
                "Row count should decrease by one after delete"
            )
        }
        screenshot("04-recording-removed-from-library")

        XCTAssertEqual(app.state, .runningForeground, "App must not crash on delete (WAS-50)")
    }
}
