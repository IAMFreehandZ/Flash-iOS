import Foundation

enum ThinkingLevel: String, CaseIterable, Identifiable, Sendable {
    case off, low, medium, high, unlimited

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: "Off"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .unlimited: "Unlimited"
        }
    }

    var budgetTokens: Int {
        switch self {
        case .off, .unlimited: 0
        case .low: 128
        case .medium: 512
        case .high: 2048
        }
    }
}

enum ThinkingCapabilities: Equatable, Sendable {
    case unsupported, qwen35

    var levels: [ThinkingLevel] {
        switch self {
        case .unsupported: []
        case .qwen35: ThinkingLevel.allCases
        }
    }

    static func detect(configData: Data) -> ThinkingCapabilities {
        guard let config = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
              let modelType = config["model_type"] as? String else { return .unsupported }
        switch modelType {
        case "qwen3_5_moe", "qwen3_5_moe_text": return .qwen35
        default: return .unsupported
        }
    }

    static func load(at modelPath: String) -> ThinkingCapabilities {
        let url = URL(fileURLWithPath: modelPath).appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: url) else { return .unsupported }
        return detect(configData: data)
    }
}

/// Saved once per reply so changes cannot alter generation already in progress.
struct ThinkingSettings: Sendable {
    static let storageKey = "thinkingLevel"
    let level: ThinkingLevel

    init(level: ThinkingLevel = .high) { self.level = level }

    static func load(from defaults: UserDefaults = .standard) -> ThinkingSettings {
        let level = defaults.string(forKey: storageKey).flatMap(ThinkingLevel.init(rawValue:)) ?? .high
        return ThinkingSettings(level: level)
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(level.rawValue, forKey: Self.storageKey)
    }

    func nativeConfig(for capabilities: ThinkingCapabilities,
                      chatTemplateEnabled: Bool = true) -> FlashMoEThinkingConfig {
        var config = FlashMoEThinkingConfig()
        guard chatTemplateEnabled, capabilities.levels.contains(level) else {
            config.enabled = -1
            config.budget_tokens = 2048
            return config
        }
        config.enabled = level == .off ? 0 : 1
        config.budget_tokens = Int32(level.budgetTokens)
        return config
    }
}
