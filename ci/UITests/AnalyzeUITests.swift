import XCTest

final class AnalyzeUITests: XCTestCase {
    func testAnalyzeSampleDoesNotCrash() {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Sample"].tap()
        app.buttons["Analyze text"].tap()

        XCTAssertTrue(app.staticTexts["Rule-based QA"].waitForExistence(timeout: 15),
                      "Result card did not appear after Analyze text")
        XCTAssertEqual(app.state, .runningForeground, "App is no longer running")
    }
}
