import XCTest

final class SamplingSettingsUITests: XCTestCase {
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        if element.exists && element.isHittable { return }
        // List can discard accessibility elements outside the visible region.
        // Start from its header so the search also reaches controls above us.
        for _ in 0..<10 {
            if app.staticTexts["Run massive MoE models on iPhone"].isHittable { break }
            app.swipeDown()
        }
        for _ in 0..<14 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTFail("Could not reach sampling control: \(element)")
    }

    @MainActor
    private func resetSettings(in app: XCUIApplication) {
        let reset = app.buttons["samplingReset"]
        reveal(reset, in: app)
        reset.tap()
    }

    @MainActor
    func testSamplingControlsAreAvailableWithoutLoadingAModel() {
        let app = XCUIApplication()
        app.launch()
        resetSettings(in: app)
        for id in ["samplingTemperature", "samplingTopP", "samplingMinP", "samplingRepetitionPenalty"] {
            let slider = app.sliders[id]
            reveal(slider, in: app)
            XCTAssertTrue(slider.isEnabled, "\(id) must be usable on a new installation")
        }
        let topK = app.steppers["samplingTopK"]
        reveal(topK, in: app)
        XCTAssertTrue(topK.isEnabled)
        let seed = app.switches["samplingUseFixedSeed"]
        reveal(seed, in: app)
        XCTAssertEqual(seed.value as? String, "0")
        seed.tap()
        let seedField = app.textFields["samplingSeed"]
        reveal(seedField, in: app)
        XCTAssertEqual(seedField.value as? String, "42")
    }

    @MainActor
    func testSamplingChangesPersistAcrossRelaunch() {
        let app = XCUIApplication()
        app.launch()
        resetSettings(in: app)
        let topK = app.steppers["samplingTopK"]
        reveal(topK, in: app)
        topK.buttons.element(boundBy: 1).tap()
        XCTAssertEqual(app.staticTexts["samplingTopKValue"].label, "41")
        let temperature = app.sliders["samplingTemperature"]
        reveal(temperature, in: app)
        temperature.adjust(toNormalizedSliderPosition: 0)
        XCTAssertEqual(app.staticTexts["samplingTemperatureValue"].label, "Greedy")
        app.terminate()
        app.launch()
        let restoredTemperature = app.sliders["samplingTemperature"]
        reveal(restoredTemperature, in: app)
        XCTAssertEqual(app.staticTexts["samplingTemperatureValue"].label, "Greedy")
        let restoredTopK = app.steppers["samplingTopK"]
        reveal(restoredTopK, in: app)
        XCTAssertEqual(app.staticTexts["samplingTopKValue"].label, "41")
        XCTAssertFalse(restoredTopK.isEnabled)
    }

    @MainActor
    func testTemperatureZeroDisablesProbabilityFiltersAndResetRestoresThem() {
        let app = XCUIApplication()
        app.launch()
        resetSettings(in: app)
        let temperature = app.sliders["samplingTemperature"]
        reveal(temperature, in: app)
        temperature.adjust(toNormalizedSliderPosition: 0)
        let topP = app.sliders["samplingTopP"]
        reveal(topP, in: app)
        XCTAssertFalse(topP.isEnabled)
        let minP = app.sliders["samplingMinP"]
        reveal(minP, in: app)
        XCTAssertFalse(minP.isEnabled)
        resetSettings(in: app)
        reveal(app.sliders["samplingTopP"], in: app)
        XCTAssertTrue(app.sliders["samplingTopP"].isEnabled)
        reveal(app.sliders["samplingTemperature"], in: app)
        XCTAssertEqual(app.staticTexts["samplingTemperatureValue"].label, "0.70")
    }
}
