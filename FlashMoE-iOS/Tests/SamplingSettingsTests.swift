import XCTest
@testable import FlashMoE

final class SamplingSettingsTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "SamplingSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    func testNewInstallEnablesRandomSampling() {
        withDefaults { defaults in
            let settings = SamplingSettings.load(from: defaults)
            XCTAssertEqual(settings.temperature, 0.7, accuracy: 0.001)
            XCTAssertEqual(settings.topP, 0.9, accuracy: 0.001)
            XCTAssertEqual(settings.topK, 40)
            XCTAssertFalse(settings.useFixedSeed)
            XCTAssertEqual(settings.nativeConfig.temperature, 0.7, accuracy: 0.001)
            XCTAssertEqual(settings.nativeConfig.use_seed, 0)
        }
    }

    func testSavedSettingsReachTheNativeSampler() {
        withDefaults { defaults in
            SamplingSettings(temperature: 1.2, topP: 0.8, topK: 25, minP: 0.05,
                             repetitionPenalty: 1.15, repetitionWindow: 128,
                             useFixedSeed: true, seed: 1234).save(to: defaults)
            let native = SamplingSettings.load(from: defaults).nativeConfig
            XCTAssertEqual(native.temperature, 1.2, accuracy: 0.001)
            XCTAssertEqual(native.top_p, 0.8, accuracy: 0.001)
            XCTAssertEqual(native.top_k, 25)
            XCTAssertEqual(native.min_p, 0.05, accuracy: 0.001)
            XCTAssertEqual(native.repetition_penalty, 1.15, accuracy: 0.001)
            XCTAssertEqual(native.repetition_window, 128)
            XCTAssertEqual(native.use_seed, 1)
            XCTAssertEqual(native.seed, 1234)
        }
    }

    func testZeroValuesSurviveSavingAndReloading() {
        withDefaults { defaults in
            SamplingSettings(temperature: 0, topP: 1, topK: 0, minP: 0,
                             repetitionPenalty: 1, repetitionWindow: 0,
                             useFixedSeed: true, seed: 0).save(to: defaults)
            let settings = SamplingSettings.load(from: defaults)
            XCTAssertEqual(settings.temperature, 0)
            XCTAssertEqual(settings.topK, 0)
            XCTAssertEqual(settings.repetitionWindow, 0)
            XCTAssertEqual(settings.nativeConfig.seed, 0)
            XCTAssertEqual(settings.nativeConfig.use_seed, 1)
        }
    }

    func testOutOfRangeValuesAreClampedBeforeNativeConversion() {
        let settings = SamplingSettings(temperature: -1, topP: 5, topK: Int.max,
                                        minP: -0.5, repetitionPenalty: 99,
                                        repetitionWindow: Int.max,
                                        useFixedSeed: true, seed: -42)
        XCTAssertEqual(settings.temperature, 0)
        XCTAssertEqual(settings.topP, 1)
        XCTAssertEqual(settings.topK, 200)
        XCTAssertEqual(settings.minP, 0)
        XCTAssertEqual(settings.repetitionPenalty, 2)
        XCTAssertEqual(settings.repetitionWindow, 512)
        XCTAssertEqual(settings.nativeConfig.seed, 0)
    }

    func testNonfiniteValuesFallBackToUsableSettings() {
        let settings = SamplingSettings(temperature: .nan, topP: .infinity, minP: .nan,
                                        repetitionPenalty: -.infinity)
        XCTAssertEqual(settings.temperature, 0.7, accuracy: 0.001)
        XCTAssertEqual(settings.topP, 0.9, accuracy: 0.001)
        XCTAssertEqual(settings.minP, 0)
        XCTAssertEqual(settings.repetitionPenalty, 1)
    }

    func testResetReplacesEveryCustomSamplingSetting() {
        withDefaults { defaults in
            SamplingSettings(temperature: 0, topP: 0.2, topK: 1, minP: 0.5,
                             repetitionPenalty: 2, repetitionWindow: 512,
                             useFixedSeed: true, seed: 7).save(to: defaults)
            SamplingSettings().save(to: defaults)
            let settings = SamplingSettings.load(from: defaults)
            XCTAssertEqual(settings.temperature, 0.7, accuracy: 0.001)
            XCTAssertEqual(settings.topP, 0.9, accuracy: 0.001)
            XCTAssertEqual(settings.topK, 40)
            XCTAssertEqual(settings.minP, 0)
            XCTAssertEqual(settings.repetitionPenalty, 1)
            XCTAssertEqual(settings.repetitionWindow, 64)
            XCTAssertFalse(settings.useFixedSeed)
            XCTAssertEqual(settings.seed, 42)
        }
    }
}
