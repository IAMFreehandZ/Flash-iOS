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

    func testLongThinkingStaysInTheDisclosureUntilItsEndMarker() {
        let reasoning = String(repeating: "Planning the story. ", count: 2048)
        let open = content("<think>\n" + reasoning)
        XCTAssertEqual(open.think, reasoning.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertEqual(open.reply, "")
        let closed = content("<think>\n" + reasoning + "</think>\n\nOnce upon a time.")
        XCTAssertEqual(closed.think, open.think)
        XCTAssertEqual(closed.reply, "Once upon a time.")
    }

    func testReopenedThinkingIsKeptOutOfTheAnswer() {
        let parsed = content("<think>First plan</think>\n\nIntroduction. <think>Revised plan</think> Ending.")
        XCTAssertEqual(parsed.think, "First plan\n\nRevised plan")
        XCTAssertEqual(parsed.reply, "Introduction.  Ending.")
    }

    func testUnfinishedThinkingAfterAnAnswerRemainsInTheDisclosure() {
        let parsed = content("<think>First plan</think>Introduction.<think>Still planning")
        XCTAssertEqual(parsed.think, "First plan\n\nStill planning")
        XCTAssertEqual(parsed.reply, "Introduction.")
    }

    func testThinkingAliasAfterAStoryRemainsInTheDisclosure() {
        let answer = "I hope you enjoyed it!\n</plaintext>\n<content>"
        let parsed = content("<think>First plan</think>" + answer +
                             "\n<thinking>Okay, the user asked for a short story.",
                             isStreaming: true)
        XCTAssertEqual(parsed.think, "First plan\n\nOkay, the user asked for a short story.")
        XCTAssertEqual(parsed.reply, answer)
    }

    func testClosedThinkingAliasSeparatesReasoningFromTheAnswer() {
        let parsed = content("<thinking>Plan the story.</thinking>Once upon a time.")
        XCTAssertEqual(parsed.think, "Plan the story.")
        XCTAssertEqual(parsed.reply, "Once upon a time.")
    }

    func testThinkingAliasMarkersSplitAcrossCallbacksAreHeldUntilComplete() {
        for marker in ["<thinking>", "</thinking>"] {
            for length in 1..<marker.count {
                let suffix = String(marker.prefix(length))
                let text = marker == "<thinking>" ? "Story" + suffix : "<thinking>Plan" + suffix
                let parsed = content(text, isStreaming: true)
                XCTAssertEqual(parsed.think, marker == "<thinking>" ? nil : "Plan", "Suffix: \(suffix)")
                XCTAssertEqual(parsed.reply, marker == "<thinking>" ? "Story" : "", "Suffix: \(suffix)")
            }
        }
    }

    func testThinkingAliasAndCanonicalBlocksCanAlternate() {
        let parsed = content("<thinking>First plan</thinking>Introduction. <think>More planning</think> Ending.")
        XCTAssertEqual(parsed.think, "First plan\n\nMore planning")
        XCTAssertEqual(parsed.reply, "Introduction.  Ending.")
    }

    func testClosingMarkerSplitAcrossCallbacksNeverBecomesAnswerText() {
        for suffix in ["<", "</", "</t", "</th", "</thi", "</thin", "</think"] {
            let parsed = content("<think>Plan" + suffix, isStreaming: true)
            XCTAssertEqual(parsed.think, "Plan", "Suffix: \(suffix)")
            XCTAssertEqual(parsed.reply, "", "Suffix: \(suffix)")
        }
        XCTAssertEqual(content("<think>Plan</think>\n\nStory").reply, "Story")
    }

    func testReopeningMarkerSplitAcrossCallbacksIsHeldOutOfTheAnswer() {
        for suffix in ["<", "<t", "<th", "<thi", "<thin", "<think"] {
            let parsed = content("<think>Plan</think>Story" + suffix, isStreaming: true)
            XCTAssertEqual(parsed.think, "Plan", "Suffix: \(suffix)")
            XCTAssertEqual(parsed.reply, "Story", "Suffix: \(suffix)")
        }
        let reopened = content("<think>Plan</think>Story<think>More planning")
        XCTAssertEqual(reopened.think, "Plan\n\nMore planning")
        XCTAssertEqual(reopened.reply, "Story")
    }

    func testStrayClosingMarkerDoesNotPairWithALaterOpeningMarker() {
        let parsed = content("</think>Literal text. <think>Plan</think>Answer")
        XCTAssertEqual(parsed.think, "Plan")
        XCTAssertEqual(parsed.reply, "</think>Literal text. Answer")
    }

    func testDirectAnswerHasNoThinkingDisclosure() {
        let parsed = content("A short story.")
        XCTAssertNil(parsed.think)
        XCTAssertEqual(parsed.reply, "A short story.")
    }

    func testFinishedAnswerPreservesLiteralMarkerPrefixes() {
        for suffix in ["<", "<t", "<th", "<thi", "<thin", "<think"] {
            XCTAssertEqual(content("Literal text " + suffix).reply, "Literal text " + suffix)
        }
    }

    private func content(_ text: String, isStreaming: Bool = false) -> (think: String?, reply: String) {
        ChatMessage(role: .assistant, text: text, timestamp: Date(), isStreaming: isStreaming).parsedContent
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "ThinkingSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }
}
