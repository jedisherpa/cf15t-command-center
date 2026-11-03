import Cocoa
import SwiftUI
import AVFoundation

// MARK: - 1. Sensory-Friendly Read-Aloud Engine (Text-to-Speech for Non-Verbal & Visual/Auditory Learners)

@MainActor
final class SensoryFriendlySpeechEngine: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = SensoryFriendlySpeechEngine()

    @Published var isSpeaking: Bool = false
    @Published var speakingWindowID: CGWindowID? = nil
    @Published var speakAACConfirmations: Bool = true

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggleReadAloud(for window: MonitoredWindow) {
        if isSpeaking && speakingWindowID == window.id {
            stopSpeaking()
            return
        }

        let digest = window.liveDigest ?? AppContentFeedExtractor.shared.extractLiveDigest(for: window)
        let recentLines = digest.lines.suffix(3)
        let combinedText: String
        if recentLines.isEmpty {
            combinedText = "\(window.appName). \(window.displayTitle)"
        } else {
            let body = recentLines.map { line in
                if let speaker = line.speakerOrTag, !speaker.isEmpty {
                    return "\(speaker) says: \(line.text)"
                }
                return line.text
            }.joined(separator: ". ")
            combinedText = "\(window.appName). \(body)"
        }

        speakText(combinedText, windowID: window.id)
    }

    func speakAACConfirmation(_ phrase: String) {
        guard speakAACConfirmations else { return }
        speakText(phrase, windowID: nil)
    }

    func speakText(_ text: String, windowID: CGWindowID?) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let cleaned = text
            .replacingOccurrences(of: "```", with: "")
            .replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.rate = 0.48 // Calm, clear, unhurried pacing for neurodivergent processing
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.95
        if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }

        speakingWindowID = windowID
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        speakingWindowID = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.speakingWindowID = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.speakingWindowID = nil
        }
    }
}

// MARK: - 2. Non-Verbal AAC Picture-Symbol Action Cards

enum AACActionKind {
    case sendPrompt(String, pressReturn: Bool)
    case scrollWindow(deltaY: Int32)
    case sendKeyCombo(keyCode: CGKeyCode, flags: CGEventFlags, spokenLabel: String)
}

struct AACVisualSymbolCard: Identifiable {
    let id: String
    let iconName: String
    let emoji: String
    let shortTitle: String       // 1-2 big concrete words (e.g. "YES, DO IT", "EXPLAIN SIMPLY")
    let spokenConfirmation: String
    let backgroundColor: Color
    let foregroundColor: Color
    let action: AACActionKind

