import Foundation

/// An immutable snapshot so changing a setting cannot change a reply in progress.
struct SamplingSettings: Sendable {
    enum Keys {
        static let temperature = "samplingTemperature"
        static let topP = "samplingTopP"
        static let topK = "samplingTopK"
        static let minP = "samplingMinP"
        static let repetitionPenalty = "samplingRepetitionPenalty"
        static let repetitionWindow = "samplingRepetitionWindow"
        static let useFixedSeed = "samplingUseFixedSeed"
        static let seed = "samplingSeed"
    }

    let temperature: Double
    let topP: Double
    let topK: Int
    let minP: Double
    let repetitionPenalty: Double
    let repetitionWindow: Int
    let useFixedSeed: Bool
    let seed: Int

    init(temperature: Double = 0.7, topP: Double = 0.9, topK: Int = 40,
         minP: Double = 0, repetitionPenalty: Double = 1, repetitionWindow: Int = 64,
         useFixedSeed: Bool = false, seed: Int = 42) {
        self.temperature = Self.clamp(temperature, to: 0...2, fallback: 0.7)
        self.topP = Self.clamp(topP, to: 0.01...1, fallback: 0.9)
        self.topK = min(max(topK, 0), 200)
        self.minP = Self.clamp(minP, to: 0...1, fallback: 0)
        self.repetitionPenalty = Self.clamp(repetitionPenalty, to: 1...2, fallback: 1)
        self.repetitionWindow = min(max(repetitionWindow, 0), 512)
        self.useFixedSeed = useFixedSeed
        self.seed = min(max(seed, 0), Int(Int32.max))
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
    }

    static func load(from defaults: UserDefaults = .standard) -> SamplingSettings {
        let fallback = SamplingSettings()
        func number(_ key: String) -> NSNumber? { defaults.object(forKey: key) as? NSNumber }
        return SamplingSettings(
            temperature: number(Keys.temperature)?.doubleValue ?? fallback.temperature,
            topP: number(Keys.topP)?.doubleValue ?? fallback.topP,
            topK: number(Keys.topK)?.intValue ?? fallback.topK,
            minP: number(Keys.minP)?.doubleValue ?? fallback.minP,
            repetitionPenalty: number(Keys.repetitionPenalty)?.doubleValue ?? fallback.repetitionPenalty,
            repetitionWindow: number(Keys.repetitionWindow)?.intValue ?? fallback.repetitionWindow,
            useFixedSeed: number(Keys.useFixedSeed)?.boolValue ?? fallback.useFixedSeed,
            seed: number(Keys.seed)?.intValue ?? fallback.seed
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(temperature, forKey: Keys.temperature)
        defaults.set(topP, forKey: Keys.topP)
        defaults.set(topK, forKey: Keys.topK)
        defaults.set(minP, forKey: Keys.minP)
        defaults.set(repetitionPenalty, forKey: Keys.repetitionPenalty)
        defaults.set(repetitionWindow, forKey: Keys.repetitionWindow)
        defaults.set(useFixedSeed, forKey: Keys.useFixedSeed)
        defaults.set(seed, forKey: Keys.seed)
    }

    var nativeConfig: FlashMoESamplingConfig {
        var config = FlashMoESamplingConfig()
        config.temperature = Float(temperature)
        config.top_p = Float(topP)
        config.top_k = Int32(topK)
        config.min_p = Float(minP)
        config.repetition_penalty = Float(repetitionPenalty)
        config.repetition_window = Int32(repetitionWindow)
        config.use_seed = useFixedSeed ? 1 : 0
        config.seed = UInt64(seed)
        return config
    }
}
