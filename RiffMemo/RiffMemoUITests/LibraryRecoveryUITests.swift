//
//  LibraryRecoveryUITests.swift
//  RiffMemoUITests
//

import XCTest

/// WAS-121: when the library store can't open, the app must land on the recovery
/// screen instead of crashing. Uses the DEBUG-only `-simulateLibraryOpenFailure`
/// launch argument so no real store has to be corrupted.
final class LibraryRecoveryUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testStoreFailureShowsRecoveryScreenAndRetryReportsFailure() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-simulateLibraryOpenFailure"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Can't open library"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["libraryRecovery.export"].exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists, "The normal app must not load on a failed store")

        let retryFailed = app.staticTexts["libraryRecovery.retryFailed"]
        XCTAssertFalse(retryFailed.exists, "No retry has run yet")

        app.buttons["libraryRecovery.retry"].tap()

        XCTAssertTrue(retryFailed.waitForExistence(timeout: 5), "A failed retry must give visible feedback")
    }
}