    static func cards(for window: MonitoredWindow) -> [AACVisualSymbolCard] {
        let digestStyle = window.liveDigest?.style ?? AppContentFeedExtractor.shared.extractLiveDigest(for: window).style

        switch digestStyle {
        case .aiAgentThread:
            return [
                AACVisualSymbolCard(
                    id: "ai_yes",
                    iconName: "checkmark.circle.fill",
                    emoji: "✅",
                    shortTitle: "YES, DO IT",
                    spokenConfirmation: "Sent: Yes, do it",
                    backgroundColor: Color(red: 0.12, green: 0.78, blue: 0.45),
                    foregroundColor: .black,
                    action: .sendPrompt("Yes, please do that and continue to the next step.", pressReturn: true)
                ),
                AACVisualSymbolCard(
                    id: "ai_explain",
                    iconName: "lightbulb.fill",
                    emoji: "💡",
                    shortTitle: "EXPLAIN SIMPLY",
                    spokenConfirmation: "Sent: Explain simply",
                    backgroundColor: Color(red: 0.22, green: 0.72, blue: 1.0),
                    foregroundColor: .black,
                    action: .sendPrompt("Please explain this in big, simple step-by-step points using plain words.", pressReturn: true)
                ),
                AACVisualSymbolCard(
                    id: "ai_fix",
                    iconName: "wrench.and.screwdriver.fill",
                    emoji: "🛠️",
                    shortTitle: "FIX PROBLEM",
                    spokenConfirmation: "Sent: Fix problem",
                    backgroundColor: Color(red: 1.0, green: 0.72, blue: 0.18),
                    foregroundColor: .black,
                    action: .sendPrompt("Something isn't working right. Please find the issue and fix it.", pressReturn: true)
                ),
                AACVisualSymbolCard(
                    id: "ai_steps",
                    iconName: "list.number",
                    emoji: "📋",
                    shortTitle: "NEXT STEP",
                    spokenConfirmation: "Sent: What is the next step",
                    backgroundColor: Color(red: 0.68, green: 0.52, blue: 1.0),
                    foregroundColor: .black,
                    action: .sendPrompt("What is the single most important next step?", pressReturn: true)
                ),
                AACVisualSymbolCard(
                    id: "ai_stop",
                    iconName: "hand.raised.fill",
                    emoji: "🛑",
                    shortTitle: "WAIT / STOP",
                    spokenConfirmation: "Sent: Wait and stop",
                    backgroundColor: Color(red: 0.96, green: 0.32, blue: 0.36),
                    foregroundColor: .white,
                    action: .sendPrompt("Please stop and wait for my next instruction.", pressReturn: true)
                )
            ]

        case .messagingChat:
            return [
                AACVisualSymbolCard(
                    id: "msg_yes",
                    iconName: "hand.thumbsup.fill",
                    emoji: "👍",
                    shortTitle: "YES 👍",
                    spokenConfirmation: "Sent: Yes, sounds good",
                    backgroundColor: Color(red: 0.12, green: 0.78, blue: 0.45),
                    foregroundColor: .black,
                    action: .sendPrompt("Yes, sounds good! 👍", pressReturn: true)
                ),
                AACVisualSymbolCard(
                    id: "msg_no",
                    iconName: "hand.thumbsdown.fill",
                    emoji: "👎",
                    shortTitle: "NO THANKS",
                    spokenConfirmation: "Sent: No thank you",
                    backgroundColor: Color(red: 0.96, green: 0.32, blue: 0.36),
                    foregroundColor: .white,
                    action: .sendPrompt("No thank you.", pressReturn: true)
                ),
                AACVisualSymbolCard(
                    id: "msg_omw",
                    iconName: "car.fill",
                    emoji: "🚗",
                    shortTitle: "ON MY WAY",
                    spokenConfirmation: "Sent: I am on my way",
                    backgroundColor: Color(red: 0.22, green: 0.72, blue: 1.0),
                    foregroundColor: .black,
                    action: .sendPrompt("I'm on my way!", pressReturn: true)
                ),
                AACVisualSymbolCard(
                    id: "msg_wait",
                    iconName: "clock.fill",
                    emoji: "⏳",
                    shortTitle: "NEED TIME",
                    spokenConfirmation: "Sent: Give me a few minutes",
                    backgroundColor: Color(red: 1.0, green: 0.72, blue: 0.18),
                    foregroundColor: .black,
                    action: .sendPrompt("Please give me a few minutes, I'll reply soon.", pressReturn: true)
                ),
                AACVisualSymbolCard(
                    id: "msg_thanks",
                    iconName: "heart.fill",
                    emoji: "❤️",
                    shortTitle: "THANK YOU",
                    spokenConfirmation: "Sent: Thank you",
                    backgroundColor: Color(red: 0.96, green: 0.46, blue: 0.76),
                    foregroundColor: .black,
                    action: .sendPrompt("Thank you! ❤️", pressReturn: true)
                )
            ]

        case .browserDocument, .mediaNowPlaying, .systemInspector:
            return [
                AACVisualSymbolCard(
                    id: "nav_up",
                    iconName: "arrow.up.circle.fill",
                    emoji: "⬆️",
                    shortTitle: "SCROLL UP",
                    spokenConfirmation: "Scroll up",
                    backgroundColor: Color(red: 0.22, green: 0.72, blue: 1.0),
                    foregroundColor: .black,
                    action: .scrollWindow(deltaY: 9)
                ),
                AACVisualSymbolCard(
                    id: "nav_down",
                    iconName: "arrow.down.circle.fill",
                    emoji: "⬇️",
                    shortTitle: "SCROLL DOWN",
                    spokenConfirmation: "Scroll down",
                    backgroundColor: Color(red: 0.22, green: 0.72, blue: 1.0),
                    foregroundColor: .black,
                    action: .scrollWindow(deltaY: -9)
                ),
                AACVisualSymbolCard(
                    id: "nav_zoom_in",
                    iconName: "plus.magnifyingglass",
                    emoji: "🔍",
                    shortTitle: "ZOOM BIGGER",
                    spokenConfirmation: "Zooming app bigger",
                    backgroundColor: Color(red: 0.12, green: 0.78, blue: 0.45),
                    foregroundColor: .black,
                    action: .sendKeyCombo(keyCode: 24, flags: .maskCommand, spokenLabel: "Zoom bigger") // Cmd + '='
                ),
                AACVisualSymbolCard(
                    id: "nav_back",
                    iconName: "arrow.backward.circle.fill",
                    emoji: "🔙",
                    shortTitle: "GO BACK",
                    spokenConfirmation: "Go back",
                    backgroundColor: Color(red: 1.0, green: 0.72, blue: 0.18),
                    foregroundColor: .black,
                    action: .sendKeyCombo(keyCode: 33, flags: .maskCommand, spokenLabel: "Go back") // Cmd + '['
                )
            ]
        }
    }
}

