import SwiftUI

struct ThinkingLevelPicker: View {
    let capabilities: ThinkingCapabilities
    @AppStorage(ThinkingSettings.storageKey) private var savedLevel = ThinkingLevel.high.rawValue
    @AppStorage("chatTemplateEnabled") private var chatTemplateEnabled = true

    var body: some View {
        Picker("Thinking", selection: Binding(
            get: { ThinkingLevel(rawValue: savedLevel) ?? .high },
            set: { savedLevel = $0.rawValue }
        )) {
            ForEach(capabilities.levels) { level in
                Text(level.label).tag(level)
            }
        }
        .pickerStyle(.menu)
        .disabled(!chatTemplateEnabled)
        .accessibilityIdentifier("thinkingLevel")
        .accessibilityValue((ThinkingLevel(rawValue: savedLevel) ?? .high).label)
    }
}

struct ThinkingSettingsSection: View {
    let capabilities: ThinkingCapabilities
    @AppStorage(ThinkingSettings.storageKey) private var savedLevel = ThinkingLevel.high.rawValue
    @AppStorage("chatTemplateEnabled") private var chatTemplateEnabled = true

    private var level: ThinkingLevel { ThinkingLevel(rawValue: savedLevel) ?? .high }

    var body: some View {
        Section {
            if capabilities.levels.isEmpty {
                Text("Thinking controls are unavailable for this model.")
                    .foregroundStyle(.secondary)
            } else {
                ThinkingLevelPicker(capabilities: capabilities)
                Text("Qwen3.5 supports thinking On/Off. Low, Medium, and High set thinking token budgets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("thinkingDetail")
            }
        } header: {
            Text("Thinking Settings")
        } footer: {
            Text("Saved automatically. Changes apply to the next reply.")
        }
    }

    private var detail: String {
        if !chatTemplateEnabled { return "Enable Chat Template to use thinking controls." }
        switch level {
        case .off: return "Replies directly without a thinking step."
        case .unlimited: return "No separate thinking limit. Thinking and the answer still share Max Output Tokens."
        case .low, .medium, .high:
            return "Up to \(level.budgetTokens.formatted()) thinking tokens. The output limit may reduce this budget to reserve room for the answer."
        }
    }
}
