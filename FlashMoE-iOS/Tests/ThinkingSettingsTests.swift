import XCTest
@testable import FlashMoE

final class ThinkingSettingsTests: XCTestCase {
    func testCapabilitiesUseConfigurationRatherThanTheDirectoryName() throws {
        let qwen = Data(#"{"model_type":"qwen3_5_moe"}"#.utf8)
        let textOnly = Data(#"{"model_type":"qwen3_5_moe_text"}"#.utf8)
        let unknown = Data(#"{"model_type":"custom_model"}"#.utf8)
        XCTAssertEqual(ThinkingCapabilities.detect(configData: qwen), .qwen35)
        XCTAssertEqual(ThinkingCapabilities.detect(configData: textOnly), .qwen35)
        XCTAssertEqual(ThinkingCapabilities.detect(configData: unknown), .unsupported)
        XCTAssertEqual(ThinkingCapabilities.detect(configData: Data()), .unsupported)
        XCTAssertTrue(ThinkingCapabilities.qwen35.levels.contains(.off))
        XCTAssertTrue(ThinkingCapabilities.unsupported.levels.isEmpty)
    }

    func testNewInstallPreservesTheExistingThinkingBudget() {
        withDefaults { defaults in
            let native = ThinkingSettings.load(from: defaults).nativeConfig(for: .qwen35)
            XCTAssertEqual(native.enabled, 1)
            XCTAssertEqual(native.budget_tokens, 2048)
        }
    }

    func testSavedOffIsDifferentFromUnlimitedThinking() {
        withDefaults { defaults in
            ThinkingSettings(level: .off).save(to: defaults)
            let off = ThinkingSettings.load(from: defaults).nativeConfig(for: .qwen35)
            XCTAssertEqual(off.enabled, 0)
            ThinkingSettings(level: .unlimited).save(to: defaults)
            let unlimited = ThinkingSettings.load(from: defaults).nativeConfig(for: .qwen35)
            XCTAssertEqual(unlimited.enabled, 1)
            XCTAssertEqual(unlimited.budget_tokens, 0)
        }
    }

    func testSettingsSnapshotDoesNotChangeDuringAReply() {
        withDefaults { defaults in
            ThinkingSettings(level: .low).save(to: defaults)
            let snapshot = ThinkingSettings.load(from: defaults)
            ThinkingSettings(level: .off).save(to: defaults)
            XCTAssertEqual(snapshot.nativeConfig(for: .qwen35).enabled, 1)
            XCTAssertEqual(snapshot.nativeConfig(for: .qwen35).budget_tokens, 128)
            XCTAssertEqual(ThinkingSettings.load(from: defaults).nativeConfig(for: .qwen35).enabled, 0)
        }
    }

    func testUnknownModelsAndRawPromptsDoNotReceiveQwenThinkingControls() {
        let settings = ThinkingSettings(level: .off)
        XCTAssertEqual(settings.nativeConfig(for: .unsupported).enabled, -1)
        XCTAssertEqual(settings.nativeConfig(for: .qwen35, chatTemplateEnabled: false).enabled, -1)
    }

    func testInvalidSavedLevelFallsBackToTheExistingBudget() {
        withDefaults { defaults in
            defaults.set("unknown", forKey: ThinkingSettings.storageKey)
            let native = ThinkingSettings.load(from: defaults).nativeConfig(for: .qwen35)
            XCTAssertEqual(native.enabled, 1)
            XCTAssertEqual(native.budget_tokens, 2048)
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "ThinkingSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }
}
