import XCTest

final class ThinkingSettingsUITests: XCTestCase {
    @MainActor
    private func revealPicker(in app: XCUIApplication) -> XCUIElement {
        let picker = app.buttons["thinkingLevel"]
        for _ in 0..<16 {
            if picker.exists && picker.isHittable { return picker }
            app.swipeUp()
        }
        XCTFail("Could not reach Thinking settings")
        return picker
    }

    @MainActor
    func testThinkingLevelsAndOffAreAvailableBeforeLoadingAModel() {
        let app = XCUIApplication()
        app.launch()
        let picker = revealPicker(in: app)
        picker.tap()
        for label in ["Off", "Low", "Medium", "High", "Unlimited"] {
            XCTAssertTrue(app.buttons[label].firstMatch.exists, "Missing thinking option: \(label)")
        }
        app.buttons["High"].firstMatch.tap()
        XCTAssertEqual(picker.value as? String, "High")
    }

    @MainActor
    func testThinkingOffPersistsAcrossRelaunch() {
        let app = XCUIApplication()
        app.launch()
        let picker = revealPicker(in: app)
        picker.tap()
        app.buttons["Off"].firstMatch.tap()
        XCTAssertEqual(picker.value as? String, "Off")
        app.terminate()
        app.launch()
        XCTAssertEqual(revealPicker(in: app).value as? String, "Off")
    }
}