// MARK: - 3. Non-Verbal AAC Symbol Strip View (Big Nearsighted Touch Cards on Every Tile)

struct AACSymbolActionStrip: View {
    @ObservedObject var viewModel: CommandCenterViewModel
    let window: MonitoredWindow
    let isCenterStage: Bool

    var body: some View {
        let cards = AACVisualSymbolCard.cards(for: window)
        let visibleCards = isCenterStage ? cards : Array(cards.prefix(3))

        VStack(alignment: .leading, spacing: isCenterStage ? 6 : 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: isCenterStage ? 8 : 6) {
                    // 1-Tap AAC Picture-Symbol Cards
                    ForEach(visibleCards) { card in
                        Button {
                            viewModel.executeAACSymbolCard(card, for: window)
                        } label: {
                            HStack(spacing: isCenterStage ? 7 : 5) {
                                Image(systemName: card.iconName)
                                    .font(.system(size: isCenterStage ? 19 : 15, weight: .black))
                                Text(card.shortTitle)
                                    .font(.system(size: isCenterStage ? 15.5 : 13, weight: .black, design: .rounded))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, isCenterStage ? 14 : 10)
                            .padding(.vertical, isCenterStage ? 10 : 7)
                            .background(card.backgroundColor)
                            .foregroundColor(card.foregroundColor)
                            .clipShape(RoundedRectangle(cornerRadius: 11))
                            .overlay(
                                RoundedRectangle(cornerRadius: 11)
                                    .stroke(Color.white.opacity(0.45), lineWidth: 1.5)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    // Big Scroll Up / Down Buttons on Center Stage
                    if isCenterStage {
                        Button {
                            viewModel.scrollWindowInBackground(window, deltaY: 9)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 16, weight: .black))
                                Text("UP")
                                    .font(.system(size: 14, weight: .black, design: .rounded))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.16))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 11))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            viewModel.scrollWindowInBackground(window, deltaY: -9)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 16, weight: .black))
                                Text("DOWN")
                                    .font(.system(size: 14, weight: .black, design: .rounded))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.16))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 11))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, isCenterStage ? 12 : 8)
        .padding(.vertical, isCenterStage ? 9 : 6)
        .background(Color(red: 0.05, green: 0.07, blue: 0.12).opacity(0.96))
    }
}
