import SwiftUI

struct SamplingSettingsSection: View {
    @AppStorage(SamplingSettings.Keys.temperature) private var temperature = 0.7
    @AppStorage(SamplingSettings.Keys.topP) private var topP = 0.9
    @AppStorage(SamplingSettings.Keys.topK) private var topK = 40
    @AppStorage(SamplingSettings.Keys.minP) private var minP = 0.0
    @AppStorage(SamplingSettings.Keys.repetitionPenalty) private var repetitionPenalty = 1.0
    @AppStorage(SamplingSettings.Keys.repetitionWindow) private var repetitionWindow = 64
    @AppStorage(SamplingSettings.Keys.useFixedSeed) private var useFixedSeed = false
    @AppStorage(SamplingSettings.Keys.seed) private var seed = 42

    var body: some View {
        Section {
            slider("Temperature", value: $temperature, in: 0...2, step: 0.05,
                   id: "samplingTemperature", display: temperature == 0 ? "Greedy" : nil)
            help(temperature == 0
                 ? "Always chooses the highest scoring token. Probability filters and seed are inactive."
                 : "Higher values make replies more varied. Set to 0 for greedy decoding.")

            slider("Top P", value: $topP, in: 0.01...1, step: 0.01, id: "samplingTopP")
                .disabled(temperature == 0)
            help("Keeps the smallest set of likely tokens whose combined probability reaches this value. 1 keeps all.")

            Stepper(value: $topK, in: 0...200) {
                HStack {
                    Text("Top K")
                    Spacer()
                    Text(topK == 0 ? "Off" : "\(topK)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("samplingTopKValue")
                }
            }
            .accessibilityIdentifier("samplingTopK")
            .disabled(temperature == 0)
            help("Limits choices to this many highest scoring tokens. 0 disables the limit.")

            slider("Min P", value: $minP, in: 0...1, step: 0.01, id: "samplingMinP")
                .disabled(temperature == 0)
            help("Excludes tokens below this fraction of the most likely token's probability. 0 disables the filter.")

            slider("Repetition Penalty", value: $repetitionPenalty, in: 1...2, step: 0.05,
                   id: "samplingRepetitionPenalty")
            help("Discourages tokens used recently in the conversation. 1 disables the penalty.")
            Picker("Repetition Window", selection: $repetitionWindow) {
                Text("Off").tag(0)
                ForEach([32, 64, 128, 256, 512], id: \.self) { tokens in
                    Text("\(tokens) tokens").tag(tokens)
                }
            }
            .accessibilityIdentifier("samplingRepetitionWindow")

            Toggle("Use Fixed Seed", isOn: $useFixedSeed)
                .accessibilityIdentifier("samplingUseFixedSeed")
                .disabled(temperature == 0)
            if useFixedSeed {
                HStack {
                    Text("Seed")
                    Spacer()
                    TextField("Seed", value: $seed, format: .number.grouping(.never))
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("samplingSeed")
#if os(iOS)
                        .keyboardType(.numberPad)
#endif
                }
                .disabled(temperature == 0)
                .onChange(of: seed) { _, value in
                    seed = min(max(value, 0), Int(Int32.max))
                }
            }
            help("A fixed seed repeats the sampling sequence for the same prompt and settings in a new chat. Turn it off for fresh randomness.")

            Button("Reset Sampling Settings") { SamplingSettings().save() }
                .accessibilityIdentifier("samplingReset")
        } header: {
            Text("Sampling Settings")
        } footer: {
            Text("Saved automatically. Changes apply to the next reply.")
        }
        .onAppear { SamplingSettings.load().save() }
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>,
                        step: Double, id: String, display: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(display ?? String(format: "%.2f", value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(id + "Value")
            }
            Slider(value: value, in: range, step: step) { Text(title) }
                .accessibilityIdentifier(id)
        }
    }

    private func help(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}

struct SamplingSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form { SamplingSettingsSection() }
                .navigationTitle("Sampling Settings")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
