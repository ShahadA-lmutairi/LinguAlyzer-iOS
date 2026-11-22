import XCTest

/// Walks through the app slowly so the simulator recording makes a readable demo GIF.
/// Skipped in normal test runs; the demo workflow sets RECORD_DEMO=1.
final class DemoUITests: XCTestCase {
    func testRecordDemo() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RECORD_DEMO"] == "1",
                          "Only runs when recording the demo")

        let app = XCUIApplication()
        app.launchEnvironment["LINGUALYZER_DEMO"] = "1"
        app.launch()
        pause(2)

        // Analyze the demo translation
        app.buttons["Analyze text"].tap()
        XCTAssertTrue(app.staticTexts["Rule-based QA"].waitForExistence(timeout: 15))
        pause(2)
        app.swipeUp()
        pause(2.5)

        // Review the suggestions
        let review = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Review'")).firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        review.tap()
        pause(2)
        app.buttons["Accept"].firstMatch.tap()
        pause(1.5)
        app.swipeUp()
        pause(2.5)

        // Glossary
        app.tabBars.buttons["Glossary"].tap()
        pause(2.5)

        // Back to Analyze
        app.tabBars.buttons["Analyze"].tap()
        pause(1.5)
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
