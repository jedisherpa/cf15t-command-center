import SwiftUI

struct VoiceSlotEditorSheet: View {
    @ObservedObject var viewModel: CommandCenterViewModel
    @Environment(\.dismiss) private var dismiss

    private let quickPresets: [(name: String, appName: String, path: String, url: String)] = [
        ("Grok Bot", "Grok Bot", "/Applications/Grok Bot.app", "grokbot://"),
        ("Dot", "Dot", "/Applications/Dot.app", "https://new.computer"),
        ("Claude", "Claude", "/Applications/Claude.app", "claude://"),
        ("ChatGPT", "ChatGPT", "/Applications/ChatGPT.app", "chatgpt://"),
        ("Codex", "Codex Project Picker", "/Applications/Codex Project Picker.app", ""),
        ("Antigravity", "Antigravity", "/Applications/Antigravity.app", ""),
        ("Prism Live", "Prism GT Chat Live", "/Applications/Prism GT Chat Live.app", ""),
        ("Cubed Code", "Cubed Code GPUI", "/Applications/Cubed Code GPUI.app", "")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Configure Voice Assistant Slots (A ⇄ B)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Choose which apps or voice assistants Slot A and Slot B control, and how their mic shortcuts trigger.")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.65))
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Text("Done")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(Color(red: 0.20, green: 0.88, blue: 0.65))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .top, spacing: 18) {
                slotConfigCard(title: "SLOT A (Primary Voice)", config: $viewModel.slotA, accent: Color(red: 1.0, green: 0.38, blue: 0.18))
                slotConfigCard(title: "SLOT B (Secondary Voice)", config: $viewModel.slotB, accent: Color(red: 0.20, green: 0.86, blue: 0.65))
            }

            HStack(spacing: 14) {
                Toggle("Exclusive Mic Lock (Unmuting A automatically mutes B)", isOn: $viewModel.exclusiveMicHandoff)
                    .toggleStyle(.switch)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)

                Spacer()

                Button(action: {
                    viewModel.slotA = .defaultSlotA
                    viewModel.slotB = .defaultSlotB
                }) {
                    Text("Reset to Grok Bot & Dot Defaults")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 820, height: 520)
        .background(Color(red: 0.07, green: 0.09, blue: 0.13))
    }

    @ViewBuilder
    private func slotConfigCard(title: String, config: Binding<VoiceAssistantConfig>, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(accent)

            Text("Quick Assign Preset:")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(quickPresets, id: \.name) { preset in
                    Button(action: {
                        config.wrappedValue.displayName = preset.name
                        config.wrappedValue.targetAppName = preset.appName
                        config.wrappedValue.appBundlePath = preset.path
                        config.wrappedValue.urlSchemeOrWebURL = preset.url
                    }) {
                        Text(preset.name)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(config.wrappedValue.displayName == preset.name ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(config.wrappedValue.displayName == preset.name ? accent : Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }

            Group {
                labeledField("Button Label", text: config.displayName)
                labeledField("Target macOS App Name", text: config.targetAppName)
                labeledField("App Bundle Path", text: config.appBundlePath)
                labeledField("Fallback URL / Scheme", text: config.urlSchemeOrWebURL)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("In-App Mic Shortcut Sent on Toggle:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                Picker("", selection: config.micShortcut) {
                    ForEach(MicShortcutPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .labelsHidden()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.11, green: 0.14, blue: 0.20))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(accent.opacity(0.45), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func labeledField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
        }
    }
}
